vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('pr checks buffer', function()
  local old_system
  local old_ui_open
  local old_preload
  local captured

  local scope = {
    kind = 'github',
    host = 'github.com',
    slug = 'owner/repo',
    web_url = 'https://github.com/owner/repo',
  }

  before_each(function()
    captured = {
      logs = {},
      terms = {},
      urls = {},
    }
    old_system = vim.system
    old_ui_open = vim.ui.open
    old_preload = helpers.capture_preload({
      'forge',
      'forge.layout',
      'forge.log',
      'forge.logger',
      'forge.scope',
      'forge.system',
      'forge.term',
    })

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            split = 'horizontal',
            ci = { refresh = 5 },
            keys = {
              log = {
                next_step = ']]',
                prev_step = '[[',
                refresh = '<c-r>',
              },
            },
          }
        end,
        filter_checks = function(checks)
          return checks
        end,
        format_checks = function(checks)
          local rows = {}
          for _, check in ipairs(checks) do
            rows[#rows + 1] = {
              { check.name, check.bucket == 'fail' and 'ForgeFail' or 'ForgePass' },
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

    package.preload['forge.log'] = function()
      return {
        open = function(cmd, opts)
          captured.logs[#captured.logs + 1] = { cmd = cmd, opts = opts }
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        error = function() end,
      }
    end

    package.preload['forge.scope'] = function()
      return {
        bufpath = function()
          return 'github.com/owner/repo'
        end,
        subject_web_url = function(_, num)
          return 'https://github.com/owner/repo/pull/' .. num
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

    package.preload['forge.term'] = function()
      return {
        open = function(cmd, opts)
          captured.terms[#captured.terms + 1] = { cmd = cmd, opts = opts }
        end,
      }
    end

    vim.ui.open = function(url)
      captured.urls[#captured.urls + 1] = url
    end

    package.loaded['forge'] = nil
    package.loaded['forge.layout'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pr_checks'] = nil
    package.loaded['forge.scope'] = nil
    package.loaded['forge.system'] = nil
    package.loaded['forge.term'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open

    helpers.restore_preload(old_preload)
    package.loaded['forge'] = nil
    package.loaded['forge.layout'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.scope'] = nil
    package.loaded['forge.system'] = nil
    package.loaded['forge.term'] = nil
    package.loaded['forge.pr_checks'] = nil

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

  it('opens completed checks in a buffer and routes enter to check logs', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            name = 'lint',
            bucket = 'fail',
            link = 'https://example.com/actions/runs/123/job/456',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.pr_checks')
    mod.open({
      name = 'github',
      labels = { pr_one = 'PR' },
      capabilities = { per_pr_checks = true },
      checks_json_cmd = function()
        return { 'checks', '42' }
      end,
      check_log_cmd = function(_, run_id, failed, job_id)
        return { 'log', run_id, tostring(failed), job_id or '' }
      end,
    }, {
      num = '42',
      scope = scope,
    })

    local buf = vim.api.nvim_get_current_buf()
    assert.equals('forge://github.com/owner/repo/pr/42/checks', vim.api.nvim_buf_get_name(buf))
    assert.equals('forgelist', vim.bo[buf].filetype)
    assert.same({
      version = 1,
      kind = 'pr_checks',
      url = 'https://github.com/owner/repo/pull/42',
    }, vim.b[buf].forge)
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'lint'
    end)
    assert.same({ 'lint' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    local enter = vim.fn.maparg('<cr>', 'n', false, true).callback
    local win = vim.api.nvim_get_current_win()
    enter()

    assert.same({
      cmd = { 'log', '123', 'true', '456' },
      opts = {
        forge_name = 'github',
        scope = scope,
        run_id = '123',
        url = 'https://example.com/actions/runs/123/job/456',
        steps_cmd = nil,
        job_id = '456',
        in_progress = false,
        status_cmd = nil,
        replace_win = win,
      },
    }, captured.logs[1])
  end)

  it('trims trailing padding from rendered check rows before writing the buffer', function()
    package.preload['forge'] = function()
      return {
        config = function()
          return {
            split = 'horizontal',
            ci = { refresh = 5 },
            keys = {
              log = {
                next_step = ']]',
                prev_step = '[[',
                refresh = '<c-r>',
              },
            },
          }
        end,
        filter_checks = function(checks)
          return checks
        end,
        format_checks = function()
          return {
            {
              { 'lint', 'ForgeFail' },
              { ' [web]   ', 'ForgeDim' },
            },
          }
        end,
      }
    end
    package.loaded['forge'] = nil
    package.loaded['forge.pr_checks'] = nil

    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            name = 'lint',
            bucket = 'fail',
            link = 'https://example.com/actions/runs/123/job/456',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.pr_checks')
    mod.open({
      name = 'github',
      labels = { pr_one = 'PR' },
      capabilities = { per_pr_checks = true },
      checks_json_cmd = function()
        return { 'checks', '42' }
      end,
      check_log_cmd = function(_, run_id, failed, job_id)
        return { 'log', run_id, tostring(failed), job_id or '' }
      end,
    }, {
      num = '42',
      scope = scope,
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'lint [web]'
    end)

    assert.same({ 'lint [web]' }, vim.api.nvim_buf_get_lines(buf, 0, 1, false))
  end)

  it('routes pending checks through live tail when available', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            name = 'test',
            bucket = 'pending',
            run_id = '123',
            job_id = '456',
            link = 'https://example.com/actions/runs/123/job/456',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.pr_checks')
    mod.open({
      name = 'github',
      labels = { pr_one = 'PR' },
      capabilities = { per_pr_checks = true },
      checks_json_cmd = function()
        return { 'checks', '42' }
      end,
      check_log_cmd = function()
        return { 'log' }
      end,
      live_tail_cmd = function(_, run_id, job_id)
        return { 'tail', run_id, job_id }
      end,
    }, {
      num = '42',
      scope = scope,
    })

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'test'
    end)
    local enter = vim.fn.maparg('<cr>', 'n', false, true).callback
    enter()

    assert.same({
      cmd = { 'tail', '123', '456' },
      opts = {
        url = 'https://example.com/actions/runs/123/job/456',
      },
    }, captured.terms[1])
    assert.same({}, captured.logs)
  end)

  it('renders browse-only checks explicitly and opens them in the browser on enter', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            name = 'skipped',
            bucket = 'skipping',
            link = 'https://example.com/actions/runs/123/job/456',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.pr_checks')
    mod.open({
      name = 'github',
      labels = { pr_one = 'PR' },
      capabilities = { per_pr_checks = true },
      checks_json_cmd = function()
        return { 'checks', '42' }
      end,
      check_log_cmd = function()
        return { 'log' }
      end,
    }, {
      num = '42',
      scope = scope,
    })

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'skipped [web]'
    end)
    vim.fn.maparg('<cr>', 'n', false, true).callback()

    assert.same({ 'https://example.com/actions/runs/123/job/456' }, captured.urls)
    assert.same({}, captured.logs)
    assert.same({}, captured.terms)
  end)

  it('renders unavailable checks explicitly and leaves enter inert', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            name = 'waiting',
            bucket = 'skipping',
          },
        }),
      })
      return {
        kill = function() end,
      }
    end

    local mod = require('forge.pr_checks')
    mod.open({
      name = 'github',
      labels = { pr_one = 'PR' },
      capabilities = { per_pr_checks = true },
      checks_json_cmd = function()
        return { 'checks', '42' }
      end,
      check_log_cmd = function()
        return { 'log' }
      end,
    }, {
      num = '42',
      scope = scope,
    })

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'waiting [unavailable]'
    end)
    vim.fn.maparg('<cr>', 'n', false, true).callback()

    assert.same({}, captured.urls)
    assert.same({}, captured.logs)
    assert.same({}, captured.terms)
  end)
end)
