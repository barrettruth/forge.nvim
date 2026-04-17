vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('shared operations', function()
  local captured
  local old_system
  local old_fn_system
  local old_ui_select
  local old_ui_open
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
      urls = {},
    }

    old_system = vim.system
    old_fn_system = vim.fn.system
    old_ui_select = vim.ui.select
    old_ui_open = vim.ui.open
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.log'] = package.preload['forge.log'],
      ['forge.logger'] = package.preload['forge.logger'],
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

    vim.ui.open = function(url)
      captured.urls[#captured.urls + 1] = url
      return {}, nil
    end

    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          captured.infos[#captured.infos + 1] = msg
        end,
        warn = function(msg)
          captured.infos[#captured.infos + 1] = msg
        end,
        error = function(msg)
          captured.errors[#captured.errors + 1] = msg
        end,
        debug = function() end,
      }
    end

    package.preload['forge.log'] = function()
      return {
        _summary_job_at_line = function(_, lnum)
          if lnum == 2 then
            return { id = '22', failed = true }
          end
        end,
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

    package.loaded['forge'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.term'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.system = old_fn_system
    vim.ui.select = old_ui_select
    vim.ui.open = old_ui_open

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.log'] = old_preload['forge.log']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.term'] = old_preload['forge.term']

    package.loaded['forge'] = nil
    package.loaded['forge.log'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.term'] = nil
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

  it('opens GitHub CI run views in a terminal buffer', function()
    local ops = require('forge.ops')
    ops.ci_log({
      name = 'github',
      view_cmd = function(_, run_id, opts)
        return { 'view', run_id, opts and opts.scope or 'none' }
      end,
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
      job_web_url = function(_, run_id, job_id, scope)
        return ('https://example.com/runs/%s/jobs/%s/%s'):format(run_id, job_id, scope or 'none')
      end,
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
      scope = 'repo/ref',
    })

    assert.same({ 'view', '77', 'repo/ref' }, captured.terms[1].cmd)
    local term_opts = vim.deepcopy(captured.terms[1].opts)
    term_opts.browse_fn, term_opts.enter_fn = nil, nil
    assert.same({
      url = 'https://example.com/runs/77/repo/ref',
      startinsert = false,
    }, term_opts)
  end)

  it('gives GitHub CI watch the same contextual terminal actions', function()
    local ops = require('forge.ops')
    ops.ci_watch({
      name = 'github',
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
      check_log_cmd = function(_, run_id, failed, job_id, scope)
        return { 'check-log', run_id, tostring(failed), job_id or '', scope or 'none' }
      end,
      run_status_cmd = function(_, run_id, scope)
        return { 'status', run_id, scope or 'none' }
      end,
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
      job_web_url = function(_, run_id, job_id, scope)
        return ('https://example.com/runs/%s/jobs/%s/%s'):format(run_id, job_id, scope or 'none')
      end,
      steps_cmd = function(_, run_id, scope)
        return { 'steps', run_id, scope or 'none' }
      end,
    }, {
      id = '88',
      name = 'Deploy',
      status = 'running',
      scope = 'repo/ref',
    })

    assert.same({ 'watch', '88', 'repo/ref' }, captured.terms[1].cmd)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '  * Run busted' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local win = vim.api.nvim_get_current_win()

    local browse_url = captured.terms[1].opts.browse_fn(buf)
    captured.terms[1].opts.enter_fn(buf)

    local term_opts = vim.deepcopy(captured.terms[1].opts)
    term_opts.browse_fn, term_opts.enter_fn = nil, nil
    assert.same({
      url = 'https://example.com/runs/88/repo/ref',
      startinsert = false,
    }, term_opts)
    assert.equals('https://example.com/runs/88/jobs/22/repo/ref', browse_url)
    assert.same({ 'check-log', '88', 'true', '22', 'repo/ref' }, captured.logs[1].cmd)
    assert.same({
      forge_name = 'github',
      scope = 'repo/ref',
      run_id = '88',
      url = 'https://example.com/runs/88/jobs/22/repo/ref',
      steps_cmd = { 'steps', '88', 'repo/ref' },
      job_id = '22',
      replace_win = win,
      in_progress = true,
      status_cmd = { 'status', '88', 'repo/ref' },
    }, captured.logs[1].opts)
    assert.same({
      'GitHub does not support per-job live watch; opening a refreshing job log instead',
    }, captured.infos)
  end)

  it('opens in-progress CI runs via watch when available', function()
    local ops = require('forge.ops')
    ops.ci_open({
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
    }, {
      id = '88',
      status = 'running',
      scope = 'repo/ref',
    })

    assert.same({ 'watch', '88', 'repo/ref' }, captured.terms[1].cmd)
    assert.same({ url = 'https://example.com/runs/88/repo/ref' }, captured.terms[1].opts)
  end)

  it('opens completed CI runs via log', function()
    local ops = require('forge.ops')
    ops.ci_open({
      name = 'gitlab',
      run_log_cmd = function(_, run_id, failed, scope)
        return { 'run-log', run_id, tostring(failed), scope or 'none' }
      end,
      steps_cmd = function(_, run_id, scope)
        return { 'steps', run_id, scope or 'none' }
      end,
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
    }, {
      id = '89',
      status = 'failed',
      scope = 'repo/ref',
    })

    assert.same({ 'run-log', '89', 'true', 'repo/ref' }, captured.logs[1].cmd)
  end)

  it('falls back to JSON CI summaries when no run view is available', function()
    local ops = require('forge.ops')
    ops.ci_log({
      name = 'custom',
      summary_json_cmd = function(_, run_id, scope)
        return { 'summary', run_id, scope or 'none' }
      end,
      check_log_cmd = function(_, run_id, failed, job_id, scope)
        return { 'check-log', run_id, tostring(failed), job_id or '', scope or 'none' }
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
    summary_opts.log_cmd_fn, summary_opts.browse_url_fn = nil, nil
    assert.same({
      forge_name = 'custom',
      scope = 'repo/ref',
      run_id = '77',
      url = 'https://example.com/runs/77',
      in_progress = true,
      status_cmd = { 'status', '77', 'repo/ref' },
      json = true,
    }, summary_opts)
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
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
    }, {
      id = '88',
      name = 'Deploy',
      status = 'failed',
      scope = 'repo/ref',
    })
    local watched = ops.ci_watch({
      run_web_url = function(_, run_id, scope)
        return ('https://example.com/runs/%s/%s'):format(run_id, scope or 'none')
      end,
      watch_cmd = function(_, run_id, scope)
        return { 'watch', run_id, scope or 'none' }
      end,
    }, {
      id = '88',
      scope = 'repo/ref',
    })

    assert.same({ 'run-log', '88', 'true', 'repo/ref' }, captured.logs[1].cmd)
    assert.same({
      forge_name = 'gitlab',
      scope = 'repo/ref',
      run_id = '88',
      url = 'https://example.com/runs/88/repo/ref',
      steps_cmd = { 'steps', '88', 'repo/ref' },
      in_progress = false,
      status_cmd = { 'status', '88', 'repo/ref' },
    }, captured.logs[1].opts)
    assert.is_true(watched)
    assert.same({ 'watch', '88', 'repo/ref' }, captured.terms[1].cmd)
    assert.same({ url = 'https://example.com/runs/88/repo/ref' }, captured.terms[1].opts)
  end)

  it('list_browse opens the forge list landing page', function()
    local ops = require('forge.ops')
    local f = {
      name = 'github',
      list_web_url = function(_, kind, scope)
        return ('https://example.com/%s/%s'):format(scope or 'repo', kind)
      end,
    }

    ops.list_browse(f, 'pr', { scope = 'owner/repo' })
    ops.list_browse(f, 'issue')

    assert.same(
      { 'https://example.com/owner/repo/pr', 'https://example.com/repo/issue' },
      captured.urls
    )
    assert.same({}, captured.errors)
  end)

  it('list_browse warns when the source has no landing page for the kind', function()
    local ops = require('forge.ops')
    local f = {
      name = 'codeberg',
      list_web_url = function()
        return nil
      end,
    }

    ops.list_browse(f, 'release', {})

    assert.same({}, captured.urls)
    assert.same({ 'codeberg does not support release landing pages' }, captured.infos)
  end)

  it('list_browse warns when the source has no list_web_url method at all', function()
    local ops = require('forge.ops')
    ops.list_browse({ name = 'custom' }, 'ci', {})

    assert.same({}, captured.urls)
    assert.same({ 'custom does not support ci landing pages' }, captured.infos)
  end)

  it('ci_browse opens a backend run page', function()
    local ops = require('forge.ops')
    local f = {
      browse_run = function(_, id, scope)
        table.insert(captured.urls, ('https://example.com/runs/%s/%s'):format(id, scope or 'none'))
      end,
    }

    ops.ci_browse(f, { id = '77', scope = 'owner/repo' })

    assert.same({ 'https://example.com/runs/77/owner/repo' }, captured.urls)
  end)

  it('ci_browse falls back to run_web_url when browse_run is unavailable', function()
    local ops = require('forge.ops')
    local f = {
      name = 'custom',
      run_web_url = function(_, id, scope)
        return ('https://example.com/runs/%s/%s'):format(id, scope or 'none')
      end,
    }

    ops.ci_browse(f, { id = '88', scope = 'owner/repo' })

    assert.same({ 'https://example.com/runs/88/owner/repo' }, captured.urls)
    assert.same({}, captured.errors)
  end)

  it('ci_browse warns when the source has no run page support', function()
    local ops = require('forge.ops')

    ops.ci_browse({ name = 'custom' }, { id = '88' })

    assert.same({}, captured.urls)
    assert.same({ 'custom does not support ci run pages' }, captured.infos)
  end)
end)
