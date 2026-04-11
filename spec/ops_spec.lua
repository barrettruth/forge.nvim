vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('shared operations', function()
  local captured
  local old_system
  local old_fn_system
  local old_ui_select
  local old_preload

  before_each(function()
    captured = {
      commands = {},
      infos = {},
      errors = {},
      sessions = {},
      opened = 0,
      summaries = {},
      logs = {},
      terms = {},
    }

    old_system = vim.system
    old_fn_system = vim.fn.system
    old_ui_select = vim.ui.select
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.log'] = package.preload['forge.log'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.review'] = package.preload['forge.review'],
      ['forge.term'] = package.preload['forge.term'],
    }

    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git branch --show-current' then
        return 'feature\n'
      end
      return ''
    end

    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      captured.commands[#captured.commands + 1] = key
      if key == 'pr-base 42' then
        result.stdout = 'main\n'
      end
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    vim.ui.select = function(_, _, cb)
      cb('Yes')
    end

    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          captured.infos[#captured.infos + 1] = msg
        end,
        error = function(msg)
          captured.errors[#captured.errors + 1] = msg
        end,
        debug = function() end,
        warn = function() end,
      }
    end

    package.preload['forge.log'] = function()
      return {
        open_summary = function(cmd, opts)
          table.insert(captured.summaries, { cmd = cmd, opts = opts })
        end,
        open = function(cmd, opts)
          table.insert(captured.logs, { cmd = cmd, opts = opts })
        end,
      }
    end

    package.preload['forge.term'] = function()
      return {
        open = function(cmd, opts)
          table.insert(captured.terms, { cmd = cmd, opts = opts })
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        remote_ref = function(_, branch)
          return 'origin/' .. branch
        end,
        open = function() end,
      }
    end

    package.preload['forge.review'] = function()
      return {
        start_session = function(session)
          captured.sessions[#captured.sessions + 1] = session
        end,
        open_index = function()
          captured.opened = captured.opened + 1
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.review'] = nil
    package.loaded['forge.term'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.system = old_fn_system
    vim.ui.select = old_ui_select

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.log'] = old_preload['forge.log']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.review'] = old_preload['forge.review']
    package.preload['forge.term'] = old_preload['forge.term']

    package.loaded['forge'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.review'] = nil
    package.loaded['forge.term'] = nil
  end)

  it('starts PR review sessions through the shared operation', function()
    local ops = require('forge.ops')
    ops.pr_review({
      labels = { pr_one = 'PR' },
      checkout_cmd = function(_, num)
        return { 'checkout', num }
      end,
      pr_base_cmd = function(_, num)
        return { 'pr-base', num }
      end,
    }, { num = '42' })

    vim.wait(100, function()
      return captured.opened == 1
    end)

    assert.same({ 'checkout 42', 'pr-base 42' }, captured.commands)
    assert.equals('origin/main', captured.sessions[1].subject.base_ref)
    assert.equals('feature', captured.sessions[1].subject.head_ref)
    assert.equals('/repo', captured.sessions[1].repo_root)
    assert.equals(1, captured.opened)
  end)

  it('runs PR close commands and success callbacks through the shared operation', function()
    local done = 0
    local ops = require('forge.ops')
    ops.pr_close({
      labels = { pr_one = 'PR' },
      close_cmd = function(_, num)
        return { 'close', num }
      end,
    }, { num = '42' }, {
      on_success = function()
        done = done + 1
      end,
    })

    vim.wait(100, function()
      return done == 1
    end)

    assert.same({ 'close 42' }, captured.commands)
    assert.equals(1, done)
  end)

  it('runs PR merge commands without requiring a method', function()
    local done = 0
    local ops = require('forge.ops')
    ops.pr_merge(
      {
        labels = { pr_one = 'PR' },
        merge_cmd = function(_, num, method)
          return { 'merge', num, method or 'default' }
        end,
      },
      { num = '42' },
      nil,
      {
        on_success = function()
          done = done + 1
        end,
      }
    )

    vim.wait(100, function()
      return done == 1
    end)

    assert.same({ 'merge 42 default' }, captured.commands)
    assert.equals(1, done)
  end)

  it('confirms release deletion before running the shared delete operation', function()
    local done = 0
    local ops = require('forge.ops')
    ops.release_delete({
      delete_release_cmd = function(_, tag)
        return { 'delete', tag }
      end,
    }, { tag = 'v1.2.3' }, {
      on_success = function()
        done = done + 1
      end,
    })

    vim.wait(100, function()
      return done == 1
    end)

    assert.same({ 'delete v1.2.3' }, captured.commands)
    assert.equals(1, done)
  end)

  it('opens CI summaries through the shared log operation', function()
    local ops = require('forge.ops')
    ops.ci_log({
      name = 'github',
      summary_json_cmd = function(_, run_id, scope)
        return { 'summary', run_id, scope or 'none' }
      end,
      check_log_cmd = function(_, run_id, failed, job_id, scope)
        return { 'check-log', run_id, tostring(failed), job_id or '', scope or 'none' }
      end,
      steps_cmd = function(_, run_id, scope)
        return { 'steps', run_id, scope or 'none' }
      end,
      run_status_cmd = function(_, run_id, scope)
        return { 'status', run_id, scope or 'none' }
      end,
    }, {
      id = '77',
      name = 'CI',
      status = 'running',
      url = 'https://example.com/runs/77',
      scope = 'repo/ref',
    })

    assert.same({ 'summary', '77', 'repo/ref' }, captured.summaries[1].cmd)
    local summary_opts = vim.deepcopy(captured.summaries[1].opts)
    summary_opts.log_cmd_fn = nil
    assert.same({
      forge_name = 'github',
      run_id = '77',
      url = 'https://example.com/runs/77',
      title = 'CI',
      in_progress = true,
      status_cmd = { 'status', '77', 'repo/ref' },
      json = true,
    }, summary_opts)

    local cmd, opts = captured.summaries[1].opts.log_cmd_fn('job-1', true)
    assert.same({ 'check-log', '77', 'true', 'job-1', 'repo/ref' }, cmd)
    assert.same({
      forge_name = 'github',
      url = 'https://example.com/runs/77',
      title = 'CI / job-1',
      steps_cmd = { 'steps', '77', 'repo/ref' },
      job_id = 'job-1',
      in_progress = true,
      status_cmd = { 'status', '77', 'repo/ref' },
    }, opts)
  end)

  it('opens CI logs and watches through the shared operations', function()
    local ops = require('forge.ops')
    ops.ci_log({
      name = 'gitlab',
      run_log_cmd = function(_, run_id, failed, scope)
        return { 'run-log', run_id, tostring(failed), scope or 'none' }
      end,
      steps_cmd = function(_, run_id, scope)
        return { 'steps', run_id, scope or 'none' }
      end,
      run_status_cmd = function(_, run_id, scope)
        return { 'status', run_id, scope or 'none' }
      end,
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
    }, {
      id = '88',
      name = 'Deploy',
      status = 'failed',
      url = 'https://example.com/runs/88',
      scope = 'repo/ref',
    })
    local watched = ops.ci_watch({
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
    }, {
      id = '88',
      url = 'https://example.com/runs/88',
      scope = 'repo/ref',
    })

    assert.same({ 'run-log', '88', 'true', 'repo/ref' }, captured.logs[1].cmd)
    assert.same({
      forge_name = 'gitlab',
      url = 'https://example.com/runs/88',
      title = 'Deploy',
      steps_cmd = { 'steps', '88', 'repo/ref' },
      in_progress = false,
      status_cmd = { 'status', '88', 'repo/ref' },
    }, captured.logs[1].opts)
    assert.is_true(watched)
    assert.same({ 'watch', '88', 'repo/ref' }, captured.terms[1].cmd)
    assert.same({ url = 'https://example.com/runs/88' }, captured.terms[1].opts)
  end)
end)
