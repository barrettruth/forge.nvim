local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_entity = require('forge.picker.entity')
local picker_shared = require('forge.picker.shared')
local state_mod = require('forge.state')
local surface_policy = require('forge.surface_policy')

local M = {}

local issue_header_order = {
  'default',
  'browse',
  'edit',
  'toggle',
  'create',
  'filter',
  'refresh',
}

local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_list_key = picker_shared.scoped_list_key
local clear_state_caches = picker_shared.clear_state_caches
local refresh_picker = picker_shared.refresh_picker
local limit_settings = picker_shared.limit_settings
local maybe_prefetch_list = picker_shared.maybe_prefetch_list
local list_row = picker_shared.list_row
local remove_list_row = picker_shared.remove_list_row
local upsert_list_row = picker_shared.upsert_list_row
local issue_action_fns = picker_shared.issue_action_fns
local issue_toggle_entry = picker_shared.issue_toggle_entry

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.pick(state, f, opts)
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
  local cache_key = scoped_list_key('issue', state, scope_suffix)
  local issue_fields = f.issue_fields
  local num_field = issue_fields.number
  local issue_state_field = issue_fields.state
  local issue_show_state = state == 'all'
  local current_limit = visible_limit
  local current_issues
  local issues_stale = true
  local picker_handle
  local issue_entries

  local function build_issue_entries(issues, limit)
    return picker_entity.build_entries(issue_entries, issues, limit)
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_issue_json_cmd then
      return
    end
    maybe_prefetch_list(
      'issue',
      next_state,
      f.labels.issue,
      f:list_issue_json_cmd(next_state, fetch_limit, ref),
      scope_suffix
    )
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_issues(emit)
    picker_entity.stream(issue_entries)(emit)
  end

  local function rerender_issue_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.pick(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function refresh_issue_list()
    issues_stale = true
    rerender_issue_list()
  end

  issue_entries = {
    limit_step = limit_step,
    cache_key = cache_key,
    fetch_log = 'fetching issue list (' .. state .. ')...',
    failure_log = 'failed to fetch issues',
    failure_entry = 'Failed to fetch issues',
    get_limit = function()
      return current_limit
    end,
    get_rows = function()
      return current_issues
    end,
    set_rows = function(issues)
      current_issues = issues
    end,
    is_stale = function()
      return issues_stale
    end,
    set_stale = function(stale)
      issues_stale = stale
    end,
    request_cmd = function(requested_limit)
      return f:list_issue_json_cmd(state, requested_limit, ref)
    end,
    store_rows = function(issues)
      if use_cache then
        state_mod.set_list(cache_key, issues)
      end
    end,
    after_stream = maybe_prefetch_next,
    after_revalidate = function()
      rerender_issue_list()
      maybe_prefetch_next()
    end,
    empty_text = function()
      return state == 'all' and ('No %s'):format(f.labels.issue)
        or ('No %s %s'):format(state, f.labels.issue)
    end,
    display_rows = function(issues)
      local rows = vim.list_slice(issues, 1, #issues)
      table.sort(rows, function(a, b)
        return (a[num_field] or 0) > (b[num_field] or 0)
      end)
      return rows
    end,
    format_rows = function(issues, width)
      return forge_mod.format_issues(issues, issue_fields, issue_show_state, { width = width })
    end,
    value = function(issue)
      local n = tostring(issue[num_field] or '')
      return { num = n, scope = ref, state = issue[issue_fields.state] }
    end,
    ordinal = function(issue)
      local n = tostring(issue[num_field] or '')
      return (issue[issue_fields.title] or '') .. ' #' .. n
    end,
  }

  local function issue_cache_key(list_state)
    return scoped_list_key('issue', list_state, scope_suffix)
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
      or observed_open_issue_state(state_mod.get_list(issue_cache_key('open')))
      or observed_open_issue_state(state_mod.get_list(issue_cache_key('all')))
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
    local issues = state_mod.get_list(key)
    if type(issues) ~= 'table' then
      return
    end
    mutate(issues)
    state_mod.set_list(key, issues)
  end

  local function revalidate_current_issues()
    picker_entity.revalidate(issue_entries)
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
      state_mod.set_list(cache_key, current_issues)
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
        return surface_policy.issue_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local verb = surface_policy.issue_toggle_verb(entry)
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
        forge_mod.create_issue({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      reload = false,
      fn = function()
        M.pick(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      fn = function()
        clear_state_caches('issue', scope_suffix)
        refresh_issue_list()
      end,
    },
  }

  local cached = use_cache and state_mod.get_list(cache_key) or nil
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

return M
