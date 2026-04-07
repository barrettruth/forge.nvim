local M = {}

---@type { base: string?, mode: 'unified'|'split' }
M.state = { base = nil, mode = 'unified' }

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

local function close_view()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match('^fugitive://') or name:match('^diffs://review:') then
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

function M.toggle()
  local session = active_session
  local base = base_ref()
  if not base then
    return
  end
  if M.state.mode == 'unified' then
    local ok, commands = pcall(require, 'diffs.commands')
    if not ok then
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
      local root = session and session.repo_root or repo_root()
      local path = root ~= '' and (root .. '/' .. file) or file
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
      pcall(vim.cmd, 'Gvdiffsplit ' .. base)
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
