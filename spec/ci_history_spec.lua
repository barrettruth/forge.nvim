vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('ci history buffer', function()
  local old_system
  local old_preload
  local captured

  local scope = {
    kind = 'github',
    host = 'github.com',
    slug = 'owner/repo',
    repo_arg = 'owner/repo',
    web_url = 'https://github.com/owner/repo',
  }

  before_each(function()
    captured = {
      opened = {},
      browsed = {},
    }
    old_system = vim.system
    old_preload = helpers.capture_preload({
      'forge',
      'forge.layout',
      'forge.logger',
      'forge.ops',
      'forge.scope',
      'forge.system',
    })

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            split = 'horizontal',
            ci = { refresh = 5 },
            display = { limits = { runs = 30 } },
            keys = {
              ci = {
                refresh = '<c-r>',
              },
              log = {
                next_step = ']]',
                prev_step = '[[',
              },
            },
          }
        end,
        filter_runs = function(runs)
          return runs
        end,
        format_runs = function(runs)
          local rows = {}
          for _, run in ipairs(runs) do
            rows[#rows + 1] = {
              { run.name, run.status == 'failure' and 'ForgeFail' or 'ForgePass' },
            }
          end
          return rows
        end,
      }
    end

    package.preload['forge.layout'] = function()
      return {
        picker_width = function()
          return 80
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        error = function() end,
      }
    end

    package.preload['forge.ops'] = function()
      return {
        ci_open = function(_, run)
          captured.opened[#captured.opened + 1] = run
        end,
        ci_browse = function(_, run)
          captured.browsed[#captured.browsed + 1] = run
        end,
      }
    end

    package.preload['forge.scope'] = function()
      return {
        bufpath = function()
          return 'github.com/owner/repo'
        end,
        branch_web_url = function(_, branch)
          return 'https://github.com/owner/repo/tree/' .. branch
        end,
      }
    end

    package.preload['forge.system'] = function()
      return {
        cmd_error = function(result, fallback)
          return result.stderr ~= '' and result.stderr or fallback
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.ci_history'] = nil
    package.loaded['forge.layout'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.scope'] = nil
    package.loaded['forge.system'] = nil
  end)

  after_each(function()
    vim.system = old_system

    helpers.restore_preload(old_preload)
    package.loaded['forge'] = nil
    package.loaded['forge.ci_history'] = nil
    package.loaded['forge.layout'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.scope'] = nil
    package.loaded['forge.system'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^forge://') then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    vim.cmd('silent! %bwipeout!')
    vim.cmd('enew!')
  end)

  it('opens recent runs in a buffer and routes enter through ops.ci_open', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '123',
            name = 'CI',
            branch = 'main',
            status = 'success',
            url = 'https://example.com/runs/123',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.ci_history')
    mod.open({
      name = 'github',
      labels = { ci_inline = 'runs' },
      list_runs_json_cmd = function(_, branch, _, limit)
        return { 'runs', branch, tostring(limit) }
      end,
      normalize_run = function(_, run)
        return run
      end,
    }, {
      branch = 'main',
      scope = scope,
    })

    local buf = vim.api.nvim_get_current_buf()
    assert.equals('forge://github.com/owner/repo/ci/main', vim.api.nvim_buf_get_name(buf))
    assert.equals('forgelist', vim.bo[buf].filetype)
    assert.same({
      version = 1,
      kind = 'ci_history',
      url = 'https://github.com/owner/repo/tree/main',
    }, vim.b[buf].forge)
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'CI'
    end)
    assert.same({ 'CI' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    local enter = vim.fn.maparg('<cr>', 'n', false, true).callback
    enter()

    assert.same({
      id = '123',
      scope = scope,
      status = 'success',
      url = 'https://example.com/runs/123',
    }, captured.opened[1])
  end)

  it('routes gx through ops.ci_browse for the highlighted run', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '456',
            name = 'Lint',
            branch = 'main',
            status = 'failure',
            url = 'https://example.com/runs/456',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.ci_history')
    mod.open({
      name = 'github',
      labels = { ci_inline = 'runs' },
      list_runs_json_cmd = function(_, branch, _, limit)
        return { 'runs', branch, tostring(limit) }
      end,
      normalize_run = function(_, run)
        return run
      end,
    }, {
      branch = 'main',
      scope = scope,
    })

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'Lint'
    end)
    local browse = vim.fn.maparg('gx', 'n', false, true).callback
    browse()

    assert.same({
      id = '456',
      scope = scope,
      status = 'failure',
      url = 'https://example.com/runs/456',
    }, captured.browsed[1])
  end)
end)
