vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local items = info.loclist == 1 and vim.fn.getloclist(0) or vim.fn.getqflist()
    if #items == 0 then
      return
    end
    local bufname = vim.fn.bufname(items[1].bufnr)
    if not bufname:match('^diffs://') then
      return
    end
    vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
    vim.fn.matchadd('DiffDelete', [[\v-\d+]])
    vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
    vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
    vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
    vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
  end,
})

local function require_forge_or_warn()
  local forge_mod = require('forge')
  local f = forge_mod.detect()
  if not f then
    vim.notify('[forge]: no forge detected', vim.log.levels.WARN)
    return nil, forge_mod
  end
  return f, forge_mod
end

local function require_git_or_warn()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    vim.notify('[forge]: not a git repository', vim.log.levels.WARN)
    return false
  end
  return true
end

local function parse_flags(args, start)
  local flags = {}
  local positional = {}
  for i = start, #args do
    local flag = args[i]:match('^%-%-(.+)$')
    if flag then
      local fk, fv = flag:match('^(.-)=(.+)$')
      if fk then
        flags[fk] = fv
      else
        flags[flag] = true
      end
    else
      table.insert(positional, args[i])
    end
  end
  return flags, positional
end

local function dispatch(args)
  local sub = args[1]

  if sub == 'pr' then
    if not require_git_or_warn() then
      return
    end
    local f, forge_mod = require_forge_or_warn()
    if not f then
      return
    end
    local pickers = require('forge.pickers')
    if #args == 1 then
      pickers.pr('open', f)
      return
    end
    local flags, pos = parse_flags(args, 2)
    if flags.state then
      pickers.pr(flags.state, f)
      return
    end
    local action = pos[1]
    if action == 'create' then
      local cf = parse_flags(args, 3)
      local opts = {}
      if cf.draft then
        opts.draft = true
      end
      if cf.fill then
        opts.instant = true
      end
      if cf.web then
        opts.web = true
      end
      forge_mod.create_pr(opts)
      return
    end
    local num = pos[2]
    if not num then
      vim.notify('[forge]: missing argument', vim.log.levels.WARN)
      return
    end
    if action == 'checkout' then
      pickers.pr_actions(f, num)._by_name.checkout()
    elseif action == 'diff' then
      pickers.pr_actions(f, num)._by_name.diff()
    elseif action == 'worktree' then
      pickers.pr_actions(f, num)._by_name.worktree()
    elseif action == 'ci' then
      if f.capabilities.per_pr_checks then
        pickers.checks(f, num)
      else
        require('forge').log(
          ('per-%s checks unavailable on %s, showing repo CI'):format(f.labels.pr_one, f.name)
        )
        pickers.ci(f)
      end
    elseif action == 'browse' then
      f:view_web(f.kinds.pr, num)
    elseif action == 'manage' then
      pickers.pr_manage(f, num)
    else
      vim.notify('[forge]: unknown pr action: ' .. action, vim.log.levels.WARN)
    end
    return
  end

  if sub == 'issue' then
    if not require_git_or_warn() then
      return
    end
    local f = require_forge_or_warn()
    if not f then
      return
    end
    local pickers = require('forge.pickers')
    if #args == 1 then
      pickers.issue('all', f)
      return
    end
    local flags, pos = parse_flags(args, 2)
    if flags.state then
      pickers.issue(flags.state, f)
      return
    end
    local action = pos[1]
    local num = pos[2]
    if action == 'browse' then
      if not num then
        vim.notify('[forge]: missing issue number', vim.log.levels.WARN)
        return
      end
      f:view_web(f.kinds.issue, num)
    elseif action == 'close' then
      if not num then
        vim.notify('[forge]: missing issue number', vim.log.levels.WARN)
        return
      end
      pickers.issue_close(f, num)
    elseif action == 'reopen' then
      if not num then
        vim.notify('[forge]: missing issue number', vim.log.levels.WARN)
        return
      end
      pickers.issue_reopen(f, num)
    else
      vim.notify('[forge]: unknown issue action: ' .. (action or ''), vim.log.levels.WARN)
    end
    return
  end

  if sub == 'ci' then
    if not require_git_or_warn() then
      return
    end
    local f = require_forge_or_warn()
    if not f then
      return
    end
    local flags = parse_flags(args, 2)
    local branch
    if not flags.all then
      branch = vim.trim(vim.fn.system('git branch --show-current'))
      if branch == '' then
        branch = nil
      end
    end
    require('forge.pickers').ci(f, branch)
    return
  end

  if sub == 'browse' then
    if not require_git_or_warn() then
      return
    end
    local f = require_forge_or_warn()
    if not f then
      return
    end
    local flags = parse_flags(args, 2)
    if flags.root then
      f:browse_root()
    elseif flags.commit then
      local sha = vim.trim(vim.fn.system('git rev-parse HEAD'))
      f:browse_commit(sha)
    else
      local forge_mod = require('forge')
      local loc = forge_mod.file_loc()
      local branch = vim.trim(vim.fn.system('git branch --show-current'))
      if branch == '' then
        vim.notify('[forge]: detached HEAD', vim.log.levels.WARN)
        return
      end
      f:browse(loc, branch)
    end
    return
  end

  if sub == 'yank' then
    if not require_git_or_warn() then
      return
    end
    local f = require_forge_or_warn()
    if not f then
      return
    end
    local forge_mod = require('forge')
    local loc = forge_mod.file_loc()
    local flags = parse_flags(args, 2)
    if flags.commit then
      f:yank_commit(loc)
    else
      f:yank_branch(loc)
    end
    return
  end

  if sub == 'review' then
    local review = require('forge.review')
    if #args < 2 then
      vim.notify('[forge]: missing review action (end, toggle)', vim.log.levels.WARN)
      return
    end
    local action = args[2]
    if action == 'end' then
      review.stop()
    elseif action == 'toggle' then
      review.toggle()
    else
      vim.notify('[forge]: unknown review action: ' .. action, vim.log.levels.WARN)
    end
    return
  end

  if sub == 'clear' then
    require('forge').clear_cache()
    vim.notify('[forge]: cache cleared')
    return
  end

  vim.notify('[forge]: unknown command: ' .. sub, vim.log.levels.WARN)
end

local function complete(arglead, cmdline, _)
  local words = {}
  for word in cmdline:gmatch('%S+') do
    table.insert(words, word)
  end
  local arg_idx = arglead == '' and #words or #words - 1

  local subcmds = { 'pr', 'issue', 'ci', 'browse', 'yank', 'review', 'clear' }
  local sub_actions = {
    pr = { 'checkout', 'diff', 'worktree', 'ci', 'browse', 'manage', 'create', '--state=' },
    issue = { 'browse', 'close', 'reopen', '--state=' },
    ci = { '--all' },
    review = { 'end', 'toggle' },
    browse = { '--root', '--commit' },
    yank = { '--commit' },
  }
  local flag_values = {
    ['--state'] = { 'open', 'closed', 'all' },
  }
  local create_flags = { '--draft', '--fill', '--web' }

  local function filter(candidates)
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, candidates)
  end

  local flag, value_prefix = arglead:match('^(%-%-[^=]+)=(.*)$')
  if flag and flag_values[flag] then
    return vim.tbl_map(
      function(v)
        return flag .. '=' .. v
      end,
      vim.tbl_filter(function(v)
        return v:find(value_prefix, 1, true) == 1
      end, flag_values[flag])
    )
  end

  if arg_idx == 1 then
    return filter(subcmds)
  end

  local sub = words[2]

  if arg_idx == 2 then
    return filter(sub_actions[sub] or {})
  end

  if sub == 'pr' and words[3] == 'create' then
    return filter(create_flags)
  end

  return {}
end

vim.api.nvim_create_user_command('Forge', function(opts)
  local args = vim.split(vim.trim(opts.args), '%s+')
  if #args == 0 or args[1] == '' then
    require('forge.pickers').git()
    return
  end
  dispatch(args)
end, {
  nargs = '*',
  complete = complete,
  desc = 'forge.nvim',
})
