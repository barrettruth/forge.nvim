local log = require('forge.logger')
local picker_session = require('forge.picker.session')
local picker_shared = require('forge.picker.shared')

local cached_rows = picker_shared.cached_rows
local expanded_limit = picker_shared.expanded_limit
local load_more_entry = picker_shared.load_more_entry
local picker_failure_entry = picker_shared.picker_failure_entry
local picker_failure_text = picker_shared.picker_failure_text
local with_placeholder = picker_shared.with_placeholder

local M = {}

local function empty_text(opts, source_rows, display_rows, limit)
  local text = opts.empty_text
  if type(text) == 'function' then
    return text(source_rows, display_rows, limit)
  end
  return text
end

local function updated_rows(opts, rows, requested_limit)
  if opts.transform_rows then
    return opts.transform_rows(rows, requested_limit)
  end
  return rows
end

local function store_rows(opts, rows)
  if opts.store_rows then
    opts.store_rows(rows)
  end
end

function M.build_entries(opts, rows, limit)
  limit = limit or opts.get_limit()
  local source_rows = rows or {}
  local display_rows = opts.display_rows and opts.display_rows(source_rows, limit) or source_rows
  local has_more
  if opts.has_more then
    has_more = opts.has_more(source_rows, display_rows, limit)
  else
    has_more = #display_rows > limit
  end
  if #display_rows > limit then
    display_rows = vim.list_slice(display_rows, 1, limit)
  end
  local rows_for = cached_rows(function(width)
    return opts.format_rows(display_rows, width)
  end)
  local displays = rows_for()
  local entries = {}
  for i, row in ipairs(display_rows) do
    entries[#entries + 1] = {
      display = displays[i],
      render_display = function(width)
        return rows_for(width)[i]
      end,
      value = opts.value(row),
      ordinal = opts.ordinal(row),
    }
  end
  local count = #entries
  if has_more then
    entries[#entries + 1] = load_more_entry(expanded_limit(limit, opts.limit_step), true)
  end
  return with_placeholder(entries, empty_text(opts, source_rows, display_rows, limit)), count
end

function M.emit_entries(entries, emit)
  for _, entry in ipairs(entries) do
    emit(entry)
  end
  emit(nil)
end

function M.emit_current(opts, emit)
  M.emit_entries(M.build_entries(opts, opts.get_rows(), opts.get_limit()), emit)
end

function M.stream(opts)
  return function(emit)
    if opts.get_rows() and not opts.is_stale() then
      M.emit_current(opts, emit)
      return
    end
    if opts.fetch_log then
      log.debug(opts.fetch_log)
    end
    local requested_limit = opts.get_limit() + 1
    picker_session.request_json(
      opts.cache_key,
      opts.request_cmd(requested_limit),
      function(ok, rows, failure, stale)
        if stale then
          emit(nil)
          return
        end
        if not ok then
          log.error(picker_failure_text(failure, opts.failure_log))
          emit(picker_failure_entry(failure, opts.failure_entry))
          emit(nil)
          return
        end
        rows = updated_rows(opts, rows, requested_limit)
        opts.set_rows(rows)
        opts.set_stale(false)
        store_rows(opts, rows)
        M.emit_current(opts, emit)
        if opts.after_stream then
          opts.after_stream(rows)
        end
      end
    )
  end
end

function M.revalidate(opts)
  local requested_limit = opts.get_limit() + 1
  picker_session.request_json(
    opts.cache_key,
    opts.request_cmd(requested_limit),
    function(ok, rows, failure, stale)
      if stale then
        return
      end
      if not ok then
        log.error(picker_failure_text(failure, opts.failure_log))
        return
      end
      rows = updated_rows(opts, rows, requested_limit)
      opts.set_rows(rows)
      opts.set_stale(false)
      store_rows(opts, rows)
      if opts.after_revalidate then
        opts.after_revalidate(rows)
      end
    end
  )
end

return M
