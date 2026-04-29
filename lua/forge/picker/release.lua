local config_mod = require('forge.config')
local format_mod = require('forge.format')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_entity = require('forge.picker.entity')
local picker_shared = require('forge.picker.shared')
local repo_mod = require('forge.repo')
local state_mod = require('forge.state')

local M = {}

local release_header_order = {
  'browse',
  'yank',
  'delete',
  'filter',
  'refresh',
}

local set_clipboard = picker_shared.set_clipboard
local scoped_forge_ref = picker_shared.scoped_forge_ref
local scoped_key = picker_shared.scoped_key
local scoped_id = picker_shared.scoped_id
local clear_list_cache = picker_shared.clear_list_cache
local refresh_picker = picker_shared.refresh_picker
local limit_settings = picker_shared.limit_settings
local remove_list_row = picker_shared.remove_list_row

---@param state 'all'|'draft'|'prerelease'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.pick(state, f, opts)
  opts = opts or {}
  local limits = limit_settings(config_mod.config().display.limits.releases, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local ref = scoped_forge_ref(f, opts.scope)
  local cache_key = state_mod.list_key('release', scoped_id('list', scoped_key(ref)))
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

  local function rerender_release_list()
    if refresh_picker(picker_handle) then
      return
    end
    M.pick(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local release_entries = {
    limit_step = limit_step,
    cache_key = cache_key,
    fetch_log = 'fetching releases...',
    failure_log = 'failed to fetch releases',
    failure_entry = 'Failed to fetch releases',
    get_limit = function()
      return current_limit
    end,
    get_rows = function()
      return current_releases
    end,
    set_rows = function(releases)
      current_releases = releases
    end,
    is_stale = function()
      return releases_stale
    end,
    set_stale = function(stale)
      releases_stale = stale
    end,
    request_cmd = function(requested_limit)
      return f:list_releases_json_cmd(ref, requested_limit)
    end,
    transform_rows = remember_release_fetch,
    store_rows = function(releases)
      state_mod.set_list(cache_key, releases)
    end,
    after_revalidate = function()
      rerender_release_list()
    end,
    empty_text = function()
      return state == 'all' and 'No releases'
        or state == 'draft' and 'No draft releases'
        or 'No prerelease releases'
    end,
    display_rows = function(releases)
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
      return filtered
    end,
    has_more = function(releases, _, limit)
      return #releases > limit
    end,
    format_rows = function(releases, width)
      return format_mod.format_releases(releases, rel_fields, { width = width })
    end,
    value = function(rel)
      local tag = tostring(rel[rel_fields.tag] or '')
      return { tag = tag, rel = rel, scope = ref }
    end,
    ordinal = function(rel)
      local tag = tostring(rel[rel_fields.tag] or '')
      return tag .. ' ' .. (rel[rel_fields.title] or '')
    end,
  }

  local function build_release_entries(releases, limit)
    return picker_entity.build_entries(release_entries, releases, limit)
  end

  ---@param emit fun(entry: forge.PickerEntry?)
  local function stream_releases(emit)
    picker_entity.stream(release_entries)(emit)
  end

  local function revalidate_current_releases()
    picker_entity.revalidate(release_entries)
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
          local base = repo_mod.remote_web_url(entry.value.scope)
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
        M.pick(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
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
        M.pick(state, f, { limit = current_limit, back = opts.back, scope = ref })
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

return M
