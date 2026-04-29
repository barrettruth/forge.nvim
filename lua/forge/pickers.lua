local M = {}

local ci = require('forge.ci')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_shared = require('forge.picker.shared')
local picker_session = require('forge.picker.session')
local state_mod = require('forge.state')
local surface_policy = require('forge.surface_policy')

local next_ci_filter = {
  all = 'fail',
  fail = 'pass',
  pass = 'pending',
  pending = 'all',
}

local pr_header_order = {
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
}

local issue_header_order = {
  'default',
  'browse',
  'edit',
  'toggle',
  'create',
  'filter',
  'refresh',
}

local ci_header_order = {
  'default',
  'browse',
  'toggle',
  'filter',
  'failed',
  'passed',
  'running',
  'all',
  'refresh',
}

local checks_header_order = {
  'default',
  'browse',
  'filter',
  'failed',
  'passed',
  'running',
  'all',
  'refresh',
}

local release_header_order = {
  'browse',
  'yank',
  'delete',
  'filter',
  'refresh',
}
local placeholder_entry = picker_shared.placeholder_entry
local picker_failure_text = picker_shared.picker_failure_text
local picker_failure_entry = picker_shared.picker_failure_entry
local load_more_entry = picker_shared.load_more_entry
local with_placeholder = picker_shared.with_placeholder
local set_clipboard = picker_shared.set_clipboard
local cached_rows = picker_shared.cached_rows
local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_id = picker_shared.scoped_id
local list_states = picker_shared.list_states
local scoped_list_key = picker_shared.scoped_list_key
local clear_state_caches = picker_shared.clear_state_caches
local clear_list_cache = picker_shared.clear_list_cache
local refresh_picker = picker_shared.refresh_picker
local limit_settings = picker_shared.limit_settings
local ci_inline_label = picker_shared.ci_inline_label
local expanded_limit = picker_shared.expanded_limit
local maybe_prefetch_list = picker_shared.maybe_prefetch_list
local list_row = picker_shared.list_row
local remove_list_row = picker_shared.remove_list_row
local upsert_list_row = picker_shared.upsert_list_row
local normalize_pr_ref = picker_shared.normalize_pr_ref
local pr_action_fns = picker_shared.pr_action_fns
local issue_action_fns = picker_shared.issue_action_fns
local actionable_entry = picker_shared.actionable_entry
local picker_row_kind = picker_shared.picker_row_kind
local entity_row = picker_shared.entity_row
local load_more_row = picker_shared.load_more_row
local pr_toggle_entry = picker_shared.pr_toggle_entry
local issue_toggle_entry = picker_shared.issue_toggle_entry
local check_openable = picker_shared.check_openable
local pr_toggle_draft_action = picker_shared.pr_toggle_draft_action

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
---@param opts? forge.PickerLimitOpts
function M.checks(f, num, filter, cached_checks, opts)
  opts = opts or {}
  filter = filter or 'all'
  local forge_mod = require('forge')
  local ref = scoped_forge_ref(f, opts.scope)
  local current_checks = cached_checks
  local request_key = state_mod.list_key('check', scoped_id(num, scoped_key(forge_mod, ref)))
  local labels = {
    all = 'all',
    fail = 'failed',
    pass = 'passed',
    pending = 'running',
  }
  local prompt_labels = {
    fail = 'Failed',
    pass = 'Passed',
    pending = 'Running',
  }

  local function checks_prompt(count)
    local scope = ('%s #%s'):format(f.labels.pr_one, num)
    local filter_label = prompt_labels[filter]
    local title = filter_label and ('%s %s Checks'):format(scope, filter_label)
      or (scope .. ' Checks')
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_check_entries(checks)
    local filtered = forge_mod.filter_checks(checks, filter)
    local count = #filtered
    local rows_for = cached_rows(function(width)
      return forge_mod.format_checks(filtered, { width = width })
    end)
    local displays = rows_for()
    local entries = {}
    for i, c in ipairs(filtered) do
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = c,
        ordinal = c.name or '',
      })
    end
    local filter_label = labels[filter] or filter
    local empty_text = filter == 'all' and ('No checks for #%s'):format(num)
      or ('No %s checks for #%s'):format(filter_label, num)
    return with_placeholder(entries, empty_text), count
  end

  local function open_check(entry)
    if not entry then
      return
    end
    local c = entry.value
    local run_id = c.run_id or (c.link or ''):match('/actions/runs/(%d+)')
    local job_id = c.job_id or (c.link or ''):match('/job/(%d+)')
    local bucket = (c.bucket or ''):lower()
    local in_progress = bucket == 'pending'
    local check_ref = c.scope or ref
    if in_progress and f.live_tail_cmd then
      require('forge.term').open(f:live_tail_cmd(run_id, job_id, check_ref), { url = c.link })
      return
    end
    log.debug('fetching check logs...')
    local cmd = f:check_log_cmd(run_id, bucket == 'fail', job_id, check_ref)
    local steps_cmd = f.steps_cmd and f:steps_cmd(run_id, check_ref) or nil
    local status_cmd = f.run_status_cmd and f:run_status_cmd(run_id, check_ref) or nil
    require('forge.log').open(cmd, {
      forge_name = f.name,
      scope = check_ref,
      run_id = run_id,
      url = c.link,
      steps_cmd = steps_cmd,
      job_id = job_id,
      in_progress = in_progress,
      status_cmd = status_cmd,
    })
  end

  local actions = {
    {
      name = 'default',
      label = 'open',
      available = check_openable,
      fn = open_check,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and entry.value.link then
          vim.ui.open(entry.value.link)
        end
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      fn = function()
        M.checks(
          f,
          num,
          next_ci_filter[filter] or 'all',
          current_checks,
          { back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'failed',
      label = 'failed',
      reload = false,
      fn = function()
        M.checks(f, num, 'fail', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      reload = false,
      fn = function()
        M.checks(f, num, 'pass', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      reload = false,
      fn = function()
        M.checks(f, num, 'pending', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      reload = false,
      fn = function()
        M.checks(f, num, 'all', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        log.debug(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
        M.checks(f, num, filter, nil, { back = opts.back, scope = ref })
      end,
    },
  }

  local function open_picker(checks)
    current_checks = checks
    for _, check in ipairs(checks) do
      check.scope = check.scope or ref
    end
    local entries, count = build_check_entries(checks)

    picker.pick({
      prompt = checks_prompt(count),
      entries = entries,
      actions = actions,
      header_order = checks_header_order,
      picker_name = 'ci',
      back = opts.back,
    })
  end

  if cached_checks then
    log.debug(('checks (%s #%s, cached)'):format(f.labels.pr_one, num))
    open_picker(cached_checks)
    return
  end

  if f.checks_json_cmd then
    picker_session.pick_json({
      key = request_key,
      loading_prompt = checks_prompt,
      actions = actions,
      header_order = checks_header_order,
      picker_name = 'ci',
      back = opts.back,
      cmd = function()
        return f:checks_json_cmd(num, ref)
      end,
      on_fetch = function()
        log.debug(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
      end,
      on_success = function(checks)
        current_checks = checks
      end,
      build_entries = function(checks)
        current_checks = checks
        for _, check in ipairs(checks) do
          check.scope = check.scope or ref
        end
        local entries = build_check_entries(checks)
        return entries
      end,
      open = open_picker,
      on_failure = function(failure)
        log.error(
          picker_failure_text(
            failure,
            ('failed to fetch checks for %s #%s'):format(f.labels.pr_one, num)
          )
        )
      end,
      error_entry = function(failure)
        return picker_failure_entry(failure, ('Failed to fetch checks for #%s'):format(num))
      end,
    })
  else
    log.warn('structured checks not available for this forge')
  end
end

---@param f forge.Forge
---@param branch string?
---@param filter string?
---@param opts? forge.PickerLimitOpts
function M.ci(f, branch, filter, opts)
  opts = opts or {}
  filter = filter or 'all'
  local forge_mod = require('forge')
  local limits = limit_settings(forge_mod.config().display.limits.runs, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local ref = scoped_forge_ref(f, opts.scope)
  local request_key =
    state_mod.list_key('ci', scoped_id(branch or 'all', scoped_key(forge_mod, ref)))
  local labels = {
    all = 'all',
    fail = 'failed',
    pass = 'passed',
    pending = 'running',
  }
  local prompt_labels = {
    fail = 'Failed',
    pass = 'Passed',
    pending = 'Running',
  }
  local scope_label = branch or 'all branches'
  local current_limit = visible_limit
  ---@type forge.CIRun[]?
  local current_runs
  local runs_stale = true
  local picker_handle

  ---@param runs table[]
  ---@return forge.CIRun[]
  local function normalize_ci_runs(runs)
    local normalized = {}
    for _, entry in ipairs(runs) do
      local run = f:normalize_run(entry)
      run.scope = run.scope or ref
      table.insert(normalized, run)
    end
    return normalized
  end

  local function ci_prompt(count)
    local filter_label = prompt_labels[filter]
    local title = filter_label and ('%s %s for %s'):format(filter_label, f.labels.ci, scope_label)
      or ('%s for %s'):format(f.labels.ci, scope_label)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_ci_entries(runs, limit)
    limit = limit or current_limit
    local normalized = {}
    for _, entry in ipairs(runs) do
      local run = vim.deepcopy(entry)
      run.scope = run.scope or ref
      table.insert(normalized, run)
    end
    local has_more = #normalized > limit
    local filtered = forge_mod.filter_runs(normalized, filter)
    if #filtered > limit then
      filtered = vim.list_slice(filtered, 1, limit)
    end
    local count = #filtered
    local rows_for = cached_rows(function(width)
      return forge_mod.format_runs(filtered, { width = width })
    end)
    local displays = rows_for()

    local entries = {}
    for i, run in ipairs(filtered) do
      local ordinal = table.concat(
        vim.tbl_filter(function(part)
          return type(part) == 'string' and vim.trim(part) ~= ''
        end, { run.name or '', run.context or '', run.branch or '' }),
        ' '
      )
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = run,
        ordinal = ordinal,
      })
    end
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), true)
    end
    local filter_label = labels[filter] or filter
    local run_label = ci_inline_label(f)
    local empty_text
    if branch and filter ~= 'all' then
      empty_text = ('No %s %s for %s'):format(filter_label, run_label, branch)
    elseif branch then
      empty_text = ('No %s for %s'):format(run_label, branch)
    elseif filter ~= 'all' then
      empty_text = ('No %s %s'):format(filter_label, run_label)
    else
      empty_text = ('No %s'):format(run_label)
    end
    return with_placeholder(entries, empty_text), count
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function emit_cached(emit)
    local entries = build_ci_entries(current_runs, current_limit)
    for _, entry in ipairs(entries) do
      emit(entry)
    end
    emit(nil)
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_runs(emit)
    if current_runs and not runs_stale then
      emit_cached(emit)
      return
    end
    log.debug('fetching ' .. ci_inline_label(f) .. '...')
    picker_session.request_json(
      request_key,
      f:list_runs_json_cmd(branch, ref, current_limit + 1),
      function(ok, runs, failure, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error(picker_failure_text(failure, 'failed to fetch ' .. ci_inline_label(f)))
          emit(picker_failure_entry(failure, 'Failed to fetch ' .. ci_inline_label(f)))
          emit(nil)
          return
        end
        current_runs = normalize_ci_runs(runs)
        runs_stale = false
        emit_cached(emit)
      end
    )
  end

  ---@return nil
  local function rerender_ci_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.ci(f, branch, filter, { limit = current_limit, back = opts.back, scope = ref })
  end

  ---@return nil
  local function revalidate_current_runs()
    picker_session.request_json(
      request_key,
      f:list_runs_json_cmd(branch, ref, current_limit + 1),
      function(ok, runs, failure, stale)
        if stale then
          return
        end
        if not ok then
          log.error(picker_failure_text(failure, 'failed to fetch ' .. ci_inline_label(f)))
          return
        end
        current_runs = normalize_ci_runs(runs)
        runs_stale = false
        rerender_ci_list()
      end
    )
  end

  ---@param run forge.CIRun
  ---@return string
  local function next_ci_status(run)
    local status = type(run.status) == 'string' and vim.trim(run.status) or ''
    local next_status = ci.toggle_verb(run) == 'cancel' and 'cancelled' or 'queued'
    if status ~= '' and status == status:upper() then
      return next_status:upper()
    end
    return next_status
  end

  ---@param id string
  ---@return integer?, forge.CIRun?
  local function ci_run_row(id)
    if type(current_runs) ~= 'table' then
      return nil, nil
    end
    local target = tostring(id or '')
    for index, run in ipairs(current_runs) do
      local current_run = run
      if type(current_run) == 'table' and current_run.id == nil then
        current_run = f:normalize_run(current_run)
        current_run.scope = current_run.scope or ref
      end
      if tostring(type(current_run) == 'table' and current_run.id or '') == target then
        return index, current_run
      end
    end
    return nil, nil
  end

  ---@param entry forge.PickerEntry
  local function locally_toggle_ci_run(entry)
    local index, run = ci_run_row(entry.value.id)
    if not index or type(run) ~= 'table' then
      runs_stale = true
      rerender_ci_list()
      return
    end
    local updated_run = vim.deepcopy(run)
    updated_run.status = next_ci_status(run)
    current_runs[index] = updated_run
    rerender_ci_list()
    revalidate_current_runs()
  end

  local actions = {
    {
      name = 'default',
      label = 'open',
      fn = function(entry)
        if not entry then
          return
        end
        if entry.load_more then
          current_limit = entry.next_limit
          runs_stale = true
          return
        end
        ops.ci_open(f, entry.value)
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        ops.ci_browse(f, entry.value)
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      fn = function()
        M.ci(
          f,
          branch,
          next_ci_filter[filter] or 'all',
          { limit = current_limit, back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'failed',
      label = 'failed',
      reload = false,
      fn = function()
        M.ci(f, branch, 'fail', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      reload = false,
      fn = function()
        M.ci(f, branch, 'pass', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      reload = false,
      fn = function()
        M.ci(f, branch, 'pending', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      reload = false,
      fn = function()
        M.ci(f, branch, 'all', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'toggle',
      label = function(entry)
        if entry == nil then
          return 'cancel/rerun'
        end
        return surface_policy.ci_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local refresh_current = function()
          runs_stale = true
          rerender_ci_list()
        end
        ops.ci_toggle(f, entry.value, {
          on_success = function()
            locally_toggle_ci_run(entry)
          end,
          on_failure = refresh_current,
        })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        log.debug('refreshing ' .. ci_inline_label(f) .. '...')
        runs_stale = true
        if refresh_picker(picker_handle) then
          return
        end
        M.ci(f, branch, filter, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  if f.list_runs_json_cmd then
    picker_handle = picker.pick({
      prompt = ci_prompt(),
      entries = {},
      actions = actions,
      header_order = ci_header_order,
      picker_name = 'ci',
      back = opts.back,
      stream = stream_runs,
    })
  elseif f.list_runs_cmd then
    log.warn('structured CI data not available for this forge')
  end
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.pr(state, f, opts)
  require('forge.picker.pr').pick(state, f, opts)
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.issue(state, f, opts)
  require('forge.picker.issue').pick(state, f, opts)
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.issue_close(f, num, ref)
  ops.issue_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.issue_reopen(f, num, ref)
  ops.issue_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_close(f, num, ref)
  ops.pr_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_reopen(f, num, ref)
  ops.pr_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@return table<string, function>
function M.pr_actions(f, pr)
  return pr_action_fns(f, normalize_pr_ref(pr))
end

---@param state 'all'|'draft'|'prerelease'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.release(state, f, opts)
  opts = opts or {}
  local forge_mod = require('forge')
  local limits = limit_settings(forge_mod.config().display.limits.releases, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local ref = scoped_forge_ref(f, opts.scope)
  local cache_key = state_mod.list_key('release', scoped_id('list', scoped_key(forge_mod, ref)))
  local rel_fields = f.release_fields
  local next_state = ({ all = 'draft', draft = 'prerelease', prerelease = 'all' })[state]
  local title = ({ all = 'Releases', draft = 'Draft Releases', prerelease = 'Pre-releases' })[state]
    or 'Releases'
  local current_limit = visible_limit
  local current_releases
  local releases_stale = true
  local picker_handle

  local function remember_release_fetch(releases, requested_limit)
    if type(releases) == 'table' then
      releases._fetch_limit = requested_limit
    end
    return releases
  end

  local function cached_releases()
    local cached = state_mod.get_list(cache_key)
    if not cached then
      return nil
    end
    local cached_fetch_limit = rawget(cached, '_fetch_limit')
    if cached_fetch_limit == nil then
      if current_limit == limit_step then
        return cached
      end
      return nil
    end
    if cached_fetch_limit >= fetch_limit or #cached < cached_fetch_limit then
      return cached
    end
    return nil
  end

  local function release_prompt(count)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_release_entries(releases, limit)
    limit = limit or current_limit
    local filtered = releases
    if state == 'draft' and rel_fields.is_draft then
      filtered = {}
      for _, release in ipairs(releases) do
        if release[rel_fields.is_draft] == true then
          filtered[#filtered + 1] = release
        end
      end
    elseif state == 'prerelease' and rel_fields.is_prerelease then
      filtered = {}
      for _, release in ipairs(releases) do
        if release[rel_fields.is_prerelease] == true then
          filtered[#filtered + 1] = release
        end
      end
    end

    local has_more = #releases > limit
    if #filtered > limit then
      filtered = vim.list_slice(filtered, 1, limit)
    end
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_releases(filtered, rel_fields, { width = width })
    end)
    local displays = rows_for()
    for i, rel in ipairs(filtered) do
      local tag = tostring(rel[rel_fields.tag] or '')
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = { tag = tag, rel = rel, scope = ref },
        ordinal = tag .. ' ' .. (rel[rel_fields.title] or ''),
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), true)
    end
    local empty_text = state == 'all' and 'No releases'
      or state == 'draft' and 'No draft releases'
      or 'No prerelease releases'
    return with_placeholder(entries, empty_text), count
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function emit_cached_releases(emit)
    local entries = build_release_entries(current_releases, current_limit)
    for _, entry in ipairs(entries) do
      emit(entry)
    end
    emit(nil)
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_releases(emit)
    if current_releases and not releases_stale then
      emit_cached_releases(emit)
      return
    end
    log.debug('fetching releases...')
    local requested = current_limit + 1
    picker_session.request_json(
      cache_key,
      f:list_releases_json_cmd(ref, requested),
      function(ok, releases, failure, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error(picker_failure_text(failure, 'failed to fetch releases'))
          emit(picker_failure_entry(failure, 'Failed to fetch releases'))
          emit(nil)
          return
        end
        current_releases = remember_release_fetch(releases, requested)
        releases_stale = false
        state_mod.set_list(cache_key, current_releases)
        emit_cached_releases(emit)
      end
    )
  end

  local function rerender_release_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.release(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function revalidate_current_releases()
    local requested = current_limit + 1
    picker_session.request_json(
      cache_key,
      f:list_releases_json_cmd(ref, requested),
      function(ok, releases, failure, stale)
        if stale then
          return
        end
        if not ok then
          log.error(picker_failure_text(failure, 'failed to fetch releases'))
          return
        end
        current_releases = remember_release_fetch(releases, requested)
        releases_stale = false
        state_mod.set_list(cache_key, current_releases)
        rerender_release_list()
      end
    )
  end

  ---@param entry forge.PickerEntry
  local function locally_delete_release(entry)
    local tag_field = rel_fields.tag
    local removed = remove_list_row(current_releases, tag_field, entry.value.tag)
    if removed == nil then
      clear_list_cache(cache_key)
      releases_stale = true
      rerender_release_list()
      return
    end
    state_mod.set_list(cache_key, current_releases)
    rerender_release_list()
    revalidate_current_releases()
  end

  local function reopen_list()
    clear_list_cache(cache_key)
    releases_stale = true
    refresh_picker(picker_handle)
  end

  local actions = {
    {
      name = 'browse',
      label = 'open',
      close = false,
      fn = function(entry)
        if entry and entry.load_more then
          current_limit = entry.next_limit
          releases_stale = true
        elseif entry then
          ops.release_browse(f, entry.value)
        end
      end,
    },
    {
      name = 'yank',
      label = 'copy',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          local base = forge_mod.remote_web_url(entry.value.scope)
          local tag = entry.value.tag
          local url = base .. '/releases/tag/' .. tag
          set_clipboard(url)
          log.info('copied release URL')
        end
      end,
    },
    {
      name = 'delete',
      label = 'delete',
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        ops.release_delete(f, entry.value, {
          on_success = function()
            locally_delete_release(entry)
          end,
          on_failure = reopen_list,
        })
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      fn = function()
        M.release(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        clear_list_cache(cache_key)
        releases_stale = true
        if refresh_picker(picker_handle) then
          return
        end
        M.release(state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  local cached = cached_releases()
  if cached then
    current_releases = cached
    releases_stale = false
  end

  local initial_prompt
  if current_releases then
    local _, count = build_release_entries(current_releases, current_limit)
    initial_prompt = release_prompt(count)
  else
    initial_prompt = release_prompt()
  end

  picker_handle = picker.pick({
    prompt = initial_prompt,
    entries = {},
    actions = actions,
    header_order = release_header_order,
    picker_name = 'release',
    back = opts.back,
    stream = stream_releases,
  })
end

function M.git()
  require('forge').open()
end

return M
