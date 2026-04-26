local M = {}

local availability = require('forge.availability')
local layout = require('forge.layout')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_session = require('forge.picker.session')

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

---@param text string
---@param kind? 'empty'|'error'
---@return forge.PickerEntry
local function placeholder_entry(text, kind)
  return {
    display = { { text, 'ForgeDim' } },
    value = nil,
    ordinal = text,
    placeholder = true,
    placeholder_kind = kind or 'empty',
  }
end

---@param next_limit integer
---@param keep_open boolean?
---@return forge.PickerEntry
local function load_more_entry(next_limit, keep_open)
  local entry = {
    display = { { 'Load more...', 'ForgeDim' } },
    value = nil,
    ordinal = 'Load more',
    load_more = true,
    next_limit = next_limit,
  }
  if keep_open then
    entry.keep_open = true
  else
    entry.force_close = true
  end
  return entry
end

---@param entries forge.PickerEntry[]
---@param text string
---@return forge.PickerEntry[]
local function with_placeholder(entries, text)
  if #entries > 0 then
    return entries
  end
  return { placeholder_entry(text, 'empty') }
end

local function set_clipboard(text)
  local ok = pcall(vim.fn.setreg, '+', text)
  if not ok then
    pcall(vim.fn.setreg, '"', text)
  end
end

local function cached_rows(build)
  local cache = {}
  return function(width)
    width = width or layout.picker_width()
    local rows = cache[width]
    if rows == nil then
      rows = build(width)
      cache[width] = rows
    end
    return rows
  end
end

local function scoped_forge_ref(f, ref)
  if ref then
    return ref
  end
  local forge_mod = require('forge')
  if forge_mod.current_scope then
    return forge_mod.current_scope(f.name)
  end
  return nil
end

local function scoped_key(forge_mod, ref)
  if forge_mod.scope_key then
    return forge_mod.scope_key(ref)
  end
  return ''
end

local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

local list_states = { 'open', 'closed', 'all' }

local function scoped_list_key(forge_mod, kind, state, suffix)
  if suffix ~= nil and suffix ~= '' then
    return forge_mod.list_key(kind, state .. '|' .. suffix)
  end
  return forge_mod.list_key(kind, state)
end

local function clear_state_caches(forge_mod, kind, suffix)
  for _, state in ipairs(list_states) do
    local key = scoped_list_key(forge_mod, kind, state, suffix)
    forge_mod.clear_list(key)
    picker_session.invalidate(key)
  end
end

local function clear_list_cache(forge_mod, key)
  forge_mod.clear_list(key)
  picker_session.invalidate(key)
end

local function refresh_picker(handle)
  return handle and type(handle.refresh) == 'function' and handle.refresh() == true
end

local function limit_settings(base_limit, requested_limit)
  local visible_limit = requested_limit or base_limit
  return {
    step = base_limit,
    visible = visible_limit,
    fetch = visible_limit + 1,
    use_cache = visible_limit == base_limit,
  }
end

---@param f forge.Forge
---@return string
local function ci_inline_label(f)
  return (f.labels and f.labels.ci_inline) or 'runs'
end

local function expanded_limit(limit, step)
  return limit + step
end

local function maybe_prefetch_list(forge_mod, kind, state, label, cmd, suffix)
  local key = scoped_list_key(forge_mod, kind, state, suffix)
  local started = picker_session.prefetch_json({
    key = key,
    cmd = cmd,
    skip_if = function()
      return forge_mod.get_list(key) ~= nil
    end,
    on_success = function(data)
      forge_mod.set_list(key, data)
    end,
  })
  if started then
    log.debug(('prefetching %s list (%s)...'):format(label, state))
  end
end

local function list_row(rows, field, id)
  if type(rows) ~= 'table' then
    return nil, nil
  end
  local target = tostring(id or '')
  for index, row in ipairs(rows) do
    if tostring(row[field] or '') == target then
      return index, row
    end
  end
  return nil, nil
end

local function remove_list_row(rows, field, id)
  local index, row = list_row(rows, field, id)
  if not index then
    return nil
  end
  table.remove(rows, index)
  return row
end

local function upsert_list_row(rows, field, id, row)
  local index = list_row(rows, field, id)
  if index then
    rows[index] = row
    return
  end
  rows[#rows + 1] = row
end

---@param pr forge.PRRefLike
---@return forge.PRRef
local function normalize_pr_ref(pr)
  if type(pr) == 'table' then
    return pr
  end
  return { num = pr }
end

---@param f forge.Forge
---@param pr forge.PRRef
---@return table<string, function>
local function pr_action_fns(f, pr)
  return {
    review = function()
      ops.pr_review(f, pr)
    end,
    ci = function(opts)
      ops.pr_ci(f, pr, opts)
    end,
    edit = function()
      ops.pr_edit(pr)
    end,
  }
end

local function issue_action_fns(f, issue)
  return {
    browse = function()
      ops.issue_browse(f, issue)
    end,
    edit = function()
      ops.issue_edit(issue)
    end,
  }
end

local function actionable_entry(entry)
  return entry ~= nil and not entry.load_more
end

local function picker_row_kind(entry)
  if type(picker.row_kind) ~= 'function' then
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
  end
  return picker.row_kind(entry)
end

local function entity_row(entry)
  return picker_row_kind(entry) == 'entity'
end

local function load_more_row(entry)
  return picker_row_kind(entry) == 'load_more'
end

local function pr_toggle_entry(entry)
  return actionable_entry(entry) and picker.pr_toggle_verb(entry) ~= nil
end

local function issue_toggle_entry(entry)
  return actionable_entry(entry) and picker.issue_toggle_verb(entry) ~= nil
end

local function check_openable(entry)
  if not actionable_entry(entry) or entry.placeholder then
    return false
  end
  local c = entry.value
  if type(c) ~= 'table' then
    return false
  end
  if (c.bucket or ''):lower() == 'skipping' then
    return false
  end
  local run_id = c.run_id or (c.link or ''):match('/actions/runs/(%d+)')
  return run_id ~= nil
end

---@param f forge.Forge
---@param pr forge.PRRef
local function pr_toggle_draft_action(f, pr, opts)
  opts = opts or {}
  local is_draft = rawget(pr, 'is_draft')
  if is_draft == nil then
    local pr_state = require('forge').pr_state(f, pr.num, pr.scope)
    is_draft = pr_state.is_draft == true
  end
  ops.pr_toggle_draft(f, pr, is_draft, opts)
end

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
  local request_key = forge_mod.list_key('check', scoped_id(num, scoped_key(forge_mod, ref)))
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
    log.info('fetching check logs...')
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
        log.info(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
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
        log.info(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
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
      on_failure = function()
        log.info('no checks found')
      end,
      error_entry = function()
        return placeholder_entry(('No checks for #%s'):format(num))
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
    forge_mod.list_key('ci', scoped_id(branch or 'all', scoped_key(forge_mod, ref)))
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
  local current_runs
  local runs_stale = true
  local picker_handle

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
      local run = f:normalize_run(entry)
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
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = run,
        ordinal = run.name .. ' ' .. run.branch,
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
    log.info('fetching ' .. ci_inline_label(f) .. '...')
    picker_session.request_json(
      request_key,
      f:list_runs_json_cmd(branch, ref, current_limit + 1),
      function(ok, runs, _, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error('failed to fetch ' .. ci_inline_label(f))
          emit(placeholder_entry('Failed to fetch ' .. ci_inline_label(f)))
          emit(nil)
          return
        end
        current_runs = runs
        runs_stale = false
        emit_cached(emit)
      end
    )
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
        return picker.ci_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local refresh_current = function()
          runs_stale = true
          refresh_picker(picker_handle)
        end
        ops.ci_toggle(
          f,
          entry.value,
          { on_success = refresh_current, on_failure = refresh_current }
        )
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        log.info('refreshing ' .. ci_inline_label(f) .. '...')
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
  opts = opts or {}
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limits = limit_settings(cfg.display.limits.pulls, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local use_cache = limits.use_cache
  local ref = scoped_forge_ref(f, opts.scope)
  local scope_suffix = scoped_key(forge_mod, ref)
  local cache_key = scoped_list_key(forge_mod, 'pr', state, scope_suffix)
  local pr_fields = f.pr_fields
  local num_field = pr_fields.number
  local pr_state_field = pr_fields.state
  local show_state = state ~= 'open'
  local current_limit = visible_limit
  local current_prs
  local prs_stale = true
  local picker_handle

  local function build_pr_entries(prs, limit)
    limit = limit or current_limit

    table.sort(prs, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #prs > limit
    if has_more then
      prs = vim.list_slice(prs, 1, limit)
    end
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_prs(prs, pr_fields, show_state, { width = width })
    end)
    local displays = rows_for()
    for i, pr in ipairs(prs) do
      local num = tostring(pr[pr_fields.number] or '')
      local draft_field = rawget(pr_fields, 'is_draft')
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = {
          num = num,
          scope = ref,
          state = pr[pr_fields.state],
          is_draft = draft_field and pr[draft_field] or nil,
        },
        ordinal = (pr[pr_fields.title] or '') .. ' #' .. num,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), true)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.pr)
      or ('No %s %s'):format(state, f.labels.pr)
    return with_placeholder(entries, empty_text), count
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function emit_cached_prs(emit)
    local entries = build_pr_entries(current_prs, current_limit)
    for _, entry in ipairs(entries) do
      emit(entry)
    end
    emit(nil)
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_pr_json_cmd then
      return
    end
    maybe_prefetch_list(
      forge_mod,
      'pr',
      next_state,
      f.labels.pr,
      f:list_pr_json_cmd(next_state, fetch_limit, ref),
      scope_suffix
    )
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_prs(emit)
    if current_prs and not prs_stale then
      emit_cached_prs(emit)
      return
    end
    log.info(('fetching %s list (%s)...'):format(f.labels.pr, state))
    picker_session.request_json(
      cache_key,
      f:list_pr_json_cmd(state, current_limit + 1, ref),
      function(ok, prs, _, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error('failed to fetch ' .. f.labels.pr)
          emit(placeholder_entry('Failed to fetch ' .. f.labels.pr, 'error'))
          emit(nil)
          return
        end
        current_prs = prs
        prs_stale = false
        if use_cache then
          forge_mod.set_list(cache_key, prs)
        end
        emit_cached_prs(emit)
        maybe_prefetch_next()
      end
    )
  end

  local function rerender_pr_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.pr(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function refresh_pr_list()
    prs_stale = true
    rerender_pr_list()
  end

  local function reopen_list()
    clear_state_caches(forge_mod, 'pr', scope_suffix)
    forge_mod.clear_pr_state(nil, ref)
    refresh_pr_list()
  end

  local function pr_cache_key(list_state)
    return scoped_list_key(forge_mod, 'pr', list_state, scope_suffix)
  end

  local function observed_open_pr_state(rows)
    if type(rows) ~= 'table' then
      return nil
    end
    for _, pr in ipairs(rows) do
      local value = pr[pr_state_field]
      if type(value) == 'string' then
        local text = vim.trim(value)
        local lower = text:lower()
        if lower == 'open' or lower == 'opened' then
          return text
        end
      end
    end
    return nil
  end

  local function next_pr_state(current_pr, verb)
    local current_state = current_pr[pr_state_field]
    local current_text = type(current_state) == 'string' and vim.trim(current_state) or ''
    if verb == 'close' then
      if current_text ~= '' and current_text == current_text:upper() then
        return 'CLOSED'
      end
      return 'closed'
    end
    local open_state = observed_open_pr_state(state == 'open' and current_prs or nil)
      or observed_open_pr_state(state == 'all' and current_prs or nil)
      or observed_open_pr_state(forge_mod.get_list(pr_cache_key('open')))
      or observed_open_pr_state(forge_mod.get_list(pr_cache_key('all')))
    if open_state then
      return open_state
    end
    if current_text ~= '' and current_text == current_text:upper() then
      return 'OPEN'
    end
    return 'open'
  end

  local function patch_pr_cache(list_state, mutate)
    local key = pr_cache_key(list_state)
    local prs = forge_mod.get_list(key)
    if type(prs) ~= 'table' then
      return
    end
    mutate(prs)
    forge_mod.set_list(key, prs)
  end

  local function revalidate_current_prs()
    picker_session.request_json(
      cache_key,
      f:list_pr_json_cmd(state, current_limit + 1, ref),
      function(ok, prs, _, stale)
        if stale then
          return
        end
        if not ok then
          log.error('failed to fetch ' .. f.labels.pr)
          return
        end
        current_prs = prs
        prs_stale = false
        if use_cache then
          forge_mod.set_list(cache_key, prs)
        end
        rerender_pr_list()
        maybe_prefetch_next()
      end
    )
  end

  local function locally_toggle_pr(entry, verb)
    local current_index, current_pr = list_row(current_prs, num_field, entry.value.num)
    if not current_index or type(current_pr) ~= 'table' then
      refresh_pr_list()
      return
    end
    local updated_pr = vim.deepcopy(current_pr)
    updated_pr[pr_state_field] = next_pr_state(current_pr, verb)

    if state == 'all' then
      current_prs[current_index] = updated_pr
    else
      table.remove(current_prs, current_index)
    end
    if use_cache then
      forge_mod.set_list(cache_key, current_prs)
    end

    if verb == 'close' then
      if state ~= 'closed' then
        patch_pr_cache('closed', function(prs)
          upsert_list_row(prs, num_field, entry.value.num, vim.deepcopy(updated_pr))
        end)
      end
      if state ~= 'open' then
        patch_pr_cache('open', function(prs)
          remove_list_row(prs, num_field, entry.value.num)
        end)
      end
    else
      if state ~= 'open' then
        patch_pr_cache('open', function(prs)
          upsert_list_row(prs, num_field, entry.value.num, vim.deepcopy(updated_pr))
        end)
      end
      if state ~= 'closed' then
        patch_pr_cache('closed', function(prs)
          remove_list_row(prs, num_field, entry.value.num)
        end)
      end
    end
    if state ~= 'all' then
      patch_pr_cache('all', function(prs)
        upsert_list_row(prs, num_field, entry.value.num, vim.deepcopy(updated_pr))
      end)
    end

    rerender_pr_list()
    revalidate_current_prs()
  end

  local function back_to_list()
    M.pr(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function pr_entity_only(entry)
    return entity_row(entry)
  end

  local function pr_load_more_or_entity(entry)
    return entity_row(entry) or load_more_row(entry)
  end

  local function pr_create_visible(entry)
    local kind = picker_row_kind(entry)
    return kind == 'none'
      or kind == 'load_more'
      or kind == 'empty'
      or kind == 'error'
      or kind == 'entity'
  end

  local function pr_filter_visible(entry)
    local kind = picker_row_kind(entry)
    return kind ~= 'error'
  end

  local function pr_refresh_visible(_)
    return true
  end

  local actions = {
    {
      name = 'default',
      label = function(entry)
        if load_more_row(entry) then
          return 'load more'
        end
        return require('forge.review').label(f, entry and entry.value or nil)
      end,
      available = pr_load_more_or_entity,
      fn = function(entry)
        if entry and entry.load_more then
          current_limit = entry.next_limit
          prs_stale = true
        elseif entry then
          pr_action_fns(f, entry.value).review()
        end
      end,
    },
    {
      name = 'ci',
      label = 'checks',
      reload = false,
      available = pr_entity_only,
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).ci({ back = back_to_list })
        end
      end,
    },
    {
      name = 'edit',
      label = 'edit',
      available = pr_entity_only,
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).edit()
        end
      end,
    },
    {
      name = 'approve',
      label = 'approve',
      available = function(entry)
        return availability.pr_can_approve(f, entry)
      end,
      fn = function(entry)
        if entry and not entry.load_more then
          ops.pr_approve(f, entry.value, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'merge',
      label = 'merge',
      available = function(entry)
        return availability.pr_can_merge(f, entry)
      end,
      fn = function(entry)
        if entry and not entry.load_more then
          ops.pr_merge(f, entry.value, nil, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'create',
      label = 'create',
      available = pr_create_visible,
      fn = function()
        ops.pr_create({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'toggle',
      available = pr_toggle_entry,
      label = function(entry)
        if entry == nil then
          return 'close/reopen'
        end
        return picker.pr_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local verb = picker.pr_toggle_verb(entry)
        local callbacks = {
          on_success = function()
            locally_toggle_pr(entry, verb)
          end,
          on_failure = refresh_pr_list,
        }
        if verb == 'close' then
          ops.pr_close(f, entry.value, callbacks)
        elseif verb == 'reopen' then
          ops.pr_reopen(f, entry.value, callbacks)
        end
      end,
    },
    {
      name = 'draft',
      label = function(entry)
        return availability.pr_draft_label(f, entry)
      end,
      available = function(entry)
        return availability.pr_can_toggle_draft(f, entry)
      end,
      fn = function(entry)
        if entry and not entry.load_more and f.capabilities.draft then
          pr_toggle_draft_action(f, entry.value, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      available = pr_filter_visible,
      fn = function()
        M.pr(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      available = pr_refresh_visible,
      fn = function()
        clear_state_caches(forge_mod, 'pr', scope_suffix)
        forge_mod.clear_pr_state(nil, ref)
        refresh_pr_list()
      end,
    },
  }

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  if cached then
    current_prs = cached
    prs_stale = false
  end

  local initial_prompt
  if current_prs then
    local _, count = build_pr_entries(current_prs, current_limit)
    initial_prompt = ('%s %s (%d)> '):format(state_label, f.labels.pr, count)
  else
    initial_prompt = ('%s %s> '):format(state_label, f.labels.pr)
  end

  picker_handle = picker.pick({
    prompt = initial_prompt,
    entries = {},
    actions = actions,
    header_order = pr_header_order,
    picker_name = 'pr',
    back = opts.back,
    stream = stream_prs,
  })

  if current_prs then
    maybe_prefetch_next()
  end
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.issue(state, f, opts)
  opts = opts or {}
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limits = limit_settings(cfg.display.limits.issues, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local use_cache = limits.use_cache
  local ref = scoped_forge_ref(f, opts.scope)
  local scope_suffix = scoped_key(forge_mod, ref)
  local cache_key = scoped_list_key(forge_mod, 'issue', state, scope_suffix)
  local issue_fields = f.issue_fields
  local num_field = issue_fields.number
  local issue_state_field = issue_fields.state
  local issue_show_state = state == 'all'
  local current_limit = visible_limit
  local current_issues
  local issues_stale = true
  local picker_handle

  local function build_issue_entries(issues, limit)
    limit = limit or current_limit

    table.sort(issues, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #issues > limit
    if has_more then
      issues = vim.list_slice(issues, 1, limit)
    end
    local state_field = issue_fields.state
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_issues(issues, issue_fields, issue_show_state, { width = width })
    end)
    local displays = rows_for()
    for i, issue in ipairs(issues) do
      local n = tostring(issue[num_field] or '')
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = { num = n, scope = ref, state = issue[state_field] },
        ordinal = (issue[issue_fields.title] or '') .. ' #' .. n,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), true)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.issue)
      or ('No %s %s'):format(state, f.labels.issue)
    return with_placeholder(entries, empty_text), count
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function emit_cached_issues(emit)
    local entries = build_issue_entries(current_issues, current_limit)
    for _, entry in ipairs(entries) do
      emit(entry)
    end
    emit(nil)
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_issue_json_cmd then
      return
    end
    maybe_prefetch_list(
      forge_mod,
      'issue',
      next_state,
      f.labels.issue,
      f:list_issue_json_cmd(next_state, fetch_limit, ref),
      scope_suffix
    )
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_issues(emit)
    if current_issues and not issues_stale then
      emit_cached_issues(emit)
      return
    end
    log.info('fetching issue list (' .. state .. ')...')
    picker_session.request_json(
      cache_key,
      f:list_issue_json_cmd(state, current_limit + 1, ref),
      function(ok, issues, _, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error('failed to fetch issues')
          emit(placeholder_entry('Failed to fetch issues'))
          emit(nil)
          return
        end
        current_issues = issues
        issues_stale = false
        if use_cache then
          forge_mod.set_list(cache_key, issues)
        end
        emit_cached_issues(emit)
        maybe_prefetch_next()
      end
    )
  end

  local function rerender_issue_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.issue(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function refresh_issue_list()
    issues_stale = true
    rerender_issue_list()
  end

  local function issue_cache_key(list_state)
    return scoped_list_key(forge_mod, 'issue', list_state, scope_suffix)
  end

  local function observed_open_issue_state(rows)
    if type(rows) ~= 'table' then
      return nil
    end
    for _, issue in ipairs(rows) do
      local value = issue[issue_state_field]
      if type(value) == 'string' then
        local text = vim.trim(value)
        local lower = text:lower()
        if lower == 'open' or lower == 'opened' then
          return text
        end
      end
    end
    return nil
  end

  local function next_issue_state(current_issue, verb)
    local current_state = current_issue[issue_state_field]
    local current_text = type(current_state) == 'string' and vim.trim(current_state) or ''
    if verb == 'close' then
      if current_text ~= '' and current_text == current_text:upper() then
        return 'CLOSED'
      end
      return 'closed'
    end
    local open_state = observed_open_issue_state(state == 'open' and current_issues or nil)
      or observed_open_issue_state(state == 'all' and current_issues or nil)
      or observed_open_issue_state(forge_mod.get_list(issue_cache_key('open')))
      or observed_open_issue_state(forge_mod.get_list(issue_cache_key('all')))
    if open_state then
      return open_state
    end
    if current_text ~= '' and current_text == current_text:upper() then
      return 'OPEN'
    end
    return 'open'
  end

  local function patch_issue_cache(list_state, mutate)
    local key = issue_cache_key(list_state)
    local issues = forge_mod.get_list(key)
    if type(issues) ~= 'table' then
      return
    end
    mutate(issues)
    forge_mod.set_list(key, issues)
  end

  local function revalidate_current_issues()
    picker_session.request_json(
      cache_key,
      f:list_issue_json_cmd(state, current_limit + 1, ref),
      function(ok, issues, _, stale)
        if stale then
          return
        end
        if not ok then
          log.error('failed to fetch issues')
          return
        end
        current_issues = issues
        issues_stale = false
        if use_cache then
          forge_mod.set_list(cache_key, issues)
        end
        rerender_issue_list()
        maybe_prefetch_next()
      end
    )
  end

  local function locally_toggle_issue(entry, verb)
    local current_index, current_issue = list_row(current_issues, num_field, entry.value.num)
    if not current_index or type(current_issue) ~= 'table' then
      refresh_issue_list()
      return
    end
    local updated_issue = vim.deepcopy(current_issue)
    updated_issue[issue_state_field] = next_issue_state(current_issue, verb)

    if state == 'all' then
      current_issues[current_index] = updated_issue
    else
      table.remove(current_issues, current_index)
    end
    if use_cache then
      forge_mod.set_list(cache_key, current_issues)
    end

    if verb == 'close' then
      if state ~= 'closed' then
        patch_issue_cache('closed', function(issues)
          upsert_list_row(issues, num_field, entry.value.num, vim.deepcopy(updated_issue))
        end)
      end
      if state ~= 'open' then
        patch_issue_cache('open', function(issues)
          remove_list_row(issues, num_field, entry.value.num)
        end)
      end
    else
      if state ~= 'open' then
        patch_issue_cache('open', function(issues)
          upsert_list_row(issues, num_field, entry.value.num, vim.deepcopy(updated_issue))
        end)
      end
      if state ~= 'closed' then
        patch_issue_cache('closed', function(issues)
          remove_list_row(issues, num_field, entry.value.num)
        end)
      end
    end
    if state ~= 'all' then
      patch_issue_cache('all', function(issues)
        upsert_list_row(issues, num_field, entry.value.num, vim.deepcopy(updated_issue))
      end)
    end

    rerender_issue_list()
    revalidate_current_issues()
  end

  local actions = {
    {
      name = 'default',
      label = 'open',
      close = false,
      fn = function(entry)
        if entry and entry.load_more then
          current_limit = entry.next_limit
          issues_stale = true
        elseif entry then
          issue_action_fns(f, entry.value).browse()
        end
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          issue_action_fns(f, entry.value).browse()
        end
      end,
    },
    {
      name = 'edit',
      label = 'edit',
      fn = function(entry)
        if entry and not entry.load_more then
          issue_action_fns(f, entry.value).edit()
        end
      end,
    },
    {
      name = 'toggle',
      available = issue_toggle_entry,
      label = function(entry)
        if entry == nil then
          return 'close/reopen'
        end
        return picker.issue_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local verb = picker.issue_toggle_verb(entry)
        local callbacks = {
          on_success = function()
            locally_toggle_issue(entry, verb)
          end,
          on_failure = refresh_issue_list,
        }
        if verb == 'close' then
          ops.issue_close(f, entry.value, callbacks)
        elseif verb == 'reopen' then
          ops.issue_reopen(f, entry.value, callbacks)
        end
      end,
    },
    {
      name = 'create',
      label = 'create',
      fn = function()
        ops.issue_create({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      fn = function()
        M.issue(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        clear_state_caches(forge_mod, 'issue', scope_suffix)
        refresh_issue_list()
      end,
    },
  }

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  if cached then
    current_issues = cached
    issues_stale = false
  end

  local initial_prompt
  if current_issues then
    local _, count = build_issue_entries(current_issues, current_limit)
    initial_prompt = ('%s %s (%d)> '):format(state_label, f.labels.issue, count)
  else
    initial_prompt = ('%s %s> '):format(state_label, f.labels.issue)
  end

  picker_handle = picker.pick({
    prompt = initial_prompt,
    entries = {},
    actions = actions,
    header_order = issue_header_order,
    picker_name = 'issue',
    back = opts.back,
    stream = stream_issues,
  })

  if current_issues then
    maybe_prefetch_next()
  end
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
  local cache_key = forge_mod.list_key('release', scoped_id('list', scoped_key(forge_mod, ref)))
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
    local cached = forge_mod.get_list(cache_key)
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
      filtered = vim.tbl_filter(function(r)
        return r[rel_fields.is_draft] == true
      end, releases)
    elseif state == 'prerelease' and rel_fields.is_prerelease then
      filtered = vim.tbl_filter(function(r)
        return r[rel_fields.is_prerelease] == true
      end, releases)
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
    log.info('fetching releases...')
    local requested = current_limit + 1
    picker_session.request_json(
      cache_key,
      f:list_releases_json_cmd(ref, requested),
      function(ok, releases, _, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error('failed to fetch releases')
          emit(placeholder_entry('Failed to fetch releases'))
          emit(nil)
          return
        end
        current_releases = remember_release_fetch(releases, requested)
        releases_stale = false
        forge_mod.set_list(cache_key, current_releases)
        emit_cached_releases(emit)
      end
    )
  end

  local function reopen_list()
    clear_list_cache(forge_mod, cache_key)
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
          on_success = reopen_list,
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
        clear_list_cache(forge_mod, cache_key)
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
