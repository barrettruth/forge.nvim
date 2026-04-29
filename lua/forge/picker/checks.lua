local log = require('forge.logger')
local picker = require('forge.picker')
local picker_session = require('forge.picker.session')
local picker_shared = require('forge.picker.shared')
local state_mod = require('forge.state')

local M = {}

local next_ci_filter = {
  all = 'fail',
  fail = 'pass',
  pass = 'pending',
  pending = 'all',
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

local picker_failure_text = picker_shared.picker_failure_text
local picker_failure_entry = picker_shared.picker_failure_entry
local with_placeholder = picker_shared.with_placeholder
local cached_rows = picker_shared.cached_rows
local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_id = picker_shared.scoped_id
local check_openable = picker_shared.check_openable

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
---@param opts? forge.PickerLimitOpts
function M.pick(f, num, filter, cached_checks, opts)
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
        M.pick(
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
        M.pick(f, num, 'fail', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      reload = false,
      fn = function()
        M.pick(f, num, 'pass', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      reload = false,
      fn = function()
        M.pick(f, num, 'pending', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      reload = false,
      fn = function()
        M.pick(f, num, 'all', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        log.debug(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
        M.pick(f, num, filter, nil, { back = opts.back, scope = ref })
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

return M
