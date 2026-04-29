local availability = require('forge.surface.availability')
local config_mod = require('forge.config')
local format_mod = require('forge.format')
local ops = require('forge.action.ops')
local picker = require('forge.picker')
local picker_entity = require('forge.picker.entity')
local picker_shared = require('forge.picker.shared')
local pr_mod = require('forge.pr')
local state_mod = require('forge.state')
local surface_policy = require('forge.surface.policy')

local M = {}

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

local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_list_key = picker_shared.scoped_list_key
local clear_state_caches = picker_shared.clear_state_caches
local clear_list_cache = picker_shared.clear_list_cache
local refresh_picker = picker_shared.refresh_picker
local limit_settings = picker_shared.limit_settings
local maybe_prefetch_list = picker_shared.maybe_prefetch_list
local list_row = picker_shared.list_row
local remove_list_row = picker_shared.remove_list_row
local upsert_list_row = picker_shared.upsert_list_row
local list_states = picker_shared.list_states
local pr_action_fns = picker_shared.pr_action_fns
local entity_row = picker_shared.entity_row
local load_more_row = picker_shared.load_more_row
local pr_toggle_entry = picker_shared.pr_toggle_entry
local picker_row_kind = picker_shared.picker_row_kind
local pr_toggle_draft_action = picker_shared.pr_toggle_draft_action

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.pick(state, f, opts)
  opts = opts or {}
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local cfg = config_mod.config()
  local limits = limit_settings(cfg.display.limits.pulls, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local use_cache = limits.use_cache
  local ref = scoped_forge_ref(f, opts.scope)
  local scope_suffix = scoped_key(ref)
  local cache_key = scoped_list_key('pr', state, scope_suffix)
  local pr_fields = f.pr_fields
  local num_field = pr_fields.number
  local pr_state_field = pr_fields.state
  local show_state = state ~= 'open'
  local current_limit = visible_limit
  local current_prs
  local prs_stale = true
  local picker_handle
  local pr_entries

  local function build_pr_entries(prs, limit)
    return picker_entity.build_entries(pr_entries, prs, limit)
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_pr_json_cmd then
      return
    end
    maybe_prefetch_list(
      'pr',
      next_state,
      f.labels.pr,
      f:list_pr_json_cmd(next_state, fetch_limit, ref),
      scope_suffix
    )
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_prs(emit)
    picker_entity.stream(pr_entries)(emit)
  end

  local function rerender_pr_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.pick(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function refresh_pr_list()
    prs_stale = true
    rerender_pr_list()
  end

  local function reopen_list()
    clear_state_caches('pr', scope_suffix)
    state_mod.clear_pr_state(nil, ref)
    refresh_pr_list()
  end

  pr_entries = {
    limit_step = limit_step,
    cache_key = cache_key,
    fetch_log = ('fetching %s list (%s)...'):format(f.labels.pr, state),
    failure_log = 'failed to fetch ' .. f.labels.pr,
    failure_entry = 'Failed to fetch ' .. f.labels.pr,
    get_limit = function()
      return current_limit
    end,
    get_rows = function()
      return current_prs
    end,
    set_rows = function(prs)
      current_prs = prs
    end,
    is_stale = function()
      return prs_stale
    end,
    set_stale = function(stale)
      prs_stale = stale
    end,
    request_cmd = function(requested_limit)
      return f:list_pr_json_cmd(state, requested_limit, ref)
    end,
    store_rows = function(prs)
      if use_cache then
        state_mod.set_list(cache_key, prs)
      end
    end,
    after_stream = maybe_prefetch_next,
    after_revalidate = function()
      rerender_pr_list()
      maybe_prefetch_next()
    end,
    empty_text = function()
      return state == 'all' and ('No %s'):format(f.labels.pr)
        or ('No %s %s'):format(state, f.labels.pr)
    end,
    display_rows = function(prs)
      local rows = vim.list_slice(prs, 1, #prs)
      table.sort(rows, function(a, b)
        return (a[num_field] or 0) > (b[num_field] or 0)
      end)
      return rows
    end,
    format_rows = function(prs, width)
      return format_mod.format_prs(prs, pr_fields, show_state, { width = width })
    end,
    value = function(pr)
      local num = tostring(pr[pr_fields.number] or '')
      local draft_field = rawget(pr_fields, 'is_draft')
      return {
        num = num,
        scope = ref,
        state = pr[pr_fields.state],
        is_draft = draft_field and pr[draft_field] or nil,
      }
    end,
    ordinal = function(pr)
      local num = tostring(pr[pr_fields.number] or '')
      return (pr[pr_fields.title] or '') .. ' #' .. num
    end,
  }

  local function pr_cache_key(list_state)
    return scoped_list_key('pr', list_state, scope_suffix)
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

  local function observed_merged_pr_state(rows)
    if type(rows) ~= 'table' then
      return nil
    end
    for _, pr in ipairs(rows) do
      local value = pr[pr_state_field]
      if type(value) == 'string' then
        local text = vim.trim(value)
        if text:lower() == 'merged' then
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
      or observed_open_pr_state(state_mod.get_list(pr_cache_key('open')))
      or observed_open_pr_state(state_mod.get_list(pr_cache_key('all')))
    if open_state then
      return open_state
    end
    if current_text ~= '' and current_text == current_text:upper() then
      return 'OPEN'
    end
    return 'open'
  end

  local function merged_pr_state(current_pr)
    local merged_state = observed_merged_pr_state(state == 'all' and current_prs or nil)
      or observed_merged_pr_state(state_mod.get_list(pr_cache_key('all')))
    if merged_state then
      return merged_state
    end
    local current_state = current_pr[pr_state_field]
    local current_text = type(current_state) == 'string' and vim.trim(current_state) or ''
    if current_text ~= '' and current_text == current_text:upper() then
      return 'MERGED'
    end
    return 'merged'
  end

  local function patch_pr_cache(list_state, mutate)
    local key = pr_cache_key(list_state)
    local prs = state_mod.get_list(key)
    if type(prs) ~= 'table' then
      return
    end
    mutate(prs)
    state_mod.set_list(key, prs)
  end

  local function revalidate_current_prs()
    picker_entity.revalidate(pr_entries)
  end

  ---@param entry forge.PickerEntry
  local function locally_approve_pr(entry)
    local scope = entry.value.scope or ref
    ---@type forge.PRState
    local current_pr_state = vim.tbl_extend('force', {
      state = entry.value.state or 'OPEN',
      mergeable = 'UNKNOWN',
      review_decision = '',
      is_draft = entry.value.is_draft == true,
    }, vim.deepcopy(state_mod.pr_state(f, entry.value.num, scope) or {}))
    current_pr_state.review_decision = 'APPROVED'
    state_mod.set_pr_state(entry.value.num, current_pr_state, scope)
    rerender_pr_list()
    revalidate_current_prs()
  end

  ---@param entry forge.PickerEntry
  local function locally_merge_pr(entry)
    local current_index, current_pr = list_row(current_prs, num_field, entry.value.num)
    if not current_index or type(current_pr) ~= 'table' then
      refresh_pr_list()
      return
    end
    local scope = entry.value.scope or ref
    if state == 'all' then
      local updated_pr = vim.deepcopy(current_pr)
      updated_pr[pr_state_field] = merged_pr_state(current_pr)
      current_prs[current_index] = updated_pr
    else
      table.remove(current_prs, current_index)
    end
    if use_cache then
      state_mod.set_list(cache_key, current_prs)
    end

    ---@type forge.PRState
    local current_pr_state = vim.tbl_extend('force', {
      state = entry.value.state or 'OPEN',
      mergeable = 'UNKNOWN',
      review_decision = '',
      is_draft = entry.value.is_draft == true,
    }, vim.deepcopy(state_mod.pr_state(f, entry.value.num, scope) or {}))
    current_pr_state.state = merged_pr_state(current_pr)
    current_pr_state.is_draft = false
    state_mod.set_pr_state(entry.value.num, current_pr_state, scope)

    for _, list_state in ipairs(list_states) do
      if list_state ~= state then
        clear_list_cache(pr_cache_key(list_state))
      end
    end

    rerender_pr_list()
    revalidate_current_prs()
  end

  ---@param entry forge.PickerEntry
  local function locally_toggle_pr_draft(entry)
    local scope = entry.value.scope or ref
    ---@type forge.PRState
    local current_pr_state = vim.tbl_extend('force', {
      state = entry.value.state or 'OPEN',
      mergeable = 'UNKNOWN',
      review_decision = '',
      is_draft = entry.value.is_draft == true,
    }, vim.deepcopy(state_mod.pr_state(f, entry.value.num, scope) or {}))
    current_pr_state.is_draft = not current_pr_state.is_draft
    state_mod.set_pr_state(entry.value.num, current_pr_state, scope)
    rerender_pr_list()
    revalidate_current_prs()
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
      state_mod.set_list(cache_key, current_prs)
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
    M.pick(state, f, { limit = current_limit, back = opts.back, scope = ref })
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
            on_success = function()
              locally_approve_pr(entry)
            end,
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
            on_success = function()
              locally_merge_pr(entry)
            end,
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
        pr_mod.create_pr({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'toggle',
      available = pr_toggle_entry,
      label = function(entry)
        if entry == nil then
          return 'close/reopen'
        end
        return surface_policy.pr_toggle_verb(entry)
      end,
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        local verb = surface_policy.pr_toggle_verb(entry)
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
            on_success = function()
              locally_toggle_pr_draft(entry)
            end,
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
        M.pick(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      reload = false,
      available = pr_refresh_visible,
      fn = function()
        clear_state_caches('pr', scope_suffix)
        state_mod.clear_pr_state(nil, ref)
        refresh_pr_list()
      end,
    },
  }

  local cached = use_cache and state_mod.get_list(cache_key) or nil
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

return M
