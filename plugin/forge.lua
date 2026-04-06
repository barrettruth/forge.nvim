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

local log = require('forge.logger')

local function require_forge_or_warn()
  local forge_mod = require('forge')
  local f = forge_mod.detect()
  if not f then
    log.warn('no forge detected')
    return nil, forge_mod
  end
  return f, forge_mod
end

local function require_git_or_warn()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    log.warn('not a git repository')
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
      forge_mod.open('prs')
      return
    end
    local flags, pos = parse_flags(args, 2)
    if flags.state then
      forge_mod.open('prs.' .. flags.state)
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
    if action == 'edit' then
      local num = pos[2]
      if not num then
        log.warn('missing PR number')
        return
      end
      forge_mod.edit_pr(num)
      return
    end
    local num = pos[2]
    if not num then
      log.warn('missing argument')
      return
    end
    if action == 'checkout' then
      pickers.pr_actions(f, num).checkout()
    elseif action == 'diff' then
      pickers.pr_actions(f, num).diff()
    elseif action == 'worktree' then
      pickers.pr_actions(f, num).worktree()
    elseif action == 'ci' then
      if f.capabilities.per_pr_checks then
        pickers.checks(f, num)
      else
        log.debug(
          ('per-%s checks unavailable on %s, showing repo CI'):format(f.labels.pr_one, f.name)
        )
        pickers.ci(f)
      end
    elseif action == 'browse' then
      f:view_web(f.kinds.pr, num)
    elseif action == 'manage' then
      pickers.pr_manage(f, num)
    elseif action == 'close' then
      pickers.pr_close(f, num)
    elseif action == 'reopen' then
      pickers.pr_reopen(f, num)
    else
      log.warn('unknown pr action: ' .. action)
    end
    return
  end

  if sub == 'issue' then
    if not require_git_or_warn() then
      return
    end
    local f, forge_mod = require_forge_or_warn()
    if not f then
      return
    end
    local pickers = require('forge.pickers')
    if #args == 1 then
      forge_mod.open('issues')
      return
    end
    local flags, pos = parse_flags(args, 2)
    if flags.state then
      forge_mod.open('issues.' .. flags.state)
      return
    end
    local action = pos[1]
    if action == 'create' then
      local cf = parse_flags(args, 3)
      local opts = {}
      if cf.web then
        opts.web = true
      end
      if cf.blank then
        opts.blank = true
      end
      if cf.template then
        opts.template = cf.template ~= true and cf.template or nil
      end
      forge_mod.create_issue(opts)
      return
    end
    local num = pos[2]
    if action == 'browse' then
      if not num then
        log.warn('missing issue number')
        return
      end
      f:view_web(f.kinds.issue, num)
    elseif action == 'close' then
      if not num then
        log.warn('missing issue number')
        return
      end
      pickers.issue_close(f, num)
    elseif action == 'reopen' then
      if not num then
        log.warn('missing issue number')
        return
      end
      pickers.issue_reopen(f, num)
    else
      log.warn('unknown issue action: ' .. (action or ''))
    end
    return
  end

  if sub == 'ci' then
    if not require_git_or_warn() then
      return
    end
    local f, forge_mod = require_forge_or_warn()
    if not f then
      return
    end
    local flags, positional = parse_flags(args, 2)
    local ref
    if not flags.all then
      ref = positional[1] or vim.trim(vim.fn.system('git branch --show-current'))
      if ref == '' then
        ref = nil
      end
    end
    forge_mod.open(flags.all and 'ci.all' or 'ci.current_branch', { branch = ref })
    return
  end

  if sub == 'release' then
    if not require_git_or_warn() then
      return
    end
    local f, forge_mod = require_forge_or_warn()
    if not f then
      return
    end
    if #args == 1 then
      forge_mod.open('releases')
      return
    end
    local _, pos = parse_flags(args, 2)
    local action = pos[1]
    local tag = pos[2]
    if action == 'browse' then
      if not tag then
        log.warn('missing release tag')
        return
      end
      f:browse_release(tag)
    elseif action == 'delete' then
      if not tag then
        log.warn('missing release tag')
        return
      end
      vim.ui.select({ 'Yes', 'No' }, {
        prompt = 'Delete release ' .. tag .. '? ',
      }, function(choice)
        if choice == 'Yes' then
          log.info('deleting release ' .. tag .. '...')
          vim.system(f:delete_release_cmd(tag), { text = true }, function(result)
            vim.schedule(function()
              if result.code == 0 then
                log.info('deleted release ' .. tag)
              else
                log.error('delete failed')
              end
            end)
          end)
        end
      end)
    else
      log.warn('unknown release action: ' .. (action or ''))
    end
    return
  end

  if sub == 'browse' then
    if not require_git_or_warn() then
      return
    end
    local f, forge_mod = require_forge_or_warn()
    if not f then
      return
    end
    local flags = parse_flags(args, 2)
    if flags.commit then
      forge_mod.open('browse.commit')
    elseif flags.root then
      forge_mod.open('browse.branch')
    else
      forge_mod.open('browse.contextual')
    end
    return
  end

  if sub == 'review' then
    local review = require('forge.review')
    if #args < 2 then
      log.warn('missing review action (end, toggle)')
      return
    end
    local action = args[2]
    if action == 'end' then
      review.stop()
    elseif action == 'toggle' then
      review.toggle()
    else
      log.warn('unknown review action: ' .. action)
    end
    return
  end

  if sub == 'clear' then
    require('forge').clear_cache()
    log.info('cache cleared')
    return
  end

  log.warn('unknown command: ' .. sub)
end

local function complete(arglead, cmdline, _)
  local words = {}
  for word in cmdline:gmatch('%S+') do
    table.insert(words, word)
  end
  local arg_idx = arglead == '' and #words or #words - 1

  local subcmds = { 'pr', 'issue', 'ci', 'release', 'browse', 'review', 'clear' }
  local sub_actions = {
    pr = {
      'checkout',
      'diff',
      'worktree',
      'ci',
      'browse',
      'manage',
      'edit',
      'create',
      'close',
      'reopen',
      '--state=',
    },
    issue = { 'browse', 'close', 'reopen', 'create', '--state=' },
    ci = { '--all' },
    release = { 'browse', 'delete' },
    review = { 'end', 'toggle' },
    browse = { '--root', '--commit' },
  }
  local flag_values = {
    ['--state'] = { 'open', 'closed', 'all' },
  }
  local create_flags = { '--draft', '--fill', '--web' }
  local issue_create_flags = { '--web', '--blank', '--template=' }

  local function filter(candidates)
    return vim.tbl_filter(function(s)
      return s:find(arglead, 1, true) == 1
    end, candidates)
  end

  local flag, value_prefix = arglead:match('^(%-%-[^=]+)=(.*)$')
  if flag then
    local values = flag_values[flag]
    if not values and flag == '--template' then
      values = require('forge').template_slugs()
    end
    if values then
      return vim.tbl_map(
        function(v)
          return flag .. '=' .. v
        end,
        vim.tbl_filter(function(v)
          return v:find(value_prefix, 1, true) == 1
        end, values)
      )
    end
  end

  if arg_idx == 1 then
    return filter(subcmds)
  end

  local sub = words[2]

  if arg_idx == 2 then
    local candidates = vim.list_extend({}, sub_actions[sub] or {})
    if sub == 'ci' and not arglead:match('^%-') then
      vim.list_extend(
        candidates,
        vim.fn.systemlist('git for-each-ref --format=%(refname:short) refs/heads refs/tags')
      )
    end
    return filter(candidates)
  end

  if sub == 'pr' and words[3] == 'create' then
    return filter(create_flags)
  end

  if sub == 'issue' and words[3] == 'create' then
    return filter(issue_create_flags)
  end

  return {}
end

vim.api.nvim_create_user_command('Forge', function(opts)
  local args = vim.split(vim.trim(opts.args), '%s+')
  if #args == 0 or args[1] == '' then
    require('forge').open()
    return
  end
  dispatch(args)
end, {
  nargs = '*',
  complete = complete,
  desc = 'forge.nvim',
})
