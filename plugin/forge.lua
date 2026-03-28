local cfg = require('forge').config()

if cfg.keys ~= false then
  local k = cfg.keys

  if k.picker then
    vim.keymap.set({ 'n', 'v' }, k.picker, function()
      require('forge.pickers').git()
    end, { desc = 'forge git picker' })
  end

  if k.next_qf then
    vim.keymap.set(
      'n',
      k.next_qf,
      require('forge.review').nav('cnext'),
      { desc = 'next quickfix entry' }
    )
  end

  if k.prev_qf then
    vim.keymap.set(
      'n',
      k.prev_qf,
      require('forge.review').nav('cprev'),
      { desc = 'prev quickfix entry' }
    )
  end

  if k.next_loc then
    vim.keymap.set(
      'n',
      k.next_loc,
      require('forge.review').nav('lnext'),
      { desc = 'next loclist entry' }
    )
  end

  if k.prev_loc then
    vim.keymap.set(
      'n',
      k.prev_loc,
      require('forge.review').nav('lprev'),
      { desc = 'prev loclist entry' }
    )
  end

  if k.fugitive ~= false then
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'fugitive',
      callback = function(args)
        local forge_mod = require('forge')
        local f = forge_mod.detect()
        if not f then
          return
        end
        local fk = k.fugitive
        local buf = args.buf
        if fk.create then
          vim.keymap.set('n', fk.create, function()
            forge_mod.create_pr({ draft = false })
          end, { buffer = buf, desc = 'create PR' })
        end
        if fk.create_draft then
          vim.keymap.set('n', fk.create_draft, function()
            forge_mod.create_pr({ draft = true })
          end, { buffer = buf, desc = 'create draft PR' })
        end
        if fk.create_fill then
          vim.keymap.set('n', fk.create_fill, function()
            forge_mod.create_pr({ instant = true })
          end, { buffer = buf, desc = 'create PR (fill)' })
        end
        if fk.create_web then
          vim.keymap.set('n', fk.create_web, function()
            forge_mod.create_pr({ web = true })
          end, { buffer = buf, desc = 'create PR (web)' })
        end
      end,
    })
  end
end

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
    elseif action == 'checks' then
      pickers.checks(f, num)
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

  if sub == 'commit' then
    if not require_git_or_warn() then
      return
    end
    local forge_mod = require('forge')
    local f = forge_mod.detect()
    local pickers = require('forge.pickers')
    if #args == 1 then
      pickers.commits(f)
      return
    end
    local _, pos = parse_flags(args, 2)
    local action = pos[1]
    local sha = pos[2]
    if not sha then
      vim.notify('[forge]: missing commit sha', vim.log.levels.WARN)
      return
    end
    if action == 'checkout' then
      forge_mod.log_now('checking out ' .. sha .. '...')
      vim.system({ 'git', 'checkout', sha }, { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 then
            vim.notify(('[forge]: checked out %s (detached)'):format(sha))
          else
            vim.notify('[forge]: checkout failed', vim.log.levels.ERROR)
          end
          vim.cmd.redraw()
        end)
      end)
    elseif action == 'diff' then
      local review = require('forge.review')
      local range = sha .. '^..' .. sha
      review.start(range)
      local ok, commands = pcall(require, 'diffs.commands')
      if ok then
        commands.greview(range)
      end
      forge_mod.log_now('reviewing ' .. sha)
    elseif action == 'browse' then
      if not f then
        vim.notify('[forge]: no forge detected', vim.log.levels.WARN)
        return
      end
      f:browse_commit(sha)
    else
      vim.notify('[forge]: unknown commit action: ' .. action, vim.log.levels.WARN)
    end
    return
  end

  if sub == 'branch' then
    if not require_git_or_warn() then
      return
    end
    local forge_mod = require('forge')
    local f = forge_mod.detect()
    local pickers = require('forge.pickers')
    if #args == 1 then
      pickers.branches(f)
      return
    end
    local _, pos = parse_flags(args, 2)
    local action = pos[1]
    local name = pos[2]
    if not name then
      vim.notify('[forge]: missing branch name', vim.log.levels.WARN)
      return
    end
    if action == 'diff' then
      local review = require('forge.review')
      review.start(name)
      local ok, commands = pcall(require, 'diffs.commands')
      if ok then
        commands.greview(name)
      end
      forge_mod.log_now('reviewing ' .. name)
    elseif action == 'browse' then
      if not f then
        vim.notify('[forge]: no forge detected', vim.log.levels.WARN)
        return
      end
      f:browse_branch(name)
    else
      vim.notify('[forge]: unknown branch action: ' .. action, vim.log.levels.WARN)
    end
    return
  end

  if sub == 'worktree' then
    if not require_git_or_warn() then
      return
    end
    require('fzf-lua').git_worktrees()
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

  if sub == 'cache' then
    if #args < 2 then
      vim.notify('[forge]: missing cache action (clear)', vim.log.levels.WARN)
      return
    end
    if args[2] == 'clear' then
      require('forge').clear_cache()
      vim.notify('[forge]: cache cleared')
    else
      vim.notify('[forge]: unknown cache action: ' .. args[2], vim.log.levels.WARN)
    end
    return
  end

  vim.notify('[forge]: unknown command: ' .. sub, vim.log.levels.WARN)
end

local function complete(arglead, cmdline, _)
  local parts = vim.split(vim.trim(cmdline), '%s+')
  local subcmds =
    { 'pr', 'issue', 'ci', 'commit', 'branch', 'worktree', 'browse', 'yank', 'review', 'cache' }
  local sub_actions = {
    pr = {
      'checkout',
      'diff',
      'worktree',
      'checks',
      'browse',
      'manage',
      'create',
      '--state=open',
      '--state=closed',
      '--state=all',
    },
    issue = { 'browse', 'close', 'reopen', '--state=open', '--state=closed', '--state=all' },
    ci = { '--all' },
    commit = { 'checkout', 'diff', 'browse' },
    branch = { 'diff', 'browse' },
    review = { 'end', 'toggle' },
    cache = { 'clear' },
    browse = { '--root', '--commit' },
    yank = { '--commit' },
  }
  local create_flags = { '--draft', '--fill', '--web' }

  if #parts <= 2 then
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, subcmds)
  end
  local sub = parts[2]
  if #parts == 3 or (#parts == 4 and sub == 'pr' and parts[3] == 'create') then
    local candidates = sub_actions[sub] or {}
    if sub == 'pr' and #parts >= 3 and parts[3] == 'create' then
      candidates = create_flags
    end
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, candidates)
  end
  if sub == 'pr' and parts[3] == 'create' then
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, create_flags)
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
