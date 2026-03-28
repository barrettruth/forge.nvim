local M = {}

---@type { base: string?, mode: 'unified'|'split' }
M.state = { base = nil, mode = 'unified' }

local review_augroup = vim.api.nvim_create_augroup('ForgeReview', { clear = true })

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
  M.state.base = nil
  M.state.mode = 'unified'
  vim.api.nvim_clear_autocmds({ group = review_augroup })
end

function M.toggle()
  if not M.state.base then
    return
  end
  if M.state.mode == 'unified' then
    local ok, commands = pcall(require, 'diffs.commands')
    if not ok then
      return
    end
    local file = commands.review_file_at_line(vim.api.nvim_get_current_buf(), vim.fn.line('.'))
    M.state.mode = 'split'
    if file then
      vim.cmd('edit ' .. vim.fn.fnameescape(file))
      pcall(vim.cmd, 'Gvdiffsplit ' .. M.state.base)
    end
  else
    local current_file = vim.fn.expand('%:.')
    close_view()
    M.state.mode = 'unified'
    local ok, commands = pcall(require, 'diffs.commands')
    if ok then
      commands.greview(M.state.base)
    end
    if current_file ~= '' then
      vim.fn.search('diff %-%-git a/' .. vim.pesc(current_file), 'cw')
    end
  end
end

---@param base string
---@param mode string?
function M.start(base, mode)
  M.state.base = base
  M.state.mode = mode or 'unified'
  vim.api.nvim_clear_autocmds({ group = review_augroup })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = review_augroup,
    pattern = 'diffs://review:*',
    callback = M.stop,
  })
end

---@param nav_cmd string
---@return function
function M.nav(nav_cmd)
  return function()
    if M.state.base and M.state.mode == 'split' then
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
    if M.state.base and M.state.mode == 'split' then
      pcall(vim.cmd, 'Gvdiffsplit ' .. M.state.base)
    end
  end
end

return M
