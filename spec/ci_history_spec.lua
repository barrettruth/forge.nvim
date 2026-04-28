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
    package.loaded['forge.log'] = nil
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
    package.loaded['forge.log'] = nil
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
    assert.equals('forge://github.com/owner/repo/ci/branch/main', vim.api.nvim_buf_get_name(buf))
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

  it('loads older runs with ]c when more branch history is available', function()
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = cmd
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'Newest',
            branch = 'main',
            status = 'success',
            url = 'https://example.com/runs/1',
          },
          {
            id = '2',
            name = 'Middle',
            branch = 'main',
            status = 'failure',
            url = 'https://example.com/runs/2',
          },
          {
            id = '3',
            name = 'Oldest',
            branch = 'main',
            status = 'success',
            url = 'https://example.com/runs/3',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            split = 'horizontal',
            ci = { refresh = 5 },
            display = { limits = { runs = 2 } },
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
            rows[#rows + 1] = { { run.name } }
          end
          return rows
        end,
      }
    end
    package.loaded['forge'] = nil

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
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2] == 'Middle'
    end)
    assert.same({ 'runs', 'main', '3' }, calls[1])
    assert.same({ 'Newest', 'Middle' }, vim.api.nvim_buf_get_lines(buf, 0, 2, false))

    local older = vim.fn.maparg(']c', 'n', false, true).callback
    older()

    vim.wait(100, function()
      return #calls == 2 and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3] == 'Oldest'
    end)
    assert.same({ 'runs', 'main', '5' }, calls[2])
    assert.same({ 'Newest', 'Middle', 'Oldest' }, vim.api.nvim_buf_get_lines(buf, 0, 3, false))
  end)

  it('shrinks the current-branch history window with [c after loading more', function()
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = cmd
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'Newest',
            branch = 'main',
            status = 'success',
            url = 'https://example.com/runs/1',
          },
          {
            id = '2',
            name = 'Middle',
            branch = 'main',
            status = 'failure',
            url = 'https://example.com/runs/2',
          },
          {
            id = '3',
            name = 'Oldest',
            branch = 'main',
            status = 'success',
            url = 'https://example.com/runs/3',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            split = 'horizontal',
            ci = { refresh = 5 },
            display = { limits = { runs = 2 } },
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
            rows[#rows + 1] = { { run.name } }
          end
          return rows
        end,
      }
    end
    package.loaded['forge'] = nil

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
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2] == 'Middle'
    end)

    vim.fn.maparg(']c', 'n', false, true).callback()
    vim.wait(100, function()
      return #calls == 2 and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3] == 'Oldest'
    end)

    vim.fn.maparg('[c', 'n', false, true).callback()
    vim.wait(100, function()
      return #calls == 3 and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3] == nil
    end)
    assert.same({ 'runs', 'main', '3' }, calls[3])
    assert.same({ 'Newest', 'Middle' }, vim.api.nvim_buf_get_lines(buf, 0, 2, false))
  end)

  it('keeps branch history distinct from same-id run summary buffers', function()
    vim.system = function(cmd, _, cb)
      if cmd[1] == 'runs' then
        cb({
          code = 0,
          stdout = vim.json.encode({
            {
              id = '123',
              name = 'Branch CI',
              branch = '123',
              status = 'success',
              url = 'https://example.com/runs/123',
            },
          }),
        })
      else
        cb({
          code = 0,
          stdout = '✓ summary job (ID 1)',
        })
      end
      return {
        kill = function() end,
      }
    end

    local ci_history = require('forge.ci_history')
    local log_mod = require('forge.log')

    ci_history.open({
      name = 'github',
      labels = { ci_inline = 'runs' },
      list_runs_json_cmd = function(_, branch, _, limit)
        return { 'runs', branch, tostring(limit) }
      end,
      normalize_run = function(_, run)
        return run
      end,
    }, {
      branch = '123',
      scope = scope,
    })

    local branch_buf = vim.api.nvim_get_current_buf()
    assert.equals(
      'forge://github.com/owner/repo/ci/branch/123',
      vim.api.nvim_buf_get_name(branch_buf)
    )
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(branch_buf, 0, -1, false)[1] == 'Branch CI'
    end)

    log_mod.open_summary({ 'summary', '123' }, {
      forge_name = 'github',
      scope = scope,
      run_id = '123',
      url = 'https://example.com/runs/123',
    })

    local summary_buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(summary_buf, 0, -1, false)[1] == '✓ summary job (ID 1)'
    end)
    assert.equals(
      'forge://github.com/owner/repo/ci/run/123',
      vim.api.nvim_buf_get_name(summary_buf)
    )
    assert.is_not.equals(branch_buf, summary_buf)
    assert.same({ 'Branch CI' }, vim.api.nvim_buf_get_lines(branch_buf, 0, -1, false))
    assert.same({ '✓ summary job (ID 1)' }, vim.api.nvim_buf_get_lines(summary_buf, 0, -1, false))
  end)

  it('keeps branch history distinct from same-id run log buffers', function()
    vim.system = function(cmd, _, cb)
      if cmd[1] == 'runs' then
        cb({
          code = 0,
          stdout = vim.json.encode({
            {
              id = '321',
              name = 'Slash Branch',
              branch = '123/log',
              status = 'success',
              url = 'https://example.com/runs/321',
            },
          }),
        })
      else
        cb({
          code = 0,
          stdout = 'build\tstep\t2024-01-01T00:00:00Z hello',
        })
      end
      return {
        kill = function() end,
      }
    end

    local ci_history = require('forge.ci_history')
    local log_mod = require('forge.log')

    ci_history.open({
      name = 'github',
      labels = { ci_inline = 'runs' },
      list_runs_json_cmd = function(_, branch, _, limit)
        return { 'runs', branch, tostring(limit) }
      end,
      normalize_run = function(_, run)
        return run
      end,
    }, {
      branch = '123/log',
      scope = scope,
    })

    local branch_buf = vim.api.nvim_get_current_buf()
    assert.equals(
      'forge://github.com/owner/repo/ci/branch/123/log',
      vim.api.nvim_buf_get_name(branch_buf)
    )
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(branch_buf, 0, -1, false)[1] == 'Slash Branch'
    end)

    log_mod.open({ 'log', '123' }, {
      forge_name = 'github',
      scope = scope,
      run_id = '123',
      url = 'https://example.com/runs/123',
    })

    local log_buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(log_buf, 0, -1, false)[1] == 'build'
    end)
    assert.equals(
      'forge://github.com/owner/repo/ci/run/123/log',
      vim.api.nvim_buf_get_name(log_buf)
    )
    assert.is_not.equals(branch_buf, log_buf)
    assert.same({ 'Slash Branch' }, vim.api.nvim_buf_get_lines(branch_buf, 0, -1, false))
    assert.same({ 'build' }, vim.api.nvim_buf_get_lines(log_buf, 0, 1, false))
  end)
end)
