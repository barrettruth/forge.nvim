vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local captured
local cache
local issue_create_calls
local issue_create_opts
local logger_messages
local op_calls
local pr_create_calls
local pr_create_opts
local default_system
local preload_modules = {
  'fzf-lua.utils',
  'forge',
  'forge.logger',
  'forge.ops',
  'forge.picker',
}
local loaded_modules = {
  'forge',
  'forge.config',
  'forge.logger',
  'forge.ops',
  'forge.picker',
  'forge.picker.session',
  'forge.pickers',
}

local function fake_forge()
  return {
    labels = { pr = 'PRs', pr_one = 'PR' },
    kinds = { pr = 'pull_request' },
    capabilities = { draft = true },
    pr_fields = {
      number = 'number',
      title = 'title',
      state = 'state',
      author = 'author',
      created_at = 'created_at',
    },
    repo_info = function()
      return {
        permission = 'WRITE',
        merge_methods = { 'merge' },
      }
    end,
    pr_state = function()
      return {
        state = 'OPEN',
        is_draft = false,
      }
    end,
    approve_cmd = function(_, num)
      return { 'approve', num }
    end,
    list_pr_json_cmd = function(_, state)
      return { 'prs', state }
    end,
    merge_cmd = function(_, num, method)
      return { 'merge', num, method }
    end,
    close_cmd = function(_, num)
      return { 'close', num }
    end,
    reopen_cmd = function(_, num)
      return { 'reopen', num }
    end,
    draft_toggle_cmd = function(_, num)
      return { 'draft', num }
    end,
  }
end

local function fake_issue_forge()
  return {
    labels = { issue = 'Issues' },
    kinds = { issue = 'issue' },
    issue_fields = {
      number = 'number',
      title = 'title',
      state = 'state',
      author = 'author',
      created_at = 'created_at',
    },
    view_web = function() end,
    list_issue_json_cmd = function(_, state)
      return { 'issues', state }
    end,
    close_issue_cmd = function(_, num)
      return { 'close', num }
    end,
    reopen_issue_cmd = function(_, num)
      return { 'reopen', num }
    end,
  }
end

local function fake_ci_forge()
  return {
    labels = { ci = 'CI', pr_one = 'PR' },
    check_log_cmd = function(_, run_id)
      return { 'log', run_id }
    end,
    checks_json_cmd = function(_, num)
      return { 'checks', num }
    end,
    list_runs_json_cmd = function(_, branch, _, limit)
      return { 'runs', branch or '', tostring(limit or '') }
    end,
    normalize_run = function(_, run)
      return run
    end,
  }
end

local function fake_release_forge()
  return {
    release_fields = {
      tag = 'tag',
      title = 'title',
      is_draft = 'is_draft',
      is_prerelease = 'is_prerelease',
    },
    browse_release = function() end,
    delete_release_cmd = function(_, tag)
      return { 'delete', tag }
    end,
    list_releases_json_cmd = function()
      return { 'releases' }
    end,
  }
end

local function action_by_name(name)
  return helpers.action_by_name(captured.actions, name)
end

describe('pickers', function()
  local old_preload

  before_each(function()
    captured = nil
    issue_create_calls = 0
    issue_create_opts = nil
    logger_messages = {
      info = {},
      warn = {},
      error = {},
      debug = {},
    }
    op_calls = {}
    pr_create_calls = 0
    pr_create_opts = nil
    default_system = vim.system
    vim.system = function(_, _, cb)
      if cb then
        cb({ code = 0, stdout = '[]' })
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
    cache = {
      ['pr:open'] = {
        { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      },
    }
    old_preload = helpers.capture_preload(preload_modules)
    package.preload['fzf-lua.utils'] = function()
      return {
        ansi_from_hl = function(_, text)
          return text
        end,
      }
    end
    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          table.insert(logger_messages.info, msg)
        end,
        error = function(msg)
          table.insert(logger_messages.error, msg)
        end,
        debug = function(msg)
          table.insert(logger_messages.debug, msg)
        end,
        warn = function(msg)
          table.insert(logger_messages.warn, msg)
        end,
      }
    end
    package.preload['forge.picker'] = function()
      return {
        backends = { ['fzf-lua'] = 'forge.picker.fzf' },
        backend = function()
          return 'fzf-lua'
        end,
        pick = function(opts)
          captured = opts
        end,
      }
    end
    package.preload['forge.ops'] = function()
      return {
        pr_checkout = function(_, pr)
          table.insert(op_calls, { name = 'pr_checkout', pr = pr })
        end,
        pr_browse = function(_, pr)
          table.insert(op_calls, { name = 'pr_browse', pr = pr })
        end,
        pr_worktree = function(_, pr)
          table.insert(op_calls, { name = 'pr_worktree', pr = pr })
        end,
        pr_ci = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_ci', pr = pr, opts = opts })
        end,
        pr_edit = function(pr)
          table.insert(op_calls, { name = 'pr_edit', pr = pr })
        end,
        pr_create = function(opts)
          require('forge').create_pr(opts)
        end,
        pr_close = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_close', pr = pr })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        pr_reopen = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_reopen', pr = pr })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        pr_approve = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_approve', pr = pr })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        pr_merge = function(_, pr, method, opts)
          table.insert(op_calls, { name = 'pr_merge', pr = pr, method = method })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        pr_toggle_draft = function(_, pr, is_draft, opts)
          table.insert(op_calls, { name = 'pr_toggle_draft', pr = pr, is_draft = is_draft })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        ci_log = function(_, run)
          table.insert(op_calls, { name = 'ci_log', run = run })
        end,
        ci_watch = function(_, run)
          table.insert(op_calls, { name = 'ci_watch', run = run })
        end,
        issue_browse = function(_, issue)
          table.insert(op_calls, { name = 'issue_browse', issue = issue })
        end,
        issue_edit = function(issue)
          table.insert(op_calls, { name = 'issue_edit', issue = issue })
        end,
        issue_create = function(opts)
          require('forge').create_issue(opts)
        end,
        issue_close = function(_, issue, opts)
          table.insert(op_calls, { name = 'issue_close', issue = issue, opts = opts })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        issue_reopen = function(_, issue, opts)
          table.insert(op_calls, { name = 'issue_reopen', issue = issue, opts = opts })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        release_browse = function(_, release)
          table.insert(op_calls, { name = 'release_browse', release = release })
        end,
        release_delete = function(_, release, opts)
          table.insert(op_calls, { name = 'release_delete', release = release })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
      }
    end
    package.preload['forge'] = function()
      return {
        config = require('forge.config').config,
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          return cache[key]
        end,
        set_list = function(key, value)
          cache[key] = value
        end,
        clear_list = function(key)
          if key then
            cache[key] = nil
          end
        end,
        format_prs = function(prs)
          return vim.tbl_map(function(pr)
            return {
              { '#' .. tostring(pr.number) },
              { ' ' .. (pr.title or '') },
            }
          end, prs)
        end,
        format_pr = function(pr)
          return {
            { '#' .. tostring(pr.number) },
            { ' ' .. (pr.title or '') },
          }
        end,
        format_issues = function(issues)
          return vim.tbl_map(function(issue)
            return {
              { '#' .. tostring(issue.number) },
              { ' ' .. (issue.title or '') },
            }
          end, issues)
        end,
        format_issue = function(issue)
          return {
            { '#' .. tostring(issue.number) },
            { ' ' .. (issue.title or '') },
          }
        end,
        format_checks = function(checks)
          return vim.tbl_map(function(check)
            return {
              { check.name or '' },
            }
          end, checks)
        end,
        format_check = function(check)
          return {
            { check.name or '' },
          }
        end,
        filter_checks = function(checks)
          return checks
        end,
        format_runs = function(runs)
          return vim.tbl_map(function(run)
            return {
              { run.name or '' },
            }
          end, runs)
        end,
        format_run = function(run)
          return {
            { run.name or '' },
          }
        end,
        filter_runs = function(runs)
          return runs
        end,
        format_releases = function(releases)
          return vim.tbl_map(function(rel)
            return {
              { tostring(rel.tag or '') },
              { ' ' .. (rel.title or '') },
            }
          end, releases)
        end,
        format_release = function(rel)
          return {
            { tostring(rel.tag or '') },
            { ' ' .. (rel.title or '') },
          }
        end,
        remote_web_url = function()
          return 'https://example.com/repo'
        end,
        repo_info = function(f)
          return f:repo_info()
        end,
        create_issue = function(...)
          issue_create_calls = issue_create_calls + 1
          issue_create_opts = select(1, ...)
        end,
        create_pr = function(...)
          pr_create_calls = pr_create_calls + 1
          pr_create_opts = select(1, ...)
        end,
        edit_pr = function() end,
      }
    end
    helpers.clear_loaded(loaded_modules)
    vim.g.forge = nil
  end)

  after_each(function()
    vim.system = default_system
    helpers.restore_preload(old_preload)
    helpers.clear_loaded(loaded_modules)
  end)

  it('uses more as the default PR action without a separate default key binding', function()
    local cfg = require('forge.config').config()
    assert.equals('<c-e>', cfg.keys.pr.edit)
    assert.equals('<c-y>', cfg.keys.pr.approve)
    assert.equals('<c-g>', cfg.keys.pr.merge)
    assert.equals('<c-a>', cfg.keys.pr.create)
    assert.equals('<c-s>', cfg.keys.pr.close)
    assert.equals('<c-d>', cfg.keys.pr.draft)
    assert.equals('<tab>', cfg.keys.ci.filter)

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('Open PRs (1)> ', captured.prompt)
    local labels = helpers.action_labels(captured.actions)
    assert.equals('checkout', labels.default)
    assert.equals('worktree', labels.worktree)
    assert.equals('edit', labels.edit)
    assert.equals('approve', labels.approve)
    assert.equals('merge', labels.merge)
    assert.equals('create', labels.create)
    assert.equals('close', labels.close)
    assert.equals('draft/ready', labels.draft)
    assert.equals('filter', labels.filter)
    assert.equals('prev', labels.filter_prev)
    assert.equals('refresh', labels.refresh)
  end)

  it('keeps auxiliary PR actions open', function()
    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('checkout', action_by_name('default').label)
    for _, case in ipairs({
      { name = 'browse', close = false },
      { name = 'worktree', close = false },
      { name = 'approve', close = nil },
      { name = 'merge', close = nil },
    }) do
      local close = rawget(action_by_name(case.name), 'close')
      if case.close == nil then
        assert.is_nil(close)
      else
        assert.equals(case.close, close)
      end
    end
  end)

  it('dispatches flattened PR actions directly from the root picker', function()
    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    local entry = captured.entries[1]
    action_by_name('default').fn(entry)
    action_by_name('edit').fn(entry)
    action_by_name('approve').fn(entry)
    action_by_name('merge').fn(entry)
    action_by_name('close').fn(entry)
    action_by_name('draft').fn(entry)

    assert.same({
      { name = 'pr_checkout', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      { name = 'pr_edit', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      { name = 'pr_approve', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      {
        name = 'pr_merge',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        method = nil,
      },
      { name = 'pr_close', pr = { num = '42', scope = nil } },
      {
        name = 'pr_toggle_draft',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        is_draft = false,
      },
    }, op_calls)
  end)

  it('shows an explicit empty PR row instead of a blank picker', function()
    cache['pr:open'] = {}

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('Open PRs (0)> ', captured.prompt)
    assert.equals('No open PRs', captured.entries[1].display[1][1])
    assert.is_true(captured.entries[1].placeholder)
  end)

  it('opens the PR picker immediately on fzf before the fetch completes', function()
    cache['pr:open'] = nil

    local old_system = vim.system
    local system_cb
    vim.system = function(_, _, cb)
      system_cb = cb
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('Open PRs> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    action_by_name('create').fn()
    assert.equals(1, pr_create_calls)

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.is_not_nil(system_cb)
    system_cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('42', streamed[1].value.num)
    assert.equals('#42', streamed[1].display[1][1])
    assert.same(42, cache['pr:open'][1].number)
  end)

  it('keeps back available on uncached streaming PR opens', function()
    cache['pr:open'] = nil
    local back_calls = 0

    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge(), {
      back = function()
        back_calls = back_calls + 1
      end,
    })

    assert.is_not_nil(captured)
    assert.is_function(captured.back)

    captured.back()

    assert.equals(1, back_calls)
    vim.system = old_system
  end)

  it('passes back through create actions from nested pickers', function()
    local pickers = require('forge.pickers')
    local back = function() end

    pickers.pr('open', fake_forge(), { back = back })
    action_by_name('create').fn()
    assert.same(back, pr_create_opts.back)

    pickers.issue('open', fake_issue_forge(), { back = back })
    action_by_name('create').fn()
    assert.same(back, issue_create_opts.back)
  end)

  it('ignores stale PR responses after a refresh starts a newer fetch', function()
    cache['pr:open'] = nil

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    local first = captured
    local first_streamed = {}
    first.stream(function(entry)
      if entry == nil then
        first_streamed.done = true
        return
      end
      first_streamed[#first_streamed + 1] = entry
    end)

    action_by_name('refresh').fn()

    local second = captured
    local second_streamed = {}
    second.stream(function(entry)
      if entry == nil then
        second_streamed.done = true
        return
      end
      second_streamed[#second_streamed + 1] = entry
    end)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 7, title = 'Older', state = 'OPEN', author = 'alice', created_at = '' },
      }),
    })
    calls[2].cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 42, title = 'Newer', state = 'OPEN', author = 'bob', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return first_streamed.done == true and second_streamed.done == true
    end)
    vim.system = old_system

    assert.is_nil(first_streamed[1])
    assert.equals('42', second_streamed[1].value.num)
    assert.same(42, cache['pr:open'][1].number)
  end)

  it('sorts PR entries by descending number', function()
    cache['pr:open'] = {
      { number = 7, title = 'Older', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 42, title = 'Newer', state = 'OPEN', author = 'bob', created_at = '' },
      { number = 13, title = 'Middle', state = 'OPEN', author = 'cora', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.same(
      { '42', '13', '7' },
      vim.tbl_map(function(entry)
        return entry.value.num
      end, captured.entries)
    )
  end)

  it('adds a load more row when the PR list exceeds the configured limit', function()
    vim.g.forge = {
      display = {
        limits = {
          pulls = 2,
        },
      },
    }
    cache['pr:open'] = {
      { number = 42, title = 'Newer', state = 'OPEN', author = 'bob', created_at = '' },
      { number = 13, title = 'Middle', state = 'OPEN', author = 'cora', created_at = '' },
      { number = 7, title = 'Older', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.same(
      { '42', '13' },
      vim.tbl_map(function(entry)
        return entry.value.num
      end, vim.list_slice(captured.entries, 1, 2))
    )
    assert.equals('Load more...', captured.entries[3].display[1][1])
    assert.is_true(captured.entries[3].load_more)
  end)

  it('fetches more PRs in place when the load more row is activated', function()
    vim.g.forge = {
      display = {
        limits = {
          pulls = 2,
        },
      },
    }
    cache['pr:open'] = {
      { number = 42, title = 'Newer', state = 'OPEN', author = 'bob', created_at = '' },
      { number = 13, title = 'Middle', state = 'OPEN', author = 'cora', created_at = '' },
      { number = 7, title = 'Older', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return {
            code = 0,
            stdout = vim.json.encode({
              { number = 42, title = 'Newer', state = 'OPEN', author = 'bob', created_at = '' },
              { number = 13, title = 'Middle', state = 'OPEN', author = 'cora', created_at = '' },
              { number = 7, title = 'Older', state = 'OPEN', author = 'alice', created_at = '' },
              { number = 3, title = 'Oldest', state = 'OPEN', author = 'drew', created_at = '' },
            }),
          }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    action_by_name('default').fn(captured.entries[3])
    vim.system = old_system

    assert.equals(2, #calls)
    assert.same({ 'prs', 'closed' }, calls[1].cmd)
    assert.same({ 'prs', 'open' }, calls[2].cmd)
  end)

  it('warms the next PR state after opening a cached list', function()
    cache['pr:closed'] = nil

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('Open PRs (1)> ', captured.prompt)
    assert.same({ 'prs', 'closed' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        {
          number = 43,
          title = 'Fix cache warmup',
          state = 'CLOSED',
          author = 'alice',
          created_at = '',
        },
      }),
    })

    vim.wait(100, function()
      return cache['pr:closed'] ~= nil
    end)
    vim.system = old_system

    assert.same(43, cache['pr:closed'][1].number)
  end)

  it('clears all PR state caches on refresh before reloading', function()
    cache['pr:closed'] = {
      { number = 43, title = 'Old closed', state = 'CLOSED', author = 'alice', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 43, title = 'Old closed', state = 'CLOSED', author = 'alice', created_at = '' },
    }

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    action_by_name('refresh').fn()

    vim.system = old_system

    assert.is_nil(cache['pr:open'])
    assert.is_nil(cache['pr:closed'])
    assert.is_nil(cache['pr:all'])
    assert.equals('Open PRs> ', captured.prompt)
    assert.same('function', type(captured.stream))
  end)

  it('keeps issue web actions open', function()
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('default'), 'close'))
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('edit'), 'close'))
    assert.is_nil(rawget(action_by_name('close'), 'close'))
  end)

  it('adds a load more row when the issue list exceeds the configured limit', function()
    vim.g.forge = {
      display = {
        limits = {
          issues = 2,
        },
      },
    }
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 12, title = 'Docs', state = 'OPEN', author = 'bob', created_at = '' },
      { number = 3, title = 'Polish', state = 'OPEN', author = 'cora', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.same(
      { '12', '7' },
      vim.tbl_map(function(entry)
        return entry.value.num
      end, vim.list_slice(captured.entries, 1, 2))
    )
    assert.equals('Load more...', captured.entries[3].display[1][1])
    assert.is_true(captured.entries[3].load_more)
  end)

  it('fetches more issues in place when the load more row is activated', function()
    vim.g.forge = {
      display = {
        limits = {
          issues = 2,
        },
      },
    }
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 12, title = 'Docs', state = 'OPEN', author = 'bob', created_at = '' },
      { number = 3, title = 'Polish', state = 'OPEN', author = 'cora', created_at = '' },
    }

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return {
            code = 0,
            stdout = vim.json.encode({
              { number = 12, title = 'Docs', state = 'OPEN', author = 'bob', created_at = '' },
              { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
              { number = 3, title = 'Polish', state = 'OPEN', author = 'cora', created_at = '' },
              { number = 1, title = 'Older', state = 'OPEN', author = 'drew', created_at = '' },
            }),
          }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())

    action_by_name('default').fn(captured.entries[3])
    vim.system = old_system

    assert.equals(2, #calls)
    assert.same({ 'issues', 'open' }, calls[1].cmd)
    assert.same({ 'issues', 'all' }, calls[2].cmd)
  end)

  it('keeps the issue header affordance on the default open action only', function()
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }
    package.preload['forge'] = function()
      return {
        config = require('forge.config').config,
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          return cache[key]
        end,
        set_list = function(key, value)
          cache[key] = value
        end,
        clear_list = function(key)
          if key then
            cache[key] = nil
          end
        end,
        format_issues = function(issues)
          return vim.tbl_map(function(issue)
            return {
              { '#' .. tostring(issue.number) },
              { ' ' .. (issue.title or '') },
            }
          end, issues)
        end,
        format_issue = function(issue)
          return {
            { '#' .. tostring(issue.number) },
            { ' ' .. (issue.title or '') },
          }
        end,
        create_issue = function() end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('all', {
      labels = { issue = 'Issues' },
      kinds = { issue = 'issue' },
      issue_fields = {
        number = 'number',
        title = 'title',
        state = 'state',
        author = 'author',
        created_at = 'created_at',
      },
      view_web = function() end,
      close_issue_cmd = function(_, num)
        return { 'close', num }
      end,
      reopen_issue_cmd = function(_, num)
        return { 'reopen', num }
      end,
    })

    assert.is_not_nil(captured)
    local labels = {}
    for _, def in ipairs(captured.actions) do
      labels[def.name] = def.label
    end
    assert.equals('open', labels.default)
    assert.equals('web', labels.browse)
    assert.equals('edit', labels.edit)
    assert.equals('toggle', labels.close)
    assert.equals('create', labels.create)
    assert.equals('filter', labels.filter)
    assert.equals('prev', labels.filter_prev)
    assert.equals('refresh', labels.refresh)
  end)

  it('opens the issue picker immediately on fzf before the fetch completes', function()
    cache['issue:all'] = nil

    local old_system = vim.system
    local system_cb
    vim.system = function(_, _, cb)
      system_cb = cb
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.equals('All Issues> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    action_by_name('create').fn()
    assert.equals(1, issue_create_calls)

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.is_not_nil(system_cb)
    system_cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('7', streamed[1].value.num)
    assert.equals('#7', streamed[1].display[1][1])
    assert.same(7, cache['issue:all'][1].number)
  end)

  it('dispatches flattened issue actions directly from the root picker', function()
    cache['issue:open'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('open', fake_issue_forge())

    assert.is_not_nil(captured)
    local entry = captured.entries[1]
    action_by_name('default').fn(entry)
    action_by_name('edit').fn(entry)
    action_by_name('close').fn(entry)

    assert.same({ name = 'issue_browse', issue = { num = '42', scope = nil } }, op_calls[1])
    assert.same({ name = 'issue_edit', issue = { num = '42', scope = nil } }, op_calls[2])
    assert.same({ name = 'issue_close', issue = { num = '42', scope = nil } }, {
      name = op_calls[3].name,
      issue = op_calls[3].issue,
    })
    assert.is_function(op_calls[3].opts.on_success)
    assert.is_function(op_calls[3].opts.on_failure)
  end)

  it('warms the next issue state after opening a cached list', function()
    cache['issue:open'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }
    cache['issue:closed'] = nil

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('open', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.equals('Open Issues (1)> ', captured.prompt)
    assert.same({ 'issues', 'closed' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 8, title = 'Fixed bug', state = 'CLOSED', author = 'alice', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return cache['issue:closed'] ~= nil
    end)
    vim.system = old_system

    assert.same(8, cache['issue:closed'][1].number)
  end)

  it('keeps check and CI web actions open', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      { name = 'lint', link = 'https://example.com/check', bucket = 'pass' },
    })

    assert.is_not_nil(captured)
    assert.equals('PR #42 Checks (1)> ', captured.prompt)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))

    local old_system = vim.system
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'CI',
            branch = 'main',
            status = 'success',
            url = 'https://example.com',
          },
        }),
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    pickers.ci(fake_ci_forge(), 'main', 'all')
    vim.wait(100, function()
      return captured and captured.prompt == 'CI for main (1)> '
    end)
    vim.system = old_system

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))
    assert.is_nil(rawget(action_by_name('watch'), 'close'))
  end)

  it('routes CI log and watch actions through forge.ops', function()
    local old_system = vim.system
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'CI',
            branch = 'main',
            status = 'success',
            url = 'https://example.com',
          },
        }),
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')
    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)
    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    action_by_name('log').fn(streamed[1])
    action_by_name('watch').fn(streamed[1])

    assert.same({
      name = 'ci_log',
      run = {
        id = '1',
        name = 'CI',
        branch = 'main',
        status = 'success',
        url = 'https://example.com',
        scope = nil,
      },
    }, op_calls[1])
    assert.same({
      name = 'ci_watch',
      run = {
        id = '1',
        name = 'CI',
        branch = 'main',
        status = 'success',
        url = 'https://example.com',
        scope = nil,
      },
    }, op_calls[2])
  end)

  it('shows an info notification when skipped checks have no logs', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      {
        name = 'lint',
        link = 'https://example.com/actions/runs/123/job/456',
        bucket = 'skipping',
        run_id = '123',
        job_id = '456',
      },
    })

    assert.is_not_nil(captured)
    action_by_name('log').fn(captured.entries[1])

    assert.same({ 'no log available - job was not started' }, logger_messages.info)
  end)

  it('builds checks entries with live display renderers', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      {
        name = 'lint',
        bucket = 'pass',
        link = 'https://example.com/check',
      },
    })

    assert.is_not_nil(captured)
    assert.is_function(captured.entries[1].render_display)
    assert.same({ { 'lint' } }, captured.entries[1].render_display(120))
  end)

  it('uses subject-first prompts for filtered checks', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'fail', {
      { name = 'lint', link = 'https://example.com/check', bucket = 'fail' },
    })

    assert.is_not_nil(captured)
    assert.equals('PR #42 Failed Checks (1)> ', captured.prompt)
  end)

  it('uses scope-first prompts for filtered CI runs while loading', function()
    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'fail')

    assert.is_not_nil(captured)
    assert.equals('Failed CI for main> ', captured.prompt)
  end)

  it('opens the checks picker immediately on fzf before the fetch completes', function()
    local old_system = vim.system
    local system_cb
    vim.system = function(_, _, cb)
      system_cb = cb
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all')

    assert.is_not_nil(captured)
    assert.equals('PR #42 Checks> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.is_not_nil(system_cb)
    system_cb({
      code = 0,
      stdout = vim.json.encode({
        {
          name = 'lint',
          bucket = 'pass',
          link = 'https://example.com/check',
          run_id = '123',
        },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('lint', streamed[1].value.name)
    assert.equals('lint', streamed[1].display[1][1])
  end)

  it('ignores stale check responses after a refresh starts a newer fetch', function()
    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all')

    local first = captured
    local first_streamed = {}
    first.stream(function(entry)
      if entry == nil then
        first_streamed.done = true
        return
      end
      first_streamed[#first_streamed + 1] = entry
    end)

    action_by_name('refresh').fn()

    local second = captured
    local second_streamed = {}
    second.stream(function(entry)
      if entry == nil then
        second_streamed.done = true
        return
      end
      second_streamed[#second_streamed + 1] = entry
    end)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { name = 'old', bucket = 'pass', link = 'https://example.com/old', run_id = '1' },
      }),
    })
    calls[2].cb({
      code = 0,
      stdout = vim.json.encode({
        { name = 'new', bucket = 'fail', link = 'https://example.com/new', run_id = '2' },
      }),
    })

    vim.wait(100, function()
      return first_streamed.done == true and second_streamed.done == true
    end)
    vim.system = old_system

    assert.is_nil(first_streamed[1])
    assert.equals('new', second_streamed[1].value.name)
  end)

  it('opens the CI picker immediately on fzf before the fetch completes', function()
    local old_system = vim.system
    local system_cb
    vim.system = function(_, _, cb)
      system_cb = cb
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    assert.is_not_nil(captured)
    assert.equals('CI for main> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))
    assert.is_nil(rawget(action_by_name('watch'), 'close'))

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.is_not_nil(system_cb)
    system_cb({
      code = 0,
      stdout = vim.json.encode({
        {
          id = '1',
          name = 'CI',
          branch = 'main',
          status = 'success',
          url = 'https://example.com',
        },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('1', streamed[1].value.id)
    assert.equals('CI', streamed[1].display[1][1])
  end)

  it('adds a load more row when the CI run list exceeds the configured limit', function()
    vim.g.forge = {
      display = {
        limits = {
          runs = 2,
        },
      },
    }

    local old_system = vim.system
    vim.system = function(_, _, cb)
      if cb then
        cb({
          code = 0,
          stdout = vim.json.encode({
            { id = '1', name = 'Build', branch = 'main', status = 'success', url = 'https://e/1' },
            { id = '2', name = 'Lint', branch = 'main', status = 'failure', url = 'https://e/2' },
            { id = '3', name = 'Docs', branch = 'main', status = 'success', url = 'https://e/3' },
          }),
        })
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('1', streamed[1].value.id)
    assert.equals('2', streamed[2].value.id)
    assert.equals('Load more...', streamed[3].display[1][1])
    assert.is_true(streamed[3].load_more)
  end)

  it('keeps repo CI all ordered chronologically instead of regrouping by status', function()
    vim.g.forge = {
      display = {
        limits = {
          runs = 3,
        },
      },
    }

    local old_system = vim.system
    vim.system = function(_, _, cb)
      if cb then
        cb({
          code = 0,
          stdout = vim.json.encode({
            {
              id = '1',
              name = 'Newest pass',
              branch = 'main',
              status = 'success',
              url = 'https://e/1',
              created_at = '2024-01-03T00:00:00Z',
            },
            {
              id = '2',
              name = 'Middle fail',
              branch = 'main',
              status = 'failure',
              url = 'https://e/2',
              created_at = '2024-01-02T00:00:00Z',
            },
            {
              id = '3',
              name = 'Oldest running',
              branch = 'main',
              status = 'running',
              url = 'https://e/3',
              created_at = '2024-01-01T00:00:00Z',
            },
          }),
        })
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('1', streamed[1].value.id)
    assert.equals('2', streamed[2].value.id)
    assert.equals('3', streamed[3].value.id)
  end)

  it('requests more CI runs when the load more row is activated', function()
    vim.g.forge = {
      display = {
        limits = {
          runs = 2,
        },
      },
    }

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    assert.is_not_nil(captured)
    assert.equals('CI for main> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.same({ 'runs', 'main', '3' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { id = '1', name = 'Build', branch = 'main', status = 'success', url = 'https://e/1' },
        { id = '2', name = 'Lint', branch = 'main', status = 'failure', url = 'https://e/2' },
        { id = '3', name = 'Docs', branch = 'main', status = 'success', url = 'https://e/3' },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)

    action_by_name('log').fn(streamed[3])

    vim.system = old_system

    assert.same({ 'runs', 'main', '5' }, calls[2].cmd)
  end)

  it('ignores stale CI responses after switching filters during fetch', function()
    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    local first = captured
    local first_streamed = {}
    first.stream(function(entry)
      if entry == nil then
        first_streamed.done = true
        return
      end
      first_streamed[#first_streamed + 1] = entry
    end)

    action_by_name('failed').fn()

    local second = captured
    local second_streamed = {}
    second.stream(function(entry)
      if entry == nil then
        second_streamed.done = true
        return
      end
      second_streamed[#second_streamed + 1] = entry
    end)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        {
          id = '1',
          name = 'Old',
          branch = 'main',
          status = 'success',
          url = 'https://example.com/old',
        },
      }),
    })
    calls[2].cb({
      code = 0,
      stdout = vim.json.encode({
        {
          id = '2',
          name = 'New',
          branch = 'main',
          status = 'fail',
          url = 'https://example.com/new',
        },
      }),
    })

    vim.wait(100, function()
      return first_streamed.done == true and second_streamed.done == true
    end)
    vim.system = old_system

    assert.is_nil(first_streamed[1])
    assert.equals('2', second_streamed[1].value.id)
  end)

  it('keeps release browse and copy actions open', function()
    cache['release:list'] = {
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
    }

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_false(rawget(action_by_name('yank'), 'close'))
    assert.is_nil(rawget(action_by_name('delete'), 'close'))
  end)

  it('keeps release copy working when the clipboard register is unavailable', function()
    local old_setreg = vim.fn.setreg
    vim.fn.setreg = function()
      error('clipboard unavailable')
    end

    cache['release:list'] = {
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
    }

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())
    action_by_name('yank').fn(captured.entries[1])

    vim.fn.setreg = old_setreg

    assert.same({ 'copied release URL' }, logger_messages.info)
  end)

  it('opens the release picker immediately on fzf before the fetch completes', function()
    cache['release:list'] = nil

    local old_system = vim.system
    local system_cb
    vim.system = function(_, _, cb)
      system_cb = cb
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())

    assert.is_not_nil(captured)
    assert.equals('Releases> ', captured.prompt)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    assert.is_not_nil(system_cb)
    system_cb({
      code = 0,
      stdout = vim.json.encode({
        { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
      }),
    })

    vim.wait(100, function()
      return streamed.done == true
    end)
    vim.system = old_system

    assert.equals('v1.0.0', streamed[1].value.tag)
    assert.equals('v1.0.0', streamed[1].display[1][1])
    assert.same('v1.0.0', cache['release:list'][1].tag)
  end)

  it('reuses one fetched release list across release filters', function()
    cache['release:list'] = {
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
      { tag = 'v1.1.0-rc1', title = 'RC', is_draft = false, is_prerelease = true },
      { tag = 'v2.0.0-draft', title = 'Draft', is_draft = true, is_prerelease = false },
    }

    local old_system = vim.system
    local calls = {}
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())

    action_by_name('filter').fn()
    assert.equals('Draft Releases (1)> ', captured.prompt)
    assert.equals('v2.0.0-draft', captured.entries[1].value.tag)

    action_by_name('filter').fn()
    assert.equals('Pre-releases (1)> ', captured.prompt)
    assert.equals('v1.1.0-rc1', captured.entries[1].value.tag)

    action_by_name('filter_prev').fn()
    assert.equals('Draft Releases (1)> ', captured.prompt)
    assert.equals('v2.0.0-draft', captured.entries[1].value.tag)

    action_by_name('filter_prev').fn()
    assert.equals('Releases (3)> ', captured.prompt)
    assert.equals('v1.0.0', captured.entries[1].value.tag)

    vim.system = old_system
    assert.same({}, calls)
  end)
end)
