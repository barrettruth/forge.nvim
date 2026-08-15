local log = require('forge.log')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- @return boolean
function M.available()
  if not vim.g.loaded_fugitive then
    pcall(vim.cmd.packadd, 'vim-fugitive')
  end
  return vim.g.loaded_fugitive ~= nil
end

function M.show()
  local u = view.current()
  if not u or u.collection ~= 'prs' or not u.number then
    log.warn('no pull request here to show the commits of')
    return
  end
  if not M.available() then
    log.err('vim-fugitive is not available')
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  --- @type forge.BufVar
  local refs = vim.b[buf].forge or {}
  if not refs.base then
    log.err('this pull request did not say what it merges into')
    return
  end

  local dir = vcs.dir()
  local git_dir = vcs.git_dir(dir)
  if not git_dir then
    log.err('no git repository here to fetch the commits into')
    return
  end
  vim.b[buf].git_dir = git_dir

  local from = vim.api.nvim_get_current_win()
  local url = ('https://github.com/%s/%s'):format(u.owner, u.repo)
  vcs.fetch_pull(dir, url, u.number, refs.base, function(base, head)
    if vim.api.nvim_win_is_valid(from) then
      vim.api.nvim_set_current_win(from)
    end
    vim.cmd(('Git log --oneline --no-decorate --reverse %s..%s'):format(base, head))
  end)
end

return M
