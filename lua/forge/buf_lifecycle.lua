local M = {}

---@generic T: table
---@param init? T|fun(): T|nil
---@return T
local function init_data(init)
  if type(init) == 'function' then
    return init()
  end
  return vim.deepcopy(init or {})
end

---@generic T: table
---@param buf_data table<integer, T>
---@param buf integer
---@param init? T|fun(): T|nil
---@return T
function M.data_for(buf_data, buf, init)
  local data = buf_data[buf]
  if not data then
    data = init_data(init)
    buf_data[buf] = data
  end
  return data
end

---@generic T: table
---@param buf_data table<integer, T>
---@param buf integer
---@param fields table
---@param init? T|fun(): T|nil
---@return T
function M.set_data(buf_data, buf, fields, init)
  local data = M.data_for(buf_data, buf, init)
  for key, value in pairs(fields) do
    data[key] = value
  end
  return data
end

---@param buf integer
---@param kind forge.BufferKind
---@param url string?
function M.set_public_buffer_state(buf, kind, url)
  vim.b[buf].forge = {
    version = 1,
    kind = kind,
    url = type(url) == 'string' and url or '',
  }
end

---@param buf_data table<integer, table>
---@param buf integer
---@param field string?
---@param init? table|fun(): table|nil
function M.stop_proc(buf_data, buf, field, init)
  local data = M.data_for(buf_data, buf, init)
  field = field or 'proc'
  local proc = data[field]
  if proc and type(proc.kill) == 'function' then
    pcall(function()
      proc:kill()
    end)
  end
  data[field] = nil
end

---@param buf_data table<integer, table>
---@param buf integer
---@param field string?
---@param init? table|fun(): table|nil
function M.stop_procs(buf_data, buf, field, init)
  local data = M.data_for(buf_data, buf, init)
  field = field or 'procs'
  local procs = data[field]
  if not procs then
    return
  end
  for _, proc in ipairs(procs) do
    pcall(function()
      proc:kill()
    end)
  end
  data[field] = nil
end

---@param buf_data table<integer, table>
---@param buf integer
---@param stop fun(buf: integer)
---@param init? table|fun(): table|nil
---@return integer
function M.begin_request(buf_data, buf, stop, init)
  local data = M.data_for(buf_data, buf, init)
  data.request_id = (data.request_id or 0) + 1
  stop(buf)
  return data.request_id
end

---@param buf_data table<integer, table>
---@param buf integer
---@param request_id integer
---@return boolean
function M.request_current(buf_data, buf, request_id)
  local data = buf_data[buf]
  return data ~= nil and data.request_id == request_id
end

---@param name string?
---@return integer?
function M.find_buf_by_name(name)
  if not name or name == '' then
    return nil
  end
  local buf = vim.fn.bufnr(name)
  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  return nil
end

---@param split string?
---@return string
local function split_prefix(split)
  return split == 'vertical' and 'vertical' or 'botright'
end

---@class forge.PrepareBufOpts
---@field bufname string?
---@field reuse_buf integer?
---@field split string?
---@field filetype string
---@field kind forge.BufferKind
---@field url string?
---@field on_wipeout fun(buf: integer)?

---@param opts forge.PrepareBufOpts
---@return integer, boolean
function M.prepare_buf(opts)
  local buf
  local reusing = false
  if opts.reuse_buf and vim.api.nvim_buf_is_valid(opts.reuse_buf) then
    buf = opts.reuse_buf
    reusing = true
  else
    local existing = M.find_buf_by_name(opts.bufname)
    if existing then
      buf = existing
      reusing = true
      local wins = vim.fn.win_findbuf(buf)
      if #wins == 0 then
        vim.cmd('noautocmd ' .. split_prefix(opts.split) .. ' sbuffer ' .. buf)
      end
    else
      vim.cmd('noautocmd ' .. split_prefix(opts.split) .. ' new')
      buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      if opts.bufname then
        vim.api.nvim_buf_set_name(buf, opts.bufname)
      end
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        callback = function()
          if opts.on_wipeout then
            opts.on_wipeout(buf)
          end
        end,
      })
    end
  end
  ---@cast buf integer
  vim.bo[buf].filetype = opts.filetype
  M.set_public_buffer_state(buf, opts.kind, opts.url)
  return buf, reusing
end

---@param buf integer
---@param ns integer
---@param lines table[]
function M.render_simple(buf, ns, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(line)
      return line.text
    end, lines)
  )
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, line in ipairs(lines) do
    for _, hl in ipairs(line.highlights or {}) do
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, hl.col, {
        end_col = hl.end_col,
        hl_group = hl.group,
      })
    end
  end
end

---@param lines table[]?
---@param field string
---@return integer[]
function M.line_positions(lines, field)
  local positions = {}
  for lnum, line in ipairs(lines or {}) do
    if line[field] ~= nil then
      positions[#positions + 1] = lnum
    end
  end
  return positions
end

---@param lines table[]?
---@param field string
---@return any
function M.current_line_value(lines, field)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local entry = (lines or {})[line]
  return entry and entry[field] or nil
end

---@param positions integer[]?
---@param dir integer
---@param wrap boolean?
function M.jump_positions(positions, dir, wrap)
  positions = positions or {}
  if #positions == 0 then
    return
  end
  local current = vim.api.nvim_win_get_cursor(0)[1]
  if dir > 0 then
    for _, lnum in ipairs(positions) do
      if lnum > current then
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        return
      end
    end
    if wrap then
      vim.api.nvim_win_set_cursor(0, { positions[1], 0 })
    end
    return
  end
  for i = #positions, 1, -1 do
    if positions[i] < current then
      vim.api.nvim_win_set_cursor(0, { positions[i], 0 })
      return
    end
  end
  if wrap then
    vim.api.nvim_win_set_cursor(0, { positions[#positions], 0 })
  end
end

return M
