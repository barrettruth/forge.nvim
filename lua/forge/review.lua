local M = {}

---@type { base: string?, mode: 'unified'|'split' }
M.state = { base = nil, mode = 'unified' }

local log = require('forge.logger')
local review_augroup = vim.api.nvim_create_augroup('ForgeReview', { clear = true })
local active_session = nil
local current_file = nil

local function repo_root()
  return vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
end

local function base_ref()
  if active_session and active_session.subject then
    return active_session.subject.base_ref
  end
  return M.state.base
end

local function open_unified(base, root)
  local ok, commands = pcall(require, 'diffs.commands')
  if ok then
    commands.greview(base, { repo_root = root })
  end
end

local function review_root()
  if active_session and active_session.worktree_path then
    return active_session.worktree_path
  end
  if active_session and active_session.repo_root then
    return active_session.repo_root
  end
  return repo_root()
end

local function placeholder_entry(text)
  return {
    display = { { text, 'ForgeDim' } },
    value = nil,
    ordinal = text,
    placeholder = true,
  }
end

local function status_hl(status)
  local kind = status:sub(1, 1)
  if kind == 'A' or kind == 'C' then
    return 'DiffAdd'
  end
  if kind == 'D' then
    return 'DiffDelete'
  end
  if kind == 'R' then
    return 'DiffText'
  end
  return 'DiffChange'
end

local function file_display(item)
  local display = {
    { item.status, status_hl(item.status) },
    { ' ' .. item.path },
  }
  if item.old_path and item.old_path ~= item.path then
    display[#display + 1] = { ' ← ' .. item.old_path, 'ForgeDim' }
  end
  return display
end

local function parse_changed_files(output)
  local files = {}
  for _, line in ipairs(vim.split(output or '', '\n', { plain = true, trimempty = true })) do
    local fields = vim.split(line, '\t', { plain = true })
    if #fields >= 2 then
      local item = {
        status = fields[1],
        path = fields[#fields],
      }
      if #fields >= 3 then
        item.old_path = fields[2]
      end
      files[#files + 1] = item
    end
  end
  return files
end

local function close_view()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match('^fugitive://') or name:match('^diffs://') then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(vim.cmd, 'diffoff!')
end

function M.stop()
  active_session = nil
  current_file = nil
  M.state.base = nil
  M.state.mode = 'unified'
  vim.api.nvim_clear_autocmds({ group = review_augroup })
end

function M.current()
  return active_session
end

function M.open_file(path)
  local session = active_session
  local base = base_ref()
  if not session or not base or not path or path == '' then
    return
  end

  session.current_file = path
  current_file = path

  close_view()

  local root = review_root()
  local abs_path = root .. '/' .. path
  if vim.fn.filereadable(abs_path) == 1 then
    vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))
  else
    vim.cmd('enew')
    vim.api.nvim_buf_set_name(0, abs_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
  end

  if M.state.mode == 'split' then
    pcall(vim.cmd, 'Gvdiffsplit ' .. base)
    return
  end

  local ok, commands = pcall(require, 'diffs.commands')
  if ok then
    commands.gdiff(base, false)
  end
end

function M.open_index()
  local session = active_session
  local base = base_ref()
  if not session or not base then
    return
  end

  local picker = require('forge.picker')

  local function open_picker(files)
    session.files = files
    local entries = {}
    for _, item in ipairs(files) do
      entries[#entries + 1] = {
        display = file_display(item),
        value = item,
        ordinal = item.status .. ' ' .. item.path .. ' ' .. (item.old_path or ''),
      }
    end
    if #entries == 0 then
      entries = { placeholder_entry('No changed files') }
    end

    picker.pick({
      prompt = ('%s Review (%d)> '):format(session.subject.label, #files),
      entries = entries,
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function(entry)
            if entry then
              M.open_file(entry.value.path)
            end
          end,
        },
      },
      picker_name = '_menu',
    })
  end

  if session.files and #session.files > 0 then
    open_picker(session.files)
    return
  end

  vim.system({
    'git',
    '-C',
    review_root(),
    'diff',
    '--name-status',
    '--find-renames',
    '--find-copies',
    '--no-ext-diff',
    base,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        log.error('failed to load review files')
        return
      end
      open_picker(parse_changed_files(result.stdout or ''))
    end)
  end)
end

function M.toggle()
  local session = active_session
  local base = base_ref()
  if not base then
    return
  end
  if session and session.current_file then
    if M.state.mode == 'unified' then
      session.mode = 'split'
      M.state.mode = 'split'
    else
      session.mode = 'unified'
      M.state.mode = 'unified'
    end
    M.open_file(session.current_file)
    return
  end
  if M.state.mode == 'unified' then
    local ok, commands = pcall(require, 'diffs.commands')
    if not ok or type(commands.review_file_at_line) ~= 'function' then
      if session then
        session.mode = 'split'
      end
      M.state.mode = 'split'
      return
    end
    local file = commands.review_file_at_line(vim.api.nvim_get_current_buf(), vim.fn.line('.'))
    if session then
      session.current_file = file
      current_file = file
      session.mode = 'split'
    end
    M.state.mode = 'split'
    if file then
      M.open_file(file)
    end
  else
    local file = vim.fn.expand('%:.')
    if session and file ~= '' then
      session.current_file = file
    end
    if file ~= '' then
      current_file = file
    end
    close_view()
    if session then
      session.mode = 'unified'
    end
    M.state.mode = 'unified'
    if session and session.current_file then
      M.open_file(session.current_file)
      return
    end
    open_unified(base, session and session.repo_root or repo_root())
    local target = session and session.current_file or current_file
    if target and target ~= '' then
      vim.fn.search('diff %-%-git a/' .. vim.pesc(target), 'cw')
    end
  end
end

function M.start_session(session)
  M.stop()
  session = vim.deepcopy(session)
  session.files = session.files or {}
  session.mode = session.mode or 'unified'
  session.current_file = session.current_file or nil
  session.materialization = session.materialization or 'current'
  session.repo_root = session.repo_root or repo_root()
  active_session = session
  current_file = session.current_file
  if session.subject and session.subject.base_ref then
    M.state.base = session.subject.base_ref
  else
    M.state.base = nil
  end
  M.state.mode = session.mode
  vim.api.nvim_clear_autocmds({ group = review_augroup })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = review_augroup,
    pattern = 'diffs://review:*',
    callback = M.stop,
  })
end

---@param base string
---@param mode string?
function M.start(base, mode)
  M.start_session({
    subject = {
      kind = 'ref',
      id = base,
      label = base,
      base_ref = base,
      head_ref = vim.trim(vim.fn.system('git rev-parse --show-current')),
    },
    mode = mode or 'unified',
    files = {},
    current_file = nil,
    materialization = 'current',
    repo_root = repo_root(),
  })
end

function M.files()
  M.open_index()
end

---@param nav_cmd string
---@return function
function M.nav(nav_cmd)
  return function()
    local session = active_session
    local base = base_ref()
    if base and M.state.mode == 'split' then
      close_view()
    end
    local wrap = {
      cnext = 'cfirst',
      cprev = 'clast',
      lnext = 'lfirst',
      lprev = 'llast',
    }
    if not pcall(vim.cmd, nav_cmd) then
      if not pcall(vim.cmd, wrap[nav_cmd]) then
        return
      end
    end
    if base and M.state.mode == 'split' then
      pcall(vim.cmd, 'Gvdiffsplit ' .. base)
      if session and session.repo_root then
        local file = vim.fn.expand('%:.')
        if file ~= '' then
          session.current_file = file
          current_file = file
        end
      end
    end
  end
end

return M
