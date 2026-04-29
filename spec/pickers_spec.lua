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
local picker_pick_calls
local picker_refresh_calls
---@type table<string, forge.PRState>
local pr_state_cache
local preload_modules = {
  'fzf-lua.utils',
  'forge',
  'forge.format',
  'forge.issue',
  'forge.logger',
  'forge.ops',
  'forge.picker',
  'forge.picker.checks',
  'forge.picker.ci',
  'forge.picker.entity',
  'forge.picker.issue',
  'forge.picker.pr',
  'forge.picker.release',
  'forge.pr',
  'forge.picker.shared',
  'forge.repo',
  'forge.routes',
  'forge.surface_policy',
  'forge.state',
}
local loaded_modules = {
  'forge.availability',
  'forge',
  'forge.config',
  'forge.format',
  'forge.issue',
  'forge.logger',
  'forge.ops',
  'forge.picker',
  'forge.picker.checks',
  'forge.picker.ci',
  'forge.picker.entity',
  'forge.picker.issue',
  'forge.picker.pr',
  'forge.picker.release',
  'forge.pr',
  'forge.picker.shared',
  'forge.picker.session',
  'forge.pickers',
  'forge.repo',
  'forge.review',
  'forge.routes',
  'forge.state',
  'forge.surface_policy',
}

local function fake_forge(opts)
  opts = opts or {}
  return {
    name = opts.name or 'github',
    labels = vim.tbl_extend('force', { pr = 'PRs', pr_one = 'PR' }, opts.labels or {}),
    kinds = { pr = 'pull_request' },
    capabilities = opts.capabilities or { draft = true },
    pr_fields = {
      number = 'number',
      title = 'title',
      state = 'state',
      author = 'author',
      created_at = 'created_at',
    },
    repo_info = function(_, scope)
      if type(opts.repo_info) == 'function' then
        return opts.repo_info(scope)
      end
      return opts.repo_info
        or {
          permission = 'WRITE',
          merge_methods = { 'merge' },
        }
    end,
    pr_state = function(_, num, scope)
      if type(opts.pr_state) == 'function' then
        return opts.pr_state(num, scope)
      end
      if type(opts.pr_states) == 'table' and opts.pr_states[num] then
        return opts.pr_states[num]
      end
      return {
        state = 'OPEN',
        mergeable = 'UNKNOWN',
        review_decision = '',
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

local function fake_ci_forge(opts)
  opts = opts or {}
  return {
    name = opts.name or 'github',
    labels = vim.tbl_extend('force', { ci = 'CI', pr_one = 'PR' }, opts.labels or {}),
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
    list_releases_json_cmd = function(_, _, limit)
      return { 'releases', tostring(limit or '') }
    end,
  }
end

---@param scope forge.Scope?
---@return string
local function pr_state_scope_key(scope)
  if type(scope) ~= 'table' then
    return '|||'
  end
  return table.concat({
    scope.kind or '',
    scope.host or '',
    scope.slug or '',
  }, '|') .. '|'
end

---@param scope forge.Scope?
---@param num string|integer?
---@return string
local function pr_state_key(scope, num)
  return pr_state_scope_key(scope) .. tostring(num or '')
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
    picker_pick_calls = 0
    picker_refresh_calls = 0
    pr_state_cache = {}
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
    package.preload['forge.state'] = function()
      return {
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
        repo_info = function(f)
          return f:repo_info()
        end,
        pr_state = function(f, num, scope)
          local key = pr_state_key(scope, num)
          local cached = pr_state_cache[key]
          if cached ~= nil then
            return cached
          end
          local state = f:pr_state(num, scope)
          pr_state_cache[key] = state
          return state
        end,
        set_pr_state = function(num, state, scope)
          pr_state_cache[pr_state_key(scope, num)] = state
          return state
        end,
        clear_pr_state = function(num, scope)
          if num ~= nil then
            pr_state_cache[pr_state_key(scope, num)] = nil
            return
          end
          if scope ~= nil then
            local prefix = pr_state_scope_key(scope)
            for key in pairs(pr_state_cache) do
              if key:sub(1, #prefix) == prefix then
                pr_state_cache[key] = nil
              end
            end
            return
          end
          pr_state_cache = {}
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
          picker_pick_calls = picker_pick_calls + 1
          captured = opts
          if type(opts.stream) == 'function' then
            local inner = opts.stream
            opts.entries = {}
            opts.stream = function(cb)
              opts.entries = {}
              inner(function(entry)
                if entry ~= nil then
                  opts.entries[#opts.entries + 1] = entry
                end
                if cb then
                  cb(entry)
                end
              end)
            end
          end
          return {
            refresh = function()
              picker_refresh_calls = picker_refresh_calls + 1
              if type(captured.stream) == 'function' then
                captured.stream(function() end)
              end
              return true
            end,
          }
        end,
      }
    end
    package.preload['forge.surface_policy'] = function()
      local function available(def, entry)
        local fn = rawget(def, 'available')
        if type(fn) == 'function' then
          return fn(entry) ~= false
        end
        if fn ~= nil then
          return fn ~= false
        end
        return true
      end
      return {
        row_kind = function(entry)
          if entry == nil then
            return 'none'
          end
          if entry.load_more then
            return 'load_more'
          end
          if entry.placeholder then
            return entry.placeholder_kind == 'error' and 'error' or 'empty'
          end
          return 'entity'
        end,
        available = available,
        resolve_label = function(def, entry)
          if not available(def, entry) then
            return nil
          end
          local label = rawget(def, 'label')
          if type(label) == 'function' then
            return label(entry)
          end
          return label
        end,
        pr_toggle_verb = function(entry)
          if not entry or type(entry.value) ~= 'table' then
            return nil
          end
          local state = (entry.value.state or ''):lower()
          if state == 'open' or state == 'opened' then
            return 'close'
          end
          if state == 'closed' then
            return 'reopen'
          end
          return nil
        end,
        issue_toggle_verb = function(entry)
          if not entry or type(entry.value) ~= 'table' then
            return nil
          end
          local state = (entry.value.state or ''):lower()
          if state == 'open' or state == 'opened' then
            return 'close'
          end
          if state == 'closed' then
            return 'reopen'
          end
          return nil
        end,
        ci_toggle_verb = function(entry)
          if not entry or type(entry.value) ~= 'table' then
            return nil
          end
          local status = (entry.value.status or ''):lower()
          if
            status == 'in_progress'
            or status == 'queued'
            or status == 'pending'
            or status == 'running'
          then
            return 'cancel'
          end
          if status == 'skipped' then
            return nil
          end
          return 'rerun'
        end,
      }
    end
    package.preload['forge.ops'] = function()
      return {
        pr_review = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_review', pr = pr, opts = opts or {} })
        end,
        pr_ci = function(_, pr, opts)
          table.insert(op_calls, { name = 'pr_ci', pr = pr, opts = opts })
        end,
        pr_edit = function(pr)
          table.insert(op_calls, { name = 'pr_edit', pr = pr })
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
        ci_open = function(_, run)
          table.insert(op_calls, { name = 'ci_open', run = run })
        end,
        ci_watch = function(_, run)
          table.insert(op_calls, { name = 'ci_watch', run = run })
        end,
        ci_browse = function(_, run)
          table.insert(op_calls, { name = 'ci_browse', run = run })
        end,
        ci_toggle = function(_, run, opts)
          table.insert(op_calls, { name = 'ci_toggle', run = run, opts = opts })
          if opts and opts.on_success then
            opts.on_success()
          end
        end,
        issue_browse = function(_, issue)
          table.insert(op_calls, { name = 'issue_browse', issue = issue })
        end,
        issue_edit = function(issue)
          table.insert(op_calls, { name = 'issue_edit', issue = issue })
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
    package.preload['forge.format'] = function()
      return {
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
          local rows = {}
          for _, rel in ipairs(releases) do
            rows[#rows + 1] = {
              { tostring(rel.tag or '') },
              { ' ' .. (rel.title or '') },
            }
          end
          return rows
        end,
        format_release = function(rel)
          return {
            { tostring(rel.tag or '') },
            { ' ' .. (rel.title or '') },
          }
        end,
      }
    end
    package.preload['forge.repo'] = function()
      return {
        current_scope = function()
          return nil
        end,
        scope_key = function(scope)
          if type(scope) ~= 'table' then
            return ''
          end
          return table.concat({
            scope.kind or '',
            scope.host or '',
            scope.slug or '',
          }, '|')
        end,
        remote_web_url = function()
          return 'https://example.com/repo'
        end,
      }
    end
    package.preload['forge.issue'] = function()
      return {
        create_issue = function(...)
          issue_create_calls = issue_create_calls + 1
          issue_create_opts = select(1, ...)
        end,
      }
    end
    package.preload['forge.pr'] = function()
      return {
        create_pr = function(...)
          pr_create_calls = pr_create_calls + 1
          pr_create_opts = select(1, ...)
        end,
      }
    end
    package.preload['forge.routes'] = function()
      return {
        open = function() end,
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
        format_prs = require('forge.format').format_prs,
        format_pr = require('forge.format').format_pr,
        format_issues = require('forge.format').format_issues,
        format_issue = require('forge.format').format_issue,
        format_checks = require('forge.format').format_checks,
        format_check = require('forge.format').format_check,
        filter_checks = require('forge.format').filter_checks,
        format_runs = require('forge.format').format_runs,
        format_run = require('forge.format').format_run,
        filter_runs = require('forge.format').filter_runs,
        format_releases = require('forge.format').format_releases,
        format_release = require('forge.format').format_release,
        remote_web_url = require('forge.repo').remote_web_url,
        repo_info = require('forge.state').repo_info,
        pr_state = require('forge.state').pr_state,
        set_pr_state = require('forge.state').set_pr_state,
        clear_pr_state = require('forge.state').clear_pr_state,
        create_issue = require('forge.issue').create_issue,
        create_pr = require('forge.pr').create_pr,
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
    vim.g.forge = nil
  end)

  it('uses row-aware labels for the highlighted open PR', function()
    local cfg = require('forge.config').config()
    assert.equals('<c-e>', cfg.keys.pr.edit)
    assert.equals('<c-y>', cfg.keys.pr.approve)
    assert.equals('<c-g>', cfg.keys.pr.merge)
    assert.equals('<c-a>', cfg.keys.pr.create)
    assert.equals('<c-s>', cfg.keys.pr.toggle)
    assert.equals('<c-d>', cfg.keys.pr.draft)
    assert.equals('<tab>', cfg.keys.ci.filter)

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('Open PRs (1)> ', captured.prompt)
    assert.same({
      'default',
      'ci',
      'edit',
      'approve',
      'merge',
      'toggle',
      'draft',
      'create',
      'filter',
      'refresh',
    }, captured.header_order)
    captured.stream(function() end)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('checkout', labels.default)
    assert.equals('edit', labels.edit)
    assert.equals('approve', labels.approve)
    assert.equals('merge', labels.merge)
    assert.equals('create', labels.create)
    assert.equals('close', labels.toggle)
    assert.equals('draft', labels.draft)
    assert.equals('filter', labels.filter)
    assert.equals('refresh', labels.refresh)
  end)

  it('uses configured integration labels for the highlighted open PR', function()
    vim.g.forge = {
      review = {
        adapter = 'diffview',
      },
    }

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    captured.stream(function() end)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('diffview', labels.default)
  end)

  it('uses functional registered review adapter labels for the highlighted open PR', function()
    vim.g.forge = {
      review = {
        adapter = 'custom-test-review',
      },
    }

    require('forge.review').register('custom-test-review', {
      label = function(ctx)
        return 'review #' .. ctx.pr.num
      end,
      open = function() end,
    })

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    captured.stream(function() end)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('review #42', labels.default)
  end)

  it('hides open-only PR actions on closed and merged rows', function()
    cache['pr:all'] = {
      { number = 42, title = 'Closed', state = 'CLOSED', author = 'alice', created_at = '' },
      { number = 41, title = 'Merged', state = 'MERGED', author = 'bob', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr('all', fake_forge())
    captured.stream(function() end)

    assert.is_not_nil(captured)

    local closed_labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.is_nil(closed_labels.approve)
    assert.is_nil(closed_labels.merge)
    assert.equals('reopen', closed_labels.toggle)
    assert.is_nil(closed_labels.draft)

    local merged_labels = helpers.action_labels(captured.actions, captured.entries[2])
    assert.is_nil(merged_labels.approve)
    assert.is_nil(merged_labels.merge)
    assert.is_nil(merged_labels.toggle)
    assert.is_nil(merged_labels.draft)
  end)

  it('uses cached PR details to tighten approve, merge, and draft labels', function()
    cache['pr:open'] = {
      {
        number = 42,
        title = 'Already approved',
        state = 'OPEN',
        author = 'alice',
        created_at = '',
      },
      { number = 41, title = 'Draft PR', state = 'OPEN', author = 'bob', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr(
      'open',
      fake_forge({
        pr_states = {
          ['42'] = {
            state = 'OPEN',
            mergeable = 'UNKNOWN',
            review_decision = 'APPROVED',
            is_draft = false,
          },
          ['41'] = {
            state = 'OPEN',
            mergeable = 'UNKNOWN',
            review_decision = '',
            is_draft = true,
          },
        },
      })
    )
    captured.stream(function() end)

    local approved_labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.is_nil(approved_labels.approve)
    assert.equals('merge', approved_labels.merge)
    assert.equals('draft', approved_labels.draft)

    local draft_labels = helpers.action_labels(captured.actions, captured.entries[2])
    assert.equals('approve', draft_labels.approve)
    assert.is_nil(draft_labels.merge)
    assert.equals('ready', draft_labels.draft)
  end)

  it('hides merge when repo permissions do not allow it', function()
    cache['pr:open'] = {
      { number = 40, title = 'Read-only repo', state = 'OPEN', author = 'carol', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr(
      'open',
      fake_forge({
        repo_info = function()
          return { permission = 'READ', merge_methods = { 'merge' } }
        end,
      })
    )
    captured.stream(function() end)

    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('approve', labels.approve)
    assert.is_nil(labels.merge)
    assert.equals('draft', labels.draft)
  end)

  it('keeps auxiliary PR actions open', function()
    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
    captured.stream(function() end)

    assert.is_not_nil(captured)
    assert.equals('checkout', helpers.action_labels(captured.actions, captured.entries[1]).default)
    for _, case in ipairs({
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
    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
    captured.stream(function() end)
    vim.wait(100, function()
      return captured.entries[1] ~= nil
    end)

    assert.is_not_nil(captured)
    local entry = captured.entries[1]
    action_by_name('default').fn(entry)
    action_by_name('edit').fn(entry)
    action_by_name('approve').fn(entry)
    action_by_name('merge').fn(entry)
    action_by_name('toggle').fn(entry)
    action_by_name('draft').fn(entry)

    assert.same({
      {
        name = 'pr_review',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        opts = {},
      },
      { name = 'pr_edit', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      { name = 'pr_approve', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      {
        name = 'pr_merge',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        method = nil,
      },
      { name = 'pr_close', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      {
        name = 'pr_toggle_draft',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        is_draft = false,
      },
    }, op_calls)

    vim.system = old_system
  end)

  it('shows an explicit empty PR row instead of a blank picker', function()
    cache['pr:open'] = {}

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
    captured.stream(function() end)

    assert.is_not_nil(captured)
    assert.equals('Open PRs (0)> ', captured.prompt)
    assert.equals('No open PRs', captured.entries[1].display[1][1])
    assert.is_true(captured.entries[1].placeholder)
    assert.equals('empty', captured.entries[1].placeholder_kind)
  end)

  it('shows only global header actions on empty PR rows', function()
    cache['pr:open'] = {}

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
    captured.stream(function() end)

    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.is_nil(labels.default)
    assert.is_nil(labels.ci)
    assert.is_nil(labels.edit)
    assert.is_nil(labels.approve)
    assert.is_nil(labels.merge)
    assert.is_nil(labels.toggle)
    assert.is_nil(labels.draft)
    assert.equals('create', labels.create)
    assert.equals('filter', labels.filter)
    assert.equals('refresh', labels.refresh)
  end)

  it('shows only global header actions on PR error rows', function()
    cache['pr:open'] = nil

    local old_system = vim.system
    local old_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
    vim.system = function(_, _, cb)
      if cb then
        cb({ code = 1, stdout = '', stderr = 'boom' })
      end
      return {
        wait = function()
          return { code = 1, stdout = '', stderr = 'boom' }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
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
    vim.schedule = old_schedule

    assert.equals('error', streamed[1].placeholder_kind)
    assert.equals('boom', streamed[1].display[1][1])
    assert.same({ 'boom' }, logger_messages.error)
    local labels = helpers.action_labels(captured.actions, streamed[1])
    assert.is_nil(labels.default)
    assert.is_nil(labels.ci)
    assert.is_nil(labels.edit)
    assert.is_nil(labels.approve)
    assert.is_nil(labels.merge)
    assert.is_nil(labels.toggle)
    assert.is_nil(labels.draft)
    assert.equals('create', labels.create)
    assert.is_nil(labels.filter)
    assert.equals('refresh', labels.refresh)
  end)

  it('shows PR decode failures in the picker instead of a generic fetch error', function()
    cache['pr:open'] = nil

    local old_system = vim.system
    local old_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
    vim.system = function(_, _, cb)
      if cb then
        cb({ code = 0, stdout = '{', stderr = '' })
      end
      return {
        wait = function()
          return { code = 0, stdout = '{', stderr = '' }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())
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
    vim.schedule = old_schedule

    assert.equals('error', streamed[1].placeholder_kind)
    assert.equals(logger_messages.error[1], streamed[1].display[1][1])
    assert.not_equals('failed to fetch PRs', logger_messages.error[1])
  end)

  it('opens the PR picker immediately on fzf before the fetch completes', function()
    cache['pr:open'] = nil

    local old_system = vim.system
    local old_schedule = vim.schedule
    local system_cb
    vim.schedule = function(fn)
      fn()
    end
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
    vim.schedule = old_schedule

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
    assert.same({
      'default',
      'ci',
      'edit',
      'approve',
      'merge',
      'toggle',
      'draft',
      'create',
      'filter',
      'refresh',
    }, captured.header_order)
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

    local streamed = {}
    captured.stream(function(entry)
      if entry == nil then
        streamed.done = true
        return
      end
      streamed[#streamed + 1] = entry
    end)

    action_by_name('refresh').fn()

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
      return streamed.done == true and captured.entries[1] ~= nil
    end)
    vim.system = old_system

    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
    assert.equals('42', captured.entries[1].value.num)
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
    captured.stream(function() end)

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
    captured.stream(function() end)

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

  it('shows only active header actions on PR load more rows', function()
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
    captured.stream(function() end)

    local labels = helpers.action_labels(captured.actions, captured.entries[3])
    assert.equals('load more', labels.default)
    assert.is_nil(labels.ci)
    assert.is_nil(labels.edit)
    assert.is_nil(labels.approve)
    assert.is_nil(labels.merge)
    assert.is_nil(labels.toggle)
    assert.is_nil(labels.draft)
    assert.equals('create', labels.create)
    assert.equals('filter', labels.filter)
    assert.equals('refresh', labels.refresh)
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
    captured.stream(function() end)

    local load_more = captured.entries[3]
    action_by_name('default').fn(load_more)
    captured.stream(function() end)
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
    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
  end)

  it(
    'patches shared PR state locally and revalidates the live PR picker after approve succeeds',
    function()
      cache['pr:open'] = {
        {
          number = 42,
          title = 'Draft approval',
          state = 'OPEN',
          author = 'alice',
          created_at = '',
        },
      }
      cache['pr:closed'] = {}

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
      pickers.pr(
        'open',
        fake_forge({
          pr_states = {
            ['42'] = {
              state = 'OPEN',
              mergeable = 'UNKNOWN',
              review_decision = '',
              is_draft = true,
            },
          },
        })
      )
      captured.stream(function() end)

      local labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.equals('approve', labels.approve)
      assert.is_nil(labels.merge)
      assert.equals('ready', labels.draft)

      action_by_name('approve').fn(captured.entries[1])

      labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.is_nil(labels.approve)
      assert.is_nil(labels.merge)
      assert.equals('ready', labels.draft)
      assert.same({
        { name = 'pr_approve', pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil } },
      }, op_calls)
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'prs', 'open' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          {
            number = 42,
            title = 'Authoritative',
            state = 'OPEN',
            author = 'alice',
            created_at = '',
          },
        }),
      })

      vim.wait(100, function()
        return cache['pr:open'][1].title == 'Authoritative'
      end)
      vim.system = old_system

      assert.equals('Authoritative', cache['pr:open'][1].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it(
    'patches shared PR state locally and revalidates the live PR picker after marking draft',
    function()
      cache['pr:open'] = {
        {
          number = 42,
          title = 'Ready PR',
          state = 'OPEN',
          author = 'alice',
          created_at = '',
        },
      }
      cache['pr:closed'] = {}

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
      pickers.pr(
        'open',
        fake_forge({
          pr_states = {
            ['42'] = {
              state = 'OPEN',
              mergeable = 'UNKNOWN',
              review_decision = '',
              is_draft = false,
            },
          },
        })
      )
      captured.stream(function() end)

      local labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.equals('approve', labels.approve)
      assert.equals('merge', labels.merge)
      assert.equals('draft', labels.draft)

      action_by_name('draft').fn(captured.entries[1])

      labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.equals('approve', labels.approve)
      assert.is_nil(labels.merge)
      assert.equals('ready', labels.draft)
      assert.same({
        {
          name = 'pr_toggle_draft',
          pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
          is_draft = false,
        },
      }, op_calls)
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'prs', 'open' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          {
            number = 42,
            title = 'Authoritative draft',
            state = 'OPEN',
            author = 'alice',
            created_at = '',
          },
        }),
      })

      vim.wait(100, function()
        return cache['pr:open'][1].title == 'Authoritative draft'
      end)
      vim.system = old_system

      assert.equals('Authoritative draft', cache['pr:open'][1].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it(
    'patches shared PR state locally and revalidates the live PR picker after marking ready',
    function()
      cache['pr:open'] = {
        {
          number = 42,
          title = 'Draft PR',
          state = 'OPEN',
          author = 'alice',
          created_at = '',
        },
      }
      cache['pr:closed'] = {}

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
      pickers.pr(
        'open',
        fake_forge({
          pr_states = {
            ['42'] = {
              state = 'OPEN',
              mergeable = 'UNKNOWN',
              review_decision = '',
              is_draft = true,
            },
          },
        })
      )
      captured.stream(function() end)

      local labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.equals('approve', labels.approve)
      assert.is_nil(labels.merge)
      assert.equals('ready', labels.draft)

      action_by_name('draft').fn(captured.entries[1])

      labels = helpers.action_labels(captured.actions, captured.entries[1])
      assert.equals('approve', labels.approve)
      assert.equals('merge', labels.merge)
      assert.equals('draft', labels.draft)
      assert.same({
        {
          name = 'pr_toggle_draft',
          pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
          is_draft = true,
        },
      }, op_calls)
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'prs', 'open' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          {
            number = 42,
            title = 'Authoritative ready',
            state = 'OPEN',
            author = 'alice',
            created_at = '',
          },
        }),
      })

      vim.wait(100, function()
        return cache['pr:open'][1].title == 'Authoritative ready'
      end)
      vim.system = old_system

      assert.equals('Authoritative ready', cache['pr:open'][1].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it('patches the open PR list locally and revalidates after merge succeeds', function()
    cache['pr:open'] = {
      { number = 42, title = 'Merge me', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Keep me', state = 'OPEN', author = 'cora', created_at = '' },
    }
    cache['pr:closed'] = {
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Merge me', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Keep me', state = 'OPEN', author = 'cora', created_at = '' },
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
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
    captured.stream(function() end)

    action_by_name('merge').fn(captured.entries[1])

    assert.same(
      { 41 },
      vim.tbl_map(function(pr)
        return pr.number
      end, cache['pr:open'])
    )
    assert.is_nil(cache['pr:closed'])
    assert.is_nil(cache['pr:all'])
    assert.equals('41', captured.entries[1].value.num)
    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
    assert.same({
      {
        name = 'pr_merge',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        method = nil,
      },
    }, op_calls)
    assert.same({ 'prs', 'open' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 41, title = 'Authoritative', state = 'OPEN', author = 'cora', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return cache['pr:open'][1].title == 'Authoritative'
    end)
    vim.system = old_system

    assert.equals('Authoritative', cache['pr:open'][1].title)
    assert.equals(2, picker_refresh_calls)
  end)

  it('updates all-PR rows in place and revalidates after merge succeeds', function()
    cache['pr:open'] = {
      { number = 42, title = 'Merge me', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Keep me', state = 'OPEN', author = 'cora', created_at = '' },
    }
    cache['pr:closed'] = {
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Merge me', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Already merged', state = 'MERGED', author = 'drew', created_at = '' },
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
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
    pickers.pr('all', fake_forge())
    captured.stream(function() end)

    action_by_name('merge').fn(captured.entries[1])

    assert.equals(
      'MERGED',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:all'])[1].state
    )
    assert.is_nil(cache['pr:open'])
    assert.is_nil(cache['pr:closed'])
    assert.equals('42', captured.entries[1].value.num)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.is_nil(labels.approve)
    assert.is_nil(labels.merge)
    assert.is_nil(labels.toggle)
    assert.is_nil(labels.draft)
    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
    assert.same({
      {
        name = 'pr_merge',
        pr = { num = '42', scope = nil, state = 'OPEN', is_draft = nil },
        method = nil,
      },
    }, op_calls)
    assert.same({ 'prs', 'all' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        {
          number = 42,
          title = 'Authoritative merge',
          state = 'MERGED',
          author = 'alice',
          created_at = '',
        },
        {
          number = 41,
          title = 'Already merged',
          state = 'MERGED',
          author = 'drew',
          created_at = '',
        },
        { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return cache['pr:all'][1].title == 'Authoritative merge'
    end)
    vim.system = old_system

    assert.equals('Authoritative merge', cache['pr:all'][1].title)
    assert.equals(2, picker_refresh_calls)
  end)

  it('patches PR caches locally and revalidates the live PR picker after close succeeds', function()
    cache['pr:open'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
    }
    cache['pr:closed'] = {
      { number = 43, title = 'Old closed', state = 'CLOSED', author = 'alice', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 43, title = 'Old closed', state = 'CLOSED', author = 'alice', created_at = '' },
      { number = 41, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
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
    captured.stream(function() end)

    action_by_name('toggle').fn(captured.entries[1])

    local closed_numbers = vim.tbl_map(function(pr)
      return pr.number
    end, cache['pr:closed'])
    table.sort(closed_numbers)

    assert.same(
      { 41 },
      vim.tbl_map(function(pr)
        return pr.number
      end, cache['pr:open'])
    )
    assert.same({ 42, 43 }, closed_numbers)
    assert.equals(
      'CLOSED',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:all'])[1].state
    )
    assert.equals('41', captured.entries[1].value.num)
    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
    assert.same({ 'prs', 'open' }, calls[1].cmd)

    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { number = 41, title = 'Authoritative', state = 'OPEN', author = 'cora', created_at = '' },
      }),
    })

    vim.wait(100, function()
      return cache['pr:open'][1].title == 'Authoritative'
    end)
    vim.system = old_system

    assert.equals('Authoritative', cache['pr:open'][1].title)
    assert.equals(2, picker_refresh_calls)
  end)

  it('updates all-PR rows in place after close succeeds', function()
    cache['pr:open'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
    }
    cache['pr:closed'] = {
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 41, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
      { number = 40, title = 'Old closed', state = 'CLOSED', author = 'bob', created_at = '' },
    }

    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('all', fake_forge())
    captured.stream(function() end)

    action_by_name('toggle').fn(captured.entries[1])

    vim.system = old_system

    assert.equals(
      'CLOSED',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:all'])[1].state
    )
    assert.is_nil(vim.tbl_filter(function(pr)
      return pr.number == 42
    end, cache['pr:open'])[1])
    assert.equals(
      'CLOSED',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:closed'])[1].state
    )
    assert.equals('42', captured.entries[1].value.num)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('reopen', labels.toggle)
    assert.is_nil(labels.approve)
    assert.is_nil(labels.merge)
    assert.is_nil(labels.draft)
    assert.equals(1, picker_refresh_calls)
  end)

  it('preserves observed open-state spelling when reopening PRs locally', function()
    cache['pr:open'] = {
      { number = 41, title = 'Follow-up', state = 'opened', author = 'cora', created_at = '' },
    }
    cache['pr:closed'] = {
      { number = 42, title = 'Fix api drift', state = 'closed', author = 'alice', created_at = '' },
    }
    cache['pr:all'] = {
      { number = 42, title = 'Fix api drift', state = 'closed', author = 'alice', created_at = '' },
      { number = 41, title = 'Follow-up', state = 'opened', author = 'cora', created_at = '' },
    }

    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.pr('closed', fake_forge())
    captured.stream(function() end)

    action_by_name('toggle').fn(captured.entries[1])

    vim.system = old_system

    assert.equals(
      'opened',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:open'])[1].state
    )
    assert.equals(
      'opened',
      vim.tbl_filter(function(pr)
        return pr.number == 42
      end, cache['pr:all'])[1].state
    )
    assert.is_true(captured.entries[1].placeholder)
    assert.equals(1, picker_refresh_calls)
  end)

  it('marks PR refresh and checks transitions as hard reopen actions', function()
    cache['pr:open'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.is_false(action_by_name('ci').reload)
    assert.is_false(action_by_name('filter').reload)
    assert.is_false(action_by_name('refresh').reload)
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
    assert.is_nil(rawget(action_by_name('toggle'), 'close'))
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
    captured.stream(function() end)

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
    captured.stream(function() end)

    action_by_name('default').fn(captured.entries[3])
    captured.stream(function() end)
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
    captured.stream(function() end)
    local labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('open', labels.default)
    assert.equals('web', labels.browse)
    assert.equals('edit', labels.edit)
    assert.equals('close', labels.toggle)
    assert.equals('create', labels.create)
    assert.equals('filter', labels.filter)
    assert.equals('refresh', labels.refresh)
  end)

  it('shows reopen for closed issue rows only', function()
    cache['issue:all'] = {
      { number = 7, title = 'Closed bug', state = 'CLOSED', author = 'alice', created_at = '' },
      { number = 6, title = 'Open bug', state = 'OPEN', author = 'bob', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())
    captured.stream(function() end)

    assert.is_not_nil(captured)

    local closed_labels = helpers.action_labels(captured.actions, captured.entries[1])
    assert.equals('reopen', closed_labels.toggle)

    local open_labels = helpers.action_labels(captured.actions, captured.entries[2])
    assert.equals('close', open_labels.toggle)
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

  it('marks the issue filter transition as a hard reopen action', function()
    cache['issue:open'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('open', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.is_false(action_by_name('filter').reload)
  end)

  it('marks issue refresh as a hard reopen action', function()
    cache['issue:open'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('open', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.is_false(action_by_name('refresh').reload)
  end)

  it(
    'patches issue caches locally and revalidates the live issue picker after close succeeds',
    function()
      cache['issue:open'] = {
        { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
        { number = 5, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
      }
      cache['issue:closed'] = {
        { number = 6, title = 'Done', state = 'CLOSED', author = 'bob', created_at = '' },
      }
      cache['issue:all'] = {
        { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
        { number = 6, title = 'Done', state = 'CLOSED', author = 'bob', created_at = '' },
        { number = 5, title = 'Follow-up', state = 'OPEN', author = 'cora', created_at = '' },
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
      pickers.issue('open', fake_issue_forge())
      captured.stream(function() end)

      action_by_name('toggle').fn(captured.entries[1])

      local closed_numbers = vim.tbl_map(function(issue)
        return issue.number
      end, cache['issue:closed'])
      table.sort(closed_numbers)

      assert.same(
        { 5 },
        vim.tbl_map(function(issue)
          return issue.number
        end, cache['issue:open'])
      )
      assert.same({ 6, 7 }, closed_numbers)
      assert.equals(
        'CLOSED',
        vim.tbl_filter(function(issue)
          return issue.number == 7
        end, cache['issue:all'])[1].state
      )
      assert.equals('5', captured.entries[1].value.num)
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'issues', 'open' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          { number = 5, title = 'Authoritative', state = 'OPEN', author = 'cora', created_at = '' },
        }),
      })

      vim.wait(100, function()
        return cache['issue:open'][1].title == 'Authoritative'
      end)
      vim.system = old_system

      assert.equals('Authoritative', cache['issue:open'][1].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it('updates all-issues rows in place after close succeeds', function()
    cache['issue:open'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }
    cache['issue:closed'] = {
      { number = 6, title = 'Done', state = 'CLOSED', author = 'bob', created_at = '' },
    }
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
      { number = 6, title = 'Done', state = 'CLOSED', author = 'bob', created_at = '' },
    }

    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())
    captured.stream(function() end)

    action_by_name('toggle').fn(captured.entries[1])

    vim.system = old_system

    assert.equals(
      'CLOSED',
      vim.tbl_filter(function(issue)
        return issue.number == 7
      end, cache['issue:all'])[1].state
    )
    assert.is_nil(vim.tbl_filter(function(issue)
      return issue.number == 7
    end, cache['issue:open'])[1])
    assert.equals(
      'CLOSED',
      vim.tbl_filter(function(issue)
        return issue.number == 7
      end, cache['issue:closed'])[1].state
    )
    assert.equals('7', captured.entries[1].value.num)
    assert.equals('reopen', helpers.action_labels(captured.actions, captured.entries[1]).toggle)
    assert.equals(1, picker_refresh_calls)
  end)

  it('preserves observed open-state spelling when reopening locally', function()
    cache['issue:open'] = {
      { number = 6, title = 'Open bug', state = 'opened', author = 'bob', created_at = '' },
    }
    cache['issue:closed'] = {
      { number = 7, title = 'Closed bug', state = 'closed', author = 'alice', created_at = '' },
    }
    cache['issue:all'] = {
      { number = 7, title = 'Closed bug', state = 'closed', author = 'alice', created_at = '' },
      { number = 6, title = 'Open bug', state = 'opened', author = 'bob', created_at = '' },
    }

    local old_system = vim.system
    vim.system = function()
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('closed', fake_issue_forge())
    captured.stream(function() end)

    action_by_name('toggle').fn(captured.entries[1])

    vim.system = old_system

    assert.equals(
      'opened',
      vim.tbl_filter(function(issue)
        return issue.number == 7
      end, cache['issue:open'])[1].state
    )
    assert.equals(
      'opened',
      vim.tbl_filter(function(issue)
        return issue.number == 7
      end, cache['issue:all'])[1].state
    )
    assert.is_true(captured.entries[1].placeholder)
    assert.equals(1, picker_refresh_calls)
  end)

  it('dispatches flattened issue actions directly from the root picker', function()
    cache['issue:open'] = {
      { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('open', fake_issue_forge())
    captured.stream(function() end)

    assert.is_not_nil(captured)
    local entry = captured.entries[1]
    action_by_name('default').fn(entry)
    action_by_name('edit').fn(entry)
    action_by_name('toggle').fn(entry)

    assert.same(
      { name = 'issue_browse', issue = { num = '42', scope = nil, state = 'OPEN' } },
      op_calls[1]
    )
    assert.same(
      { name = 'issue_edit', issue = { num = '42', scope = nil, state = 'OPEN' } },
      op_calls[2]
    )
    assert.same({
      name = 'issue_close',
      issue = { num = '42', scope = nil, state = 'OPEN' },
    }, {
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
    assert.is_nil(action_by_name('log'))
    assert.is_false(action_by_name('filter').reload)
    assert.is_false(action_by_name('failed').reload)
    assert.is_false(action_by_name('passed').reload)
    assert.is_false(action_by_name('running').reload)
    assert.is_false(action_by_name('all').reload)
    assert.is_false(action_by_name('refresh').reload)

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
    assert.is_nil(action_by_name('log'))
    assert.is_nil(action_by_name('watch'))
  end)

  it('routes CI default and browse actions through forge.ops', function()
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

    assert.is_nil(action_by_name('log'))
    assert.is_nil(action_by_name('watch'))

    action_by_name('default').fn(streamed[1])
    action_by_name('browse').fn(streamed[1])

    assert.same({
      name = 'ci_open',
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
      name = 'ci_browse',
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

  it('includes CI context in picker ordinals', function()
    local old_system = vim.system
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'feat(browse): accept shorthand target paths (#486)',
            context = 'quality',
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

    assert.equals(
      'feat(browse): accept shorthand target paths (#486) quality main',
      streamed[1].ordinal
    )
  end)

  it('routes the CI toggle action through forge.ops.ci_toggle', function()
    local pickers = require('forge.pickers')
    local entry = {
      value = {
        id = '5',
        name = 'CI',
        branch = 'main',
        status = 'in_progress',
        url = 'https://example.com',
      },
    }
    pickers.ci(fake_ci_forge(), 'main', 'all')

    local toggle = action_by_name('toggle')
    assert.is_not_nil(toggle)
    toggle.fn(entry)

    assert.same({
      id = '5',
      name = 'CI',
      branch = 'main',
      status = 'in_progress',
      url = 'https://example.com',
    }, op_calls[#op_calls].run)
    assert.equals('ci_toggle', op_calls[#op_calls].name)
  end)

  it('patches ci.all locally and revalidates the live CI picker after toggle succeeds', function()
    local old_system = vim.system
    local calls = {}
    local initial = vim.json.encode({
      {
        id = '5',
        name = 'CI',
        branch = 'main',
        status = 'in_progress',
        url = 'https://example.com',
      },
      {
        id = '4',
        name = 'Lint',
        branch = 'main',
        status = 'success',
        url = 'https://example.com/lint',
      },
    })
    vim.system = function(cmd, _, cb)
      calls[#calls + 1] = { cmd = cmd, cb = cb }
      if #calls == 1 and cb then
        cb({ code = 0, stdout = initial })
      end
      return {
        wait = function()
          return { code = 0, stdout = #calls == 1 and initial or nil }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')
    captured.stream(function() end)
    vim.wait(100, function()
      return captured.entries[1] ~= nil
    end)

    local toggle = action_by_name('toggle')
    assert.is_not_nil(toggle)
    toggle.fn(captured.entries[1])
    vim.wait(100, function()
      return calls[2] ~= nil and captured.entries[1] ~= nil
    end)

    assert.equals('cancelled', captured.entries[1].value.status)
    assert.equals('rerun', toggle.label(captured.entries[1]))
    assert.equals(1, picker_pick_calls)
    assert.equals(1, picker_refresh_calls)
    assert.same({ 'runs', 'main', '31' }, calls[2].cmd)

    calls[2].cb({
      code = 0,
      stdout = vim.json.encode({
        {
          id = '5',
          name = 'CI authoritative',
          branch = 'main',
          status = 'cancelled',
          url = 'https://example.com',
        },
        {
          id = '4',
          name = 'Lint',
          branch = 'main',
          status = 'success',
          url = 'https://example.com/lint',
        },
      }),
    })

    vim.wait(100, function()
      return captured.entries[1].value.name == 'CI authoritative'
    end)
    vim.system = old_system

    assert.equals('CI authoritative', captured.entries[1].value.name)
    assert.equals(2, picker_refresh_calls)
  end)

  it(
    'patches filtered CI views locally and revalidates them in place after toggle succeeds',
    function()
      local old_system = vim.system
      local calls = {}
      local initial = vim.json.encode({
        { id = '5', name = 'CI', branch = 'main', status = 'failure', url = 'https://example.com' },
        {
          id = '4',
          name = 'Lint',
          branch = 'main',
          status = 'success',
          url = 'https://example.com/lint',
        },
      })
      vim.system = function(cmd, _, cb)
        calls[#calls + 1] = { cmd = cmd, cb = cb }
        if #calls == 1 and cb then
          cb({ code = 0, stdout = initial })
        end
        return {
          wait = function()
            return { code = 0, stdout = #calls == 1 and initial or nil }
          end,
        }
      end

      local forge_mod = require('forge')
      local old_filter_runs = forge_mod.filter_runs
      forge_mod.filter_runs = function(runs, current_filter)
        return require('forge.format').filter_runs(runs, current_filter)
      end

      local pickers = require('forge.pickers')
      pickers.ci(fake_ci_forge(), 'main', 'fail')
      captured.stream(function() end)
      vim.wait(100, function()
        return captured.entries[1] ~= nil
      end)

      local toggle = action_by_name('toggle')
      assert.is_not_nil(toggle)
      toggle.fn(captured.entries[1])
      vim.wait(100, function()
        return calls[2] ~= nil
      end)

      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'runs', 'main', '31' }, calls[2].cmd)

      calls[2].cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '6',
            name = 'Retried',
            branch = 'main',
            status = 'failure',
            url = 'https://example.com/retried',
          },
        }),
      })

      vim.wait(100, function()
        return captured.entries[1].value and captured.entries[1].value.id == '6'
      end)
      forge_mod.filter_runs = old_filter_runs
      vim.system = old_system

      assert.equals('6', captured.entries[1].value.id)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it('labels the CI toggle action from the highlighted run status', function()
    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    local toggle = action_by_name('toggle')
    assert.is_not_nil(toggle)
    assert.equals('cancel/rerun', toggle.label(nil))
    assert.equals('cancel', toggle.label({ value = { id = '1', status = 'in_progress' } }))
    assert.equals('rerun', toggle.label({ value = { id = '2', status = 'failure' } }))
    assert.is_nil(toggle.label({ value = { id = '3', status = 'skipped' } }))
  end)

  it('gates the open action as unavailable for skipped checks', function()
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
    local default = action_by_name('default')
    assert.is_function(default.available)
    assert.is_false(default.available(captured.entries[1]))
  end)

  it('gates the open action as unavailable for checks without an extractable run id', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      {
        name = 'lint',
        link = 'https://example.com/checks/456',
        bucket = 'pass',
      },
    })

    assert.is_not_nil(captured)
    local default = action_by_name('default')
    assert.is_function(default.available)
    assert.is_false(default.available(captured.entries[1]))
  end)

  it('keeps the open action available for checks with a run id', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      { name = 'lint', bucket = 'pass', link = 'https://example.com/check', run_id = '789' },
    })

    assert.is_not_nil(captured)
    local default = action_by_name('default')
    assert.is_function(default.available)
    assert.is_true(default.available(captured.entries[1]))
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

  it('uses GitLab merge request labels in PR and checks prompts', function()
    local pickers = require('forge.pickers')
    pickers.pr(
      'open',
      fake_forge({
        name = 'gitlab',
        labels = { pr = 'Merge Requests', pr_one = 'MR' },
      })
    )

    assert.is_not_nil(captured)
    assert.equals('Open Merge Requests (1)> ', captured.prompt)

    pickers.checks(
      fake_ci_forge({
        name = 'gitlab',
        labels = { ci = 'Pipelines', pr_one = 'MR' },
      }),
      '42',
      'all',
      {
        { name = 'lint', link = 'https://example.com/check', bucket = 'pass' },
      }
    )

    assert.is_not_nil(captured)
    assert.equals('MR #42 Checks (1)> ', captured.prompt)
  end)

  it('uses scope-first prompts for filtered CI runs while loading', function()
    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'fail')

    assert.is_not_nil(captured)
    assert.equals('Failed CI for main> ', captured.prompt)
  end)

  it('uses GitLab pipeline terms for CI prompts and empty states', function()
    local pickers = require('forge.pickers')
    pickers.ci(
      fake_ci_forge({
        name = 'gitlab',
        labels = { ci = 'Pipelines', ci_inline = 'pipelines', pr_one = 'MR' },
      }),
      'main',
      'fail'
    )

    assert.is_not_nil(captured)
    assert.equals('Failed Pipelines for main> ', captured.prompt)

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

    assert.equals('No failed pipelines for main', streamed[1].display[1][1])
  end)

  it('warns when structured checks are unavailable for a forge', function()
    local pickers = require('forge.pickers')
    pickers.checks({ labels = { pr_one = 'PR' } }, '42', 'all')

    assert.same({ 'structured checks not available for this forge' }, logger_messages.warn)
  end)

  it('shows real checks fetch failures instead of no-checks placeholders', function()
    local old_system = vim.system
    local old_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
    vim.system = function(_, _, cb)
      if cb then
        cb({ code = 1, stdout = '', stderr = 'boom' })
      end
      return {
        wait = function()
          return { code = 1, stdout = '', stderr = 'boom' }
        end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all')
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
    vim.schedule = old_schedule

    assert.equals('error', streamed[1].placeholder_kind)
    assert.equals('boom', streamed[1].display[1][1])
    assert.same({}, logger_messages.info)
    assert.same({ 'fetching checks for PR #42...' }, logger_messages.debug)
    assert.same({ 'boom' }, logger_messages.error)
  end)

  it('warns when structured CI data is unavailable for a forge', function()
    local pickers = require('forge.pickers')
    pickers.ci({
      list_runs_cmd = function()
        return { 'runs' }
      end,
    }, 'main', 'all')

    assert.same({ 'structured CI data not available for this forge' }, logger_messages.warn)
  end)

  it('marks CI state jumps and refresh as hard reopen actions', function()
    local pickers = require('forge.pickers')
    pickers.ci(fake_ci_forge(), 'main', 'all')

    assert.is_not_nil(captured)
    assert.is_false(action_by_name('filter').reload)
    assert.is_false(action_by_name('failed').reload)
    assert.is_false(action_by_name('passed').reload)
    assert.is_false(action_by_name('running').reload)
    assert.is_false(action_by_name('all').reload)
    assert.is_false(action_by_name('refresh').reload)
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
    assert.same({
      'default',
      'browse',
      'filter',
      'failed',
      'passed',
      'running',
      'all',
      'refresh',
    }, captured.header_order)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('default'), 'close'))
    assert.is_nil(action_by_name('log'))

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
    assert.same({
      'default',
      'browse',
      'toggle',
      'filter',
      'failed',
      'passed',
      'running',
      'all',
      'refresh',
    }, captured.header_order)
    assert.same({}, captured.entries)
    assert.same('function', type(captured.stream))

    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(action_by_name('log'))
    assert.is_nil(action_by_name('watch'))

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

    action_by_name('default').fn(streamed[3])
    captured.stream(function() end)

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
    assert.same({
      'browse',
      'yank',
      'delete',
      'filter',
      'refresh',
    }, captured.header_order)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_false(rawget(action_by_name('yank'), 'close'))
    assert.is_nil(rawget(action_by_name('delete'), 'close'))
  end)

  it('adds a load more row when the release list exceeds the configured limit', function()
    vim.g.forge = {
      display = {
        limits = {
          releases = 2,
        },
      },
    }
    cache['release:list'] = {
      { tag = 'v3.0.0', title = 'Third', is_draft = false, is_prerelease = false },
      { tag = 'v2.0.0', title = 'Second', is_draft = false, is_prerelease = false },
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
    }

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())
    captured.stream(function() end)

    assert.same({ 'v3.0.0', 'v2.0.0' }, {
      captured.entries[1].value.tag,
      captured.entries[2].value.tag,
    })
    assert.equals('Load more...', captured.entries[3].display[1][1])
    assert.is_true(captured.entries[3].load_more)
  end)

  it('fetches more releases in place with additive next limits', function()
    vim.g.forge = {
      display = {
        limits = {
          releases = 2,
        },
      },
    }
    cache['release:list'] = {
      { tag = 'v3.0.0', title = 'Third', is_draft = false, is_prerelease = false },
      { tag = 'v2.0.0', title = 'Second', is_draft = false, is_prerelease = false },
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
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
    captured.stream(function() end)

    action_by_name('browse').fn(captured.entries[3])
    captured.stream(function() end)
    assert.same({ 'releases', '5' }, calls[1].cmd)
    calls[1].cb({
      code = 0,
      stdout = vim.json.encode({
        { tag = 'v5.0.0', title = 'Fifth', is_draft = false, is_prerelease = false },
        { tag = 'v4.0.0', title = 'Fourth', is_draft = false, is_prerelease = false },
        { tag = 'v3.0.0', title = 'Third', is_draft = false, is_prerelease = false },
        { tag = 'v2.0.0', title = 'Second', is_draft = false, is_prerelease = false },
        { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
      }),
    })

    vim.wait(100, function()
      return captured.entries[4] ~= nil
    end)
    vim.system = old_system

    assert.same({ 'v5.0.0', 'v4.0.0', 'v3.0.0', 'v2.0.0' }, {
      captured.entries[1].value.tag,
      captured.entries[2].value.tag,
      captured.entries[3].value.tag,
      captured.entries[4].value.tag,
    })
    assert.equals('Load more...', captured.entries[5].display[1][1])
    assert.equals(6, captured.entries[5].next_limit)
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
    captured.stream(function() end)
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
    captured.stream(function() end)

    action_by_name('filter').fn()
    captured.stream(function() end)
    assert.equals('Draft Releases (1)> ', captured.prompt)
    assert.equals('v2.0.0-draft', captured.entries[1].value.tag)

    action_by_name('filter').fn()
    captured.stream(function() end)
    assert.equals('Pre-releases (1)> ', captured.prompt)
    assert.equals('v1.1.0-rc1', captured.entries[1].value.tag)

    action_by_name('filter').fn()
    captured.stream(function() end)
    assert.equals('Releases (3)> ', captured.prompt)
    assert.equals('v1.0.0', captured.entries[1].value.tag)

    vim.system = old_system
    assert.same({}, calls)
  end)

  it('marks release filter and refresh as hard reopen actions', function()
    cache['release:list'] = {
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
    }

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())

    assert.is_not_nil(captured)
    assert.is_false(action_by_name('filter').reload)
    assert.is_false(action_by_name('refresh').reload)
  end)

  it(
    'patches release caches locally and revalidates the live release picker after delete succeeds',
    function()
      vim.g.forge = {
        display = {
          limits = {
            releases = 2,
          },
        },
      }
      cache['release:list'] = {
        { tag = 'v3.0.0', title = 'Third', is_draft = false, is_prerelease = false },
        { tag = 'v2.0.0', title = 'Second', is_draft = false, is_prerelease = false },
        { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
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
      captured.stream(function() end)

      action_by_name('delete').fn(captured.entries[1])

      assert.same(
        { 'v2.0.0', 'v1.0.0' },
        vim.tbl_map(function(rel)
          return rel.tag
        end, cache['release:list'])
      )
      assert.equals('v2.0.0', captured.entries[1].value.tag)
      assert.equals('v1.0.0', captured.entries[2].value.tag)
      assert.is_nil(captured.entries[3])
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'releases', '3' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          {
            tag = 'v2.0.0',
            title = 'Authoritative second',
            is_draft = false,
            is_prerelease = false,
          },
          {
            tag = 'v1.0.0',
            title = 'Authoritative first',
            is_draft = false,
            is_prerelease = false,
          },
        }),
      })

      vim.wait(100, function()
        return cache['release:list'][1].title == 'Authoritative second'
      end)
      vim.system = old_system

      assert.equals('Authoritative second', cache['release:list'][1].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it(
    'patches filtered draft releases locally and revalidates the live release picker after delete succeeds',
    function()
      vim.g.forge = {
        display = {
          limits = {
            releases = 2,
          },
        },
      }
      cache['release:list'] = {
        { tag = 'v2.0.0-draft', title = 'Draft newer', is_draft = true, is_prerelease = false },
        { tag = 'v1.0.0', title = 'Stable', is_draft = false, is_prerelease = false },
        { tag = 'v0.9.0-draft', title = 'Draft older', is_draft = true, is_prerelease = false },
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
      pickers.release('draft', fake_release_forge())
      captured.stream(function() end)

      action_by_name('delete').fn(captured.entries[1])

      assert.same(
        { 'v1.0.0', 'v0.9.0-draft' },
        vim.tbl_map(function(rel)
          return rel.tag
        end, cache['release:list'])
      )
      assert.equals('v0.9.0-draft', captured.entries[1].value.tag)
      assert.is_nil(captured.entries[2])
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'releases', '3' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          { tag = 'v1.0.0', title = 'Stable', is_draft = false, is_prerelease = false },
          {
            tag = 'v0.9.0-draft',
            title = 'Authoritative draft older',
            is_draft = true,
            is_prerelease = false,
          },
        }),
      })

      vim.wait(100, function()
        return cache['release:list'][2].title == 'Authoritative draft older'
      end)
      vim.system = old_system

      assert.equals('Authoritative draft older', cache['release:list'][2].title)
      assert.equals(2, picker_refresh_calls)
    end
  )

  it(
    'patches filtered prereleases locally and revalidates the live release picker after delete succeeds',
    function()
      vim.g.forge = {
        display = {
          limits = {
            releases = 2,
          },
        },
      }
      cache['release:list'] = {
        { tag = 'v2.0.0-rc2', title = 'RC newer', is_draft = false, is_prerelease = true },
        { tag = 'v1.0.0', title = 'Stable', is_draft = false, is_prerelease = false },
        { tag = 'v0.9.0-rc1', title = 'RC older', is_draft = false, is_prerelease = true },
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
      pickers.release('prerelease', fake_release_forge())
      captured.stream(function() end)

      action_by_name('delete').fn(captured.entries[1])

      assert.same(
        { 'v1.0.0', 'v0.9.0-rc1' },
        vim.tbl_map(function(rel)
          return rel.tag
        end, cache['release:list'])
      )
      assert.equals('v0.9.0-rc1', captured.entries[1].value.tag)
      assert.is_nil(captured.entries[2])
      assert.equals(1, picker_pick_calls)
      assert.equals(1, picker_refresh_calls)
      assert.same({ 'releases', '3' }, calls[1].cmd)

      calls[1].cb({
        code = 0,
        stdout = vim.json.encode({
          { tag = 'v1.0.0', title = 'Stable', is_draft = false, is_prerelease = false },
          {
            tag = 'v0.9.0-rc1',
            title = 'Authoritative RC older',
            is_draft = false,
            is_prerelease = true,
          },
        }),
      })

      vim.wait(100, function()
        return cache['release:list'][2].title == 'Authoritative RC older'
      end)
      vim.system = old_system

      assert.equals('Authoritative RC older', cache['release:list'][2].title)
      assert.equals(2, picker_refresh_calls)
    end
  )
end)
