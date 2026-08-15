local log = require('forge.log')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- Found the way ci.nvim and diffs.nvim are: installed under `pack/*/opt` is
--- not loaded, so |:packadd| first or an installed fugitive reads as missing.
--- @return boolean
function M.available()
  if not vim.g.loaded_fugitive then
    pcall(vim.cmd.packadd, 'vim-fugitive')
  end
  return vim.g.loaded_fugitive ~= nil
end

--- Show this pull request's commits in fugitive.
---
--- A split, where the checks and the diff take the window: fugitive's "-" is
--- the parent tree object rather than the way back, so the pull request left
--- beside the log is the only way back there is. Both ends are fetched first,
--- sharing the fetch "dd" makes.
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
  --- @type forge.ItemVar
  local refs = vim.b[buf].forge or {}
  if not refs.base then
    log.err('this pull request did not say what it merges into')
    return
  end

  -- Fugitive refuses `-C` and otherwise reads the working directory, so
  -- `b:git_dir` is the only way to aim it: at where the refs were fetched.
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
