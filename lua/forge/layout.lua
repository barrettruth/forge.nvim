local M = {}

local function normalize_text(text)
  text = text or ''
  text = text:gsub('\r\n', ' ')
  return (text:gsub('[\r\n\t]', ' '))
end

local function current_window_width()
  local ok, width = pcall(vim.api.nvim_win_get_width, 0)
  if ok and type(width) == 'number' and width > 0 then
    return width
  end
  if vim.o.columns > 0 then
    return vim.o.columns
  end
  return 80
end

local function normalize_size(size, max)
  if size <= 1 then
    return math.floor(max * size)
  end
  return math.min(size, max)
end

local function fzf_picker_width()
  local ok, config = pcall(require, 'fzf-lua.config')
  if not ok or type(config.globals) ~= 'table' then
    return nil
  end
  local winopts = config.globals.winopts
  if type(winopts) ~= 'table' then
    return nil
  end
  if winopts.fullscreen then
    return vim.o.columns
  end
  if winopts.split then
    return current_window_width()
  end
  local width = tonumber(winopts.width)
  if not width then
    return nil
  end
  local max_width = vim.o.columns > 0 and vim.o.columns or current_window_width()
  local ok_border, border_mod = pcall(require, 'fzf-lua.win.border')
  local border_width = 0
  if ok_border and type(border_mod.nvim) == 'function' then
    local _, _, resolved =
      border_mod.nvim(winopts.border, { type = 'nvim', name = 'fzf', nwin = 1 }, true)
    if type(resolved) == 'number' then
      border_width = resolved
    end
  end
  return math.max(1, normalize_size(width, max_width) - border_width)
end

function M.picker_width()
  local ok, picker = pcall(require, 'forge.picker')
  local backend = ok and type(picker.backend) == 'function' and picker.backend() or nil
  if backend == 'fzf-lua' then
    return fzf_picker_width() or current_window_width()
  end
  return current_window_width()
end

function M.display_width(text)
  return vim.fn.strdisplaywidth(normalize_text(text))
end

function M.max_width(values)
  local width = 0
  for _, value in ipairs(values or {}) do
    width = math.max(width, M.display_width(value))
  end
  return width
end

local function quantile_index(count, quantile)
  if count <= 1 then
    return count
  end
  return math.max(1, math.min(count, math.floor((count - 1) * quantile) + 1))
end

function M.measure(values, opts)
  opts = opts or {}
  local widths = {}
  for _, value in ipairs(values or {}) do
    widths[#widths + 1] = M.display_width(value)
  end
  if #widths == 0 then
    return { typical = 0, max = 0, exact = 0 }
  end
  table.sort(widths)
  local typical = widths[quantile_index(#widths, opts.typical_quantile or 0.75)] or 0
  local max = widths[quantile_index(#widths, opts.max_quantile or 0.9)] or typical
  local exact = widths[#widths] or max
  if #widths <= 4 or exact - max <= (opts.slack or 2) then
    max = exact
  end
  if max < typical then
    max = typical
  end
  return {
    typical = typical,
    max = max,
    exact = exact,
  }
end

function M.elastic(preferred, stats, min)
  min = min or 0
  local useful = stats and stats.typical or 0
  if useful <= 0 then
    return 0, 0
  end
  local target = preferred and math.min(preferred, useful) or useful
  target = math.max(min, target)
  return target, math.max(target, stats.max or useful)
end

local function tail_truncate(text, width)
  if width <= 0 then
    return ''
  end
  if M.display_width(text) <= width then
    return text
  end
  if width == 1 then
    return '…'
  end
  local budget = width - 1
  local chars = vim.fn.strchars(text)
  local parts = {}
  local used = 0
  for i = 0, chars - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    local ch_width = M.display_width(ch)
    if used + ch_width > budget then
      break
    end
    parts[#parts + 1] = ch
    used = used + ch_width
  end
  return table.concat(parts) .. '…'
end

local function head_truncate(text, width)
  if width <= 0 then
    return ''
  end
  if M.display_width(text) <= width then
    return text
  end
  if width == 1 then
    return '…'
  end
  local budget = width - 1
  local chars = vim.fn.strchars(text)
  local tail = {}
  local used = 0
  for i = chars - 1, 0, -1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    local ch_width = M.display_width(ch)
    if used + ch_width > budget then
      break
    end
    tail[#tail + 1] = ch
    used = used + ch_width
  end
  local parts = {}
  for i = #tail, 1, -1 do
    parts[#parts + 1] = tail[i]
  end
  return '…' .. table.concat(parts)
end

function M.fit(text, width, opts)
  opts = opts or {}
  text = normalize_text(text)
  if width <= 0 then
    return ''
  end
  if M.display_width(text) > width then
    if opts.overflow == 'head' then
      text = head_truncate(text, width)
    else
      text = tail_truncate(text, width)
    end
  end
  if opts.pad == false then
    return text
  end
  return text .. string.rep(' ', math.max(0, width - M.display_width(text)))
end

local function active_columns(columns)
  local active = {}
  for _, column in ipairs(columns) do
    if column.visible ~= false and column.width > 0 then
      active[#active + 1] = column
    end
  end
  return active
end

local function total_width(columns)
  local total = 0
  local first = true
  for _, column in ipairs(active_columns(columns)) do
    if not first then
      total = total + M.display_width(column.gap or ' ')
    end
    total = total + column.width
    first = false
  end
  return total
end

local function ordered(columns, key, predicate)
  local items = {}
  for _, column in ipairs(columns) do
    if predicate(column) then
      items[#items + 1] = column
    end
  end
  table.sort(items, function(a, b)
    local av = a[key] or math.huge
    local bv = b[key] or math.huge
    if av == bv then
      return a.index < b.index
    end
    return av < bv
  end)
  return items
end

local function shrink_once(columns, allow_hard_min)
  local changed = false
  for _, column in
    ipairs(ordered(columns, 'shrink', function(col)
      local floor = allow_hard_min and (col.hard_min or 1) or col.min
      return col.visible ~= false and not col.fixed and col.width > floor
    end))
  do
    local floor = allow_hard_min and (column.hard_min or 1) or column.min
    if column.width > floor then
      column.width = column.width - 1
      changed = true
    end
  end
  return changed
end

local function grow_once(columns, budget)
  local changed = false
  for _, column in
    ipairs(ordered(columns, 'grow', function(col)
      return col.visible ~= false and not col.fixed and col.width < col.max
    end))
  do
    if total_width(columns) >= budget then
      break
    end
    if column.width < column.max then
      column.width = column.width + 1
      changed = true
    end
  end
  return changed
end

local function drop_once(columns)
  local items = ordered(columns, 'drop', function(col)
    return col.visible ~= false and col.optional and col.width > 0
  end)
  local column = items[1]
  if not column then
    return false
  end
  column.visible = false
  column.width = 0
  return true
end

function M.plan(opts)
  opts = opts or {}
  local columns = {}
  for i, input in ipairs(opts.columns or {}) do
    local column = {}
    for key, value in pairs(input) do
      column[key] = value
    end
    column.index = i
    column.gap = column.gap or ' '
    if column.fixed then
      column.min = column.fixed
      column.preferred = column.fixed
      column.max = column.fixed
    end
    column.min = math.max(0, column.min or 0)
    column.preferred = math.max(column.min, column.preferred or column.max or column.min)
    column.max = math.max(column.preferred, column.max or column.preferred)
    column.width = column.preferred
    if column.hide_if_empty and column.max <= 0 then
      column.visible = false
      column.width = 0
    end
    if column.width <= 0 and column.max <= 0 then
      column.visible = false
      column.width = 0
    end
    columns[#columns + 1] = column
  end

  local budget = math.max(1, opts.width or M.picker_width())
  local shrunk = false
  local dropped = false

  while total_width(columns) > budget do
    if shrink_once(columns, false) then
      shrunk = true
    elseif drop_once(columns) then
      dropped = true
    else
      local changed = shrink_once(columns, true)
      if changed then
        shrunk = true
      else
        break
      end
    end
  end

  while total_width(columns) < budget do
    if not grow_once(columns, budget) then
      break
    end
  end

  local by_key = {}
  local widths = {}
  for _, column in ipairs(columns) do
    by_key[column.key] = column
    widths[column.key] = column.visible ~= false and column.width or 0
  end

  return {
    width = budget,
    used = total_width(columns),
    mode = dropped and 'narrow' or shrunk and 'compact' or 'wide',
    columns = columns,
    by_key = by_key,
    widths = widths,
  }
end

function M.should_pad(plan, column)
  local pack_on = column.pack_on
  if pack_on == 'always' then
    return false
  end
  if pack_on == true or pack_on == 'compact' then
    return plan.mode == 'wide'
  end
  if pack_on == 'narrow' then
    return plan.mode ~= 'narrow'
  end
  return true
end

function M.render(plan, cells)
  local display = {}
  local first = true
  for _, column in ipairs(plan.columns) do
    if column.visible ~= false and column.width > 0 then
      local cell = cells[column.key]
      if type(cell) == 'function' then
        cell = cell(column.width, plan, column)
      elseif type(cell) == 'table' and type(cell.render) == 'function' then
        cell = cell.render(column.width, plan, column)
      end
      local text = ''
      local hl
      local overflow
      local pad
      if type(cell) == 'table' then
        text = cell.text or cell[1] or ''
        hl = cell.hl or cell[2]
        overflow = cell.overflow
        pad = cell.pad
      elseif type(cell) == 'string' then
        text = cell
      end
      if pad == nil then
        pad = M.should_pad(plan, column)
      end
      local prefix = first and '' or column.gap
      display[#display + 1] = {
        prefix .. M.fit(text, column.width, { overflow = overflow or column.overflow, pad = pad }),
        hl,
      }
      first = false
    end
  end
  return display
end

return M
