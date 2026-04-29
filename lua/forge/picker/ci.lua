local ci = require('forge.ci')
local config_mod = require('forge.config')
local format_mod = require('forge.format')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_session = require('forge.picker.session')
local picker_shared = require('forge.picker.shared')
local state_mod = require('forge.state')
local surface_policy = require('forge.surface_policy')

local M = {}

local next_ci_filter = {
  all = 'fail',
  fail = 'pass',
  pass = 'pending',
  pending = 'all',
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

local picker_failure_text = picker_shared.picker_failure_text
local picker_failure_entry = picker_shared.picker_failure_entry
local load_more_entry = picker_shared.load_more_entry
local with_placeholder = picker_shared.with_placeholder
local cached_rows = picker_shared.cached_rows
local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_id = picker_shared.scoped_id
local refresh_picker = picker_shared.refresh_picker
local limit_settings = picker_shared.limit_settings
local ci_inline_label = picker_shared.ci_inline_label
local expanded_limit = picker_shared.expanded_limit

---@param f forge.Forge
---@param branch string?
---@param filter string?
---@param opts? forge.PickerLimitOpts
function M.pick(f, branch, filter, opts)
  opts = opts or {}
  filter = filter or 'all'
  local limits = limit_settings(config_mod.config().display.limits.runs, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local ref = scoped_forge_ref(f, opts.scope)
  local request_key = state_mod.list_key('ci', scoped_id(branch or 'all', scoped_key(ref)))
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
    local filtered = format_mod.filter_runs(normalized, filter)
    if #filtered > limit then
      filtered = vim.list_slice(filtered, 1, limit)
    end
    local count = #filtered
    local rows_for = cached_rows(function(width)
      return format_mod.format_runs(filtered, { width = width })
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
    M.pick(f, branch, filter, { limit = current_limit, back = opts.back, scope = ref })
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
        M.pick(
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
        M.pick(f, branch, 'fail', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      reload = false,
      fn = function()
        M.pick(f, branch, 'pass', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      reload = false,
      fn = function()
        M.pick(f, branch, 'pending', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      reload = false,
      fn = function()
        M.pick(f, branch, 'all', { limit = current_limit, back = opts.back, scope = ref })
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
        M.pick(f, branch, filter, { limit = current_limit, back = opts.back, scope = ref })
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

return M
