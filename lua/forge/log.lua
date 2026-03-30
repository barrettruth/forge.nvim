local M = {}

local ns = vim.api.nvim_create_namespace('forge_log')
local buf_data = {}

local sgr_map = {
  [2] = 'ForgeLogDim',
  [31] = 'ForgeFail',
  [32] = 'ForgePass',
  [33] = 'ForgeLogWarning',
  [34] = 'ForgeLogStep',
  [36] = 'ForgeLogSection',
  [91] = 'ForgeFail',
  [92] = 'ForgePass',
  [93] = 'ForgeLogWarning',
  [96] = 'ForgeLogSection',
}

local function strip_ansi(line)
  if line:byte(1) == 0xEF and line:byte(2) == 0xBB and line:byte(3) == 0xBF then
    line = line:sub(4)
  end
  line = line:gsub('\r', '')
  local parts = {}
  local hls = {}
  local pos = 1
  local col = 0
  local grp, grp_start
  while pos <= #line do
    local es, ee, params, code = line:find('\027%[([%d;]*)([A-Za-z])', pos)
    if not es then
      local chunk = line:sub(pos)
      parts[#parts + 1] = chunk
      col = col + #chunk
      break
    end
    if es > pos then
      local chunk = line:sub(pos, es - 1)
      parts[#parts + 1] = chunk
      col = col + #chunk
    end
    if code == 'm' then
      if grp and col > grp_start then
        hls[#hls + 1] = { col = grp_start, end_col = col, group = grp }
      end
      grp = nil
      if params ~= '' and params ~= '0' then
        for p in params:gmatch('(%d+)') do
          local n = tonumber(p)
          if n == 0 then
            grp = nil
          elseif sgr_map[n] then
            grp = sgr_map[n]
            grp_start = col
          end
        end
      end
    end
    pos = ee + 1
  end
  if grp and col > grp_start then
    hls[#hls + 1] = { col = grp_start, end_col = col, group = grp }
  end
  return table.concat(parts), hls
end

local function offset_hls(hls, n)
  for i, hl in ipairs(hls) do
    hls[i] = { col = hl.col + n, end_col = hl.end_col + n, group = hl.group }
  end
  return hls
end

local function parse_github(raw_lines)
  local lines = {}
  local headers = {}
  local errors = {}
  local cur_job, cur_step
  for _, raw in ipairs(raw_lines) do
    if raw:byte(1) == 0xEF and raw:byte(2) == 0xBB and raw:byte(3) == 0xBF then
      raw = raw:sub(4)
    end
    raw = raw:gsub('\r', '')
    local job, step, rest = raw:match('^([^\t]*)\t([^\t]*)\t(.*)$')
    if not job then
      local text, h = strip_ansi(raw)
      lines[#lines + 1] = { text = text, hls = h, fold = '0', kind = 'raw' }
      goto continue
    end
    if job ~= cur_job then
      cur_job = job
      cur_step = nil
      lines[#lines + 1] = { text = job, hls = {}, fold = '>1', kind = 'job' }
      headers[#headers + 1] = #lines
    end
    if step ~= cur_step then
      cur_step = step
      lines[#lines + 1] = { text = '  ' .. step, hls = {}, fold = '>2', kind = 'step' }
      headers[#headers + 1] = #lines
    end
    do
      local _, content = rest:match('^(%d%d%d%d%-%d%d%-%d%dT[%d:.]+Z)%s(.*)$')
      if not content then
        content = rest
      end
      local kind, m = 'content', nil
      m = content:match('^##%[error[^%]]*%](.*)$')
      if m then
        kind = 'error'
        content = m
        goto emit
      end
      m = content:match('^##%[warning[^%]]*%](.*)$')
      if m then
        kind = 'warning'
        content = m
        goto emit
      end
      m = content:match('^##%[group[^%]]*%](.*)$')
      if m then
        kind = 'group'
        content = m
        goto emit
      end
      if content:match('^##%[endgroup') then
        goto continue
      end
      m = content:match('^##%[debug[^%]]*%](.*)$')
      if m then
        kind = 'debug'
        content = m
        goto emit
      end
      m = content:match('^##%[notice[^%]]*%](.*)$')
      if m then
        kind = 'notice'
        content = m
      end
      ::emit::
      local text, h = strip_ansi(content)
      lines[#lines + 1] = {
        text = '    ' .. text,
        hls = offset_hls(h, 4),
        fold = kind == 'group' and '>3' or '2',
        kind = kind,
      }
      if kind == 'error' then
        errors[#errors + 1] = #lines
      elseif kind == 'group' then
        headers[#headers + 1] = #lines
      end
    end
    ::continue::
  end
  return { lines = lines, headers = headers, errors = errors }
end

local function parse_gitlab(raw_lines)
  local lines = {}
  local headers = {}
  local errors = {}
  local in_section = false
  for _, raw in ipairs(raw_lines) do
    raw = raw:gsub('\r', '')
    if raw:match('^section_start:') then
      local _, sep_end = raw:find('\027%[0K')
      local header_raw
      if sep_end then
        header_raw = raw:sub(sep_end + 1)
      else
        header_raw = raw:match('^section_start:%d+:(.+)$') or ''
      end
      local text, h = strip_ansi(header_raw)
      if text == '' then
        text = raw:match('^section_start:%d+:([^%c\027]+)') or 'section'
      end
      lines[#lines + 1] = { text = text, hls = h, fold = '>1', kind = 'section' }
      headers[#headers + 1] = #lines
      in_section = true
      goto continue
    end
    if raw:match('^section_end:') then
      in_section = false
      goto continue
    end
    do
      local text, h = strip_ansi(raw)
      local prefix = in_section and '  ' or ''
      if #prefix > 0 then
        offset_hls(h, #prefix)
      end
      local kind = 'content'
      for _, hl in ipairs(h) do
        if hl.group == 'ForgeFail' then
          kind = 'error'
          break
        end
      end
      lines[#lines + 1] = {
        text = prefix .. text,
        hls = h,
        fold = in_section and '1' or '0',
        kind = kind,
      }
      if kind == 'error' then
        errors[#errors + 1] = #lines
      end
    end
    ::continue::
  end
  return { lines = lines, headers = headers, errors = errors }
end

local parser_for = {
  github = parse_github,
  codeberg = parse_github,
  gitlab = parse_gitlab,
}

local function render(buf, parsed)
  local texts = {}
  local fold_exprs = {}
  for i, line in ipairs(parsed.lines) do
    texts[i] = line.text
    fold_exprs[i] = line.fold
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(parsed.lines) do
    local lnum = i - 1
    if line.kind == 'job' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogJob' })
    elseif line.kind == 'step' or line.kind == 'group' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogStep' })
    elseif line.kind == 'section' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogSection' })
    elseif line.kind == 'error' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogError' })
    elseif line.kind == 'warning' or line.kind == 'notice' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogWarning' })
    elseif line.kind == 'debug' then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = 'ForgeLogDim' })
    end
    for _, hl in ipairs(line.hls) do
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, hl.col, {
        end_col = hl.end_col,
        hl_group = hl.group,
      })
    end
  end
  buf_data[buf] = {
    fold_exprs = fold_exprs,
    headers = parsed.headers,
    errors = parsed.errors,
  }
end

local function jump(buf, kind, dir)
  local d = buf_data[buf]
  if not d then
    return
  end
  local list = kind == 'header' and d.headers or d.errors
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  if dir > 0 then
    for _, ln in ipairs(list) do
      if ln > cursor then
        vim.api.nvim_win_set_cursor(0, { ln, 0 })
        return
      end
    end
  else
    for i = #list, 1, -1 do
      if list[i] < cursor then
        vim.api.nvim_win_set_cursor(0, { list[i], 0 })
        return
      end
    end
  end
end

local function setup_keymaps(buf, url, cmd, opts)
  local cfg = require('forge').config()
  if cfg.keys == false then
    return
  end
  local keys = cfg.keys.log or {}
  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set('n', key, fn, { buffer = buf, desc = desc })
    end
  end
  map(keys.close, function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, 'Close log')
  map(keys.next_step, function()
    jump(buf, 'header', 1)
  end, 'Next step')
  map(keys.prev_step, function()
    jump(buf, 'header', -1)
  end, 'Previous step')
  map(keys.next_error, function()
    jump(buf, 'error', 1)
  end, 'Next error')
  map(keys.prev_error, function()
    jump(buf, 'error', -1)
  end, 'Previous error')
  map(keys.browse, function()
    if url then
      vim.ui.open(url)
    end
  end, 'Browse')
  map(keys.refresh, function()
    M.open(cmd, opts, buf)
  end, 'Refresh')
end

---@class forge.LogOpts
---@field forge_name string
---@field url string?
---@field title string?

---@param cmd string[]
---@param opts forge.LogOpts
---@param reuse_buf integer?
function M.open(cmd, opts, reuse_buf)
  local parse = parser_for[opts.forge_name] or parse_github
  local buf
  local saved_cursor
  if reuse_buf and vim.api.nvim_buf_is_valid(reuse_buf) then
    buf = reuse_buf
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      saved_cursor = vim.api.nvim_win_get_cursor(wins[1])
    end
  else
    vim.cmd('noautocmd botright new')
    buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = 'forge_log'
    pcall(vim.api.nvim_buf_set_name, buf, 'forge://log/' .. (opts.title or 'ci'))
    vim.wo[0].foldmethod = 'expr'
    vim.wo[0].foldexpr = 'v:lua.require("forge.log").foldexpr(v:lnum)'
    vim.wo[0].foldlevel = 99
    vim.wo[0].foldtext = ''
    setup_keymaps(buf, opts.url, cmd, opts)
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      callback = function()
        buf_data[buf] = nil
      end,
    })
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Loading...' })
  vim.bo[buf].modifiable = false
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local stdout = result.stdout or ''
      if result.code ~= 0 or stdout == '' then
        local msg = vim.trim(result.stderr or stdout)
        if msg == '' then
          msg = 'no log output'
        end
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, '\n'))
        vim.bo[buf].modifiable = false
        buf_data[buf] = { fold_exprs = {}, headers = {}, errors = {} }
        return
      end
      local raw_lines = vim.split(stdout, '\n', { plain = true })
      if raw_lines[#raw_lines] == '' then
        raw_lines[#raw_lines] = nil
      end
      local parsed = parse(raw_lines)
      render(buf, parsed)
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 then
        local win = wins[1]
        if saved_cursor then
          local lc = vim.api.nvim_buf_line_count(buf)
          saved_cursor[1] = math.min(saved_cursor[1], lc)
          vim.api.nvim_win_set_cursor(win, saved_cursor)
        else
          vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        end
      end
    end)
  end)
end

function M.foldexpr(lnum)
  local buf = vim.api.nvim_get_current_buf()
  local d = buf_data[buf]
  if not d then
    return '0'
  end
  return d.fold_exprs[lnum] or '0'
end

M._strip_ansi = strip_ansi
M._parse_github = parse_github
M._parse_gitlab = parse_gitlab

return M
