local M = {}

local modifiers = {
  state = { kind = 'value' },
  repo = { kind = 'value', target = 'repo' },
  rev = { kind = 'value', target = 'rev' },
  target = { kind = 'value', target = 'location' },
  head = { kind = 'value', target = 'rev' },
  base = { kind = 'value', target = 'rev' },
  method = { kind = 'value', values = { 'merge', 'squash', 'rebase' } },
  all = { kind = 'flag' },
  draft = { kind = 'flag' },
  fill = { kind = 'flag' },
  web = { kind = 'flag' },
  blank = { kind = 'flag' },
  template = { kind = 'value' },
  root = { kind = 'flag', legacy = true },
  commit = { kind = 'flag', legacy = true },
}

local target_modifier_parsers = {
  repo = 'resolve_repo',
  rev = 'parse_rev',
  target = 'parse_location',
  head = 'parse_rev',
  base = 'parse_rev',
}

local families = {
  {
    name = 'pr',
    surface = 'forge',
    default_verb = 'list',
    aliases = { diff = 'review' },
    verb_order = {
      'list',
      'review',
      'checkout',
      'worktree',
      'browse',
      'ci',
      'manage',
      'close',
      'reopen',
      'create',
      'edit',
      'approve',
      'merge',
      'draft',
      'ready',
    },
    verbs = {
      list = {
        subject = { min = 0, max = 0 },
        modifiers = { 'state', 'repo' },
        modifier_values = { state = { 'open', 'closed', 'all' } },
      },
      review = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      checkout = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      worktree = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      browse = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      ci = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      manage = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      close = {
        bang = true,
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      reopen = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      create = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo', 'head', 'base', 'draft', 'fill', 'web' },
      },
      edit = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      approve = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      merge = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo', 'method' },
      },
      draft = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      ready = {
        subject = { kind = 'pr', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'issue',
    surface = 'forge',
    default_verb = 'list',
    verb_order = { 'list', 'browse', 'close', 'reopen', 'create' },
    verbs = {
      list = {
        subject = { min = 0, max = 0 },
        modifiers = { 'state', 'repo' },
        modifier_values = { state = { 'open', 'closed', 'all' } },
      },
      browse = {
        subject = { kind = 'issue', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      close = {
        bang = true,
        subject = { kind = 'issue', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      reopen = {
        subject = { kind = 'issue', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      create = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo', 'web', 'blank', 'template' },
      },
    },
  },
  {
    name = 'ci',
    surface = 'forge',
    default_verb = 'list',
    verb_order = { 'list', 'log', 'watch' },
    verbs = {
      list = {
        subject = { kind = 'rev', min = 0, max = 1 },
        modifiers = { 'repo', 'rev', 'target', 'all' },
      },
      log = {
        subject = { kind = 'run', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      watch = {
        subject = { kind = 'run', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'release',
    surface = 'forge',
    default_verb = 'list',
    verb_order = { 'list', 'browse', 'delete' },
    verbs = {
      list = {
        subject = { min = 0, max = 0 },
        modifiers = { 'state', 'repo' },
        modifier_values = { state = { 'all', 'draft', 'prerelease' } },
      },
      browse = {
        subject = { kind = 'release', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      delete = {
        bang = true,
        subject = { kind = 'release', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'browse',
    surface = 'forge',
    default_verb = 'open',
    verb_order = { 'open' },
    verbs = {
      open = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo', 'rev', 'target' },
        legacy_modifiers = { 'root', 'commit' },
      },
    },
  },
  {
    name = 'branches',
    surface = 'local',
    default_verb = 'list',
    verb_order = { 'list' },
    verbs = {
      list = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
    },
  },
  {
    name = 'commits',
    surface = 'local',
    default_verb = 'list',
    verb_order = { 'list' },
    verbs = {
      list = {
        subject = { kind = 'branch', min = 0, max = 1 },
        modifiers = {},
      },
    },
  },
  {
    name = 'worktrees',
    surface = 'local',
    default_verb = 'list',
    verb_order = { 'list' },
    verbs = {
      list = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
    },
  },
  {
    name = 'review',
    surface = 'local',
    verb_order = {
      'branch',
      'commit',
      'files',
      'next-file',
      'prev-file',
      'next-hunk',
      'prev-hunk',
      'toggle',
      'end',
    },
    verbs = {
      branch = {
        subject = { kind = 'branch', min = 0, max = 1 },
        modifiers = {},
      },
      commit = {
        subject = { kind = 'sha', min = 0, max = 1 },
        modifiers = {},
      },
      files = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      ['next-file'] = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      ['prev-file'] = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      ['next-hunk'] = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      ['prev-hunk'] = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      toggle = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
      ['end'] = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
    },
  },
  {
    name = 'clear',
    surface = 'local',
    default_verb = 'run',
    verb_order = { 'run' },
    verbs = {
      run = {
        subject = { min = 0, max = 0 },
        modifiers = {},
      },
    },
  },
}

local family_index = {}

for _, family in ipairs(families) do
  family_index[family.name] = family
end

local function copy(value)
  return vim.deepcopy(value)
end

local function split_words(text)
  local words = {}
  for word in (text or ''):gmatch('%S+') do
    words[#words + 1] = word
  end
  return words
end

local function list_contains(items, value)
  for _, item in ipairs(items) do
    if item == value then
      return true
    end
  end
  return false
end

local function set_contains(items, value)
  return type(items) == 'table' and list_contains(items, value)
end

local function subject_error(family, verb, missing)
  if family == 'pr' then
    if verb == 'edit' then
      return 'missing PR number'
    end
    return missing and 'missing argument' or 'too many arguments'
  end
  if family == 'issue' then
    return missing and 'missing issue number' or 'too many arguments'
  end
  if family == 'release' then
    return missing and 'missing release tag' or 'too many arguments'
  end
  if family == 'ci' then
    return missing and 'missing run id' or 'too many arguments'
  end
  if family == 'review' then
    return missing and 'missing review target' or 'too many arguments'
  end
  return missing and 'missing argument' or 'too many arguments'
end

local function missing_verb_error(family)
  if family == 'review' then
    return 'missing review action (end, toggle, files, next-file, prev-file, next-hunk, prev-hunk, branch, commit)'
  end
  return 'missing action'
end

local function unknown_verb_error(family, verb)
  if family == 'pr' then
    return 'unknown pr action: ' .. verb
  end
  if family == 'issue' then
    return 'unknown issue action: ' .. verb
  end
  if family == 'release' then
    return 'unknown release action: ' .. verb
  end
  if family == 'review' then
    return 'unknown review action: ' .. verb
  end
  return 'unknown action: ' .. verb
end

local function warn(msg)
  require('forge.logger').warn(msg)
end

local function error_result(msg, opts)
  opts = opts or {}
  return nil, {
    code = opts.code,
    message = msg,
  }
end

local function target_parse_opts()
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.config) ~= 'function' then
    return { resolve_repo = true }
  end
  local cfg = forge.config()
  local targets = type(cfg) == 'table' and cfg.targets or nil
  local aliases = type(targets) == 'table' and targets.aliases or nil
  return {
    resolve_repo = true,
    aliases = type(aliases) == 'table' and aliases or {},
  }
end

local function require_git_or_warn()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    warn('not a git repository')
    return false
  end
  return true
end

local function require_forge_or_warn()
  local forge_mod = require('forge')
  local f = forge_mod.detect()
  if not f then
    warn('no forge detected')
    return nil, forge_mod
  end
  return f, forge_mod
end

local function resolve_scope_modifier(command)
  local _ = command
  return nil
end

local function dispatch_pr(command)
  if not require_git_or_warn() then
    return
  end
  local f, forge_mod = require_forge_or_warn()
  if not f then
    return
  end
  local pickers = require('forge.pickers')
  local num = command.subjects[1]
  if command.name == 'list' then
    local state = command.modifiers.state
    if state then
      forge_mod.open('prs.' .. state)
    else
      forge_mod.open('prs')
    end
    return
  end
  if command.name == 'create' then
    forge_mod.create_pr({
      draft = command.modifiers.draft == true,
      instant = command.modifiers.fill == true,
      web = command.modifiers.web == true,
      scope = resolve_scope_modifier(command),
    })
    return
  end
  if command.name == 'edit' then
    forge_mod.edit_pr(num)
    return
  end
  if command.name == 'checkout' then
    pickers.pr_actions(f, num).checkout()
    return
  end
  if command.name == 'review' then
    pickers.pr_actions(f, num).review()
    return
  end
  if command.name == 'worktree' then
    pickers.pr_actions(f, num).worktree()
    return
  end
  if command.name == 'ci' then
    if f.capabilities.per_pr_checks then
      pickers.checks(f, num)
    else
      require('forge.logger').debug(
        ('per-%s checks unavailable on %s, showing repo CI'):format(f.labels.pr_one, f.name)
      )
      pickers.ci(f)
    end
    return
  end
  if command.name == 'browse' then
    f:view_web(f.kinds.pr, num)
    return
  end
  if command.name == 'manage' then
    pickers.pr_manage(f, num)
    return
  end
  if command.name == 'close' then
    pickers.pr_close(f, num)
    return
  end
  if command.name == 'reopen' then
    pickers.pr_reopen(f, num)
    return
  end
  warn(('unsupported pr action: %s'):format(command.name))
end

local function dispatch_issue(command)
  if not require_git_or_warn() then
    return
  end
  local f, forge_mod = require_forge_or_warn()
  if not f then
    return
  end
  local pickers = require('forge.pickers')
  local num = command.subjects[1]
  if command.name == 'list' then
    local state = command.modifiers.state
    if state then
      forge_mod.open('issues.' .. state)
    else
      forge_mod.open('issues')
    end
    return
  end
  if command.name == 'create' then
    local template = command.modifiers.template
    forge_mod.create_issue({
      web = command.modifiers.web == true,
      blank = command.modifiers.blank == true,
      template = template ~= true and template or nil,
      scope = resolve_scope_modifier(command),
    })
    return
  end
  if command.name == 'browse' then
    f:view_web(f.kinds.issue, num)
    return
  end
  if command.name == 'close' then
    pickers.issue_close(f, num)
    return
  end
  if command.name == 'reopen' then
    pickers.issue_reopen(f, num)
    return
  end
  warn(('unsupported issue action: %s'):format(command.name))
end

local function dispatch_ci(command)
  if not require_git_or_warn() then
    return
  end
  local f, forge_mod = require_forge_or_warn()
  if not f then
    return
  end
  if command.name == 'list' then
    local branch = nil
    if command.modifiers.all ~= true then
      branch = command.modifiers.rev or command.subjects[1]
      if branch == nil or branch == '' then
        branch = vim.trim(vim.fn.system('git branch --show-current'))
        if branch == '' then
          branch = nil
        end
      end
    end
    forge_mod.open(command.modifiers.all and 'ci.all' or 'ci.current_branch', { branch = branch })
    return
  end
  warn(('unsupported ci action: %s'):format(command.name))
end

local function dispatch_release(command)
  if not require_git_or_warn() then
    return
  end
  local f, forge_mod = require_forge_or_warn()
  if not f then
    return
  end
  local tag = command.subjects[1]
  if command.name == 'list' then
    local state = command.modifiers.state
    if state then
      forge_mod.open('releases.' .. state)
    else
      forge_mod.open('releases')
    end
    return
  end
  if command.name == 'browse' then
    f:browse_release(tag)
    return
  end
  if command.name == 'delete' then
    local function do_delete()
      require('forge.logger').info('deleting release ' .. tag .. '...')
      vim.system(f:delete_release_cmd(tag), { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 then
            require('forge.logger').info('deleted release ' .. tag)
          else
            require('forge.logger').error('delete failed')
          end
        end)
      end)
    end
    if command.bang then
      do_delete()
      return
    end
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = 'Delete release ' .. tag .. '? ',
    }, function(choice)
      if choice == 'Yes' then
        do_delete()
      end
    end)
    return
  end
end

local function dispatch_browse(command)
  if not require_git_or_warn() then
    return
  end
  local f, forge_mod = require_forge_or_warn()
  if not f then
    return
  end
  if command.modifiers.commit then
    forge_mod.open('browse.commit')
  elseif command.modifiers.root then
    forge_mod.open('browse.branch')
  else
    forge_mod.open('browse.contextual')
  end
end

local function dispatch_branches()
  if not require_git_or_warn() then
    return
  end
  require('forge').open('branches')
end

local function dispatch_commits(command)
  if not require_git_or_warn() then
    return
  end
  require('forge').open('commits', { branch = command.subjects[1] })
end

local function dispatch_worktrees()
  if not require_git_or_warn() then
    return
  end
  require('forge').open('worktrees')
end

local function dispatch_review(command)
  local review = require('forge.review')
  if command.name == 'end' then
    review.stop()
    return
  end
  if command.name == 'toggle' then
    review.toggle()
    return
  end
  if command.name == 'files' then
    review.files()
    return
  end
  if command.name == 'next-file' then
    review.next_file()
    return
  end
  if command.name == 'prev-file' then
    review.prev_file()
    return
  end
  if command.name == 'next-hunk' then
    review.next_hunk()
    return
  end
  if command.name == 'prev-hunk' then
    review.prev_hunk()
    return
  end
  if not require_git_or_warn() then
    return
  end
  local forge_mod = require('forge')
  local ctx, err = forge_mod.current_context()
  if not ctx then
    warn(err or 'failed to resolve review context')
    return
  end
  if command.name == 'branch' then
    review.start_branch(ctx, command.subjects[1] or ctx.branch)
    return
  end
  if command.name == 'commit' then
    review.start_commit(ctx, command.subjects[1] or ctx.head)
    return
  end
end

local dispatchers = {
  pr = dispatch_pr,
  issue = dispatch_issue,
  ci = dispatch_ci,
  release = dispatch_release,
  browse = dispatch_browse,
  branches = dispatch_branches,
  commits = dispatch_commits,
  worktrees = dispatch_worktrees,
  review = dispatch_review,
  clear = function()
    require('forge').clear_cache()
    require('forge.logger').info('cache cleared')
  end,
}

function M.family_names()
  local names = {}
  for _, family in ipairs(families) do
    names[#names + 1] = family.name
  end
  return names
end

function M.verb_names(family_name)
  local family = family_index[family_name]
  if not family then
    return {}
  end
  return copy(family.verb_order or {})
end

function M.modifier(name)
  local spec = modifiers[name]
  if not spec then
    return nil
  end
  return copy(spec)
end

function M.family(name)
  local family = family_index[name]
  if not family then
    return nil
  end
  return copy(family)
end

function M.resolve(family_name, verb_name)
  local family = family_index[family_name]
  if not family then
    return nil
  end

  local implicit = false
  local alias = nil
  local resolved = verb_name

  if resolved == nil or resolved == '' then
    resolved = family.default_verb
    implicit = resolved ~= nil
  end

  if resolved == nil then
    return nil
  end

  if family.aliases and family.aliases[resolved] then
    alias = resolved
    resolved = family.aliases[resolved]
  end

  local verb = family.verbs[resolved]
  if not verb then
    return nil
  end

  local command = copy(verb)
  command.family = family.name
  command.name = resolved
  command.surface = family.surface
  command.implicit = implicit
  command.alias = alias
  return command
end

function M.modifier_names(family_name, verb_name)
  local command = M.resolve(family_name, verb_name)
  if not command then
    return {}
  end
  return copy(command.modifiers or {})
end

function M.legacy_modifier_names(family_name, verb_name)
  local command = M.resolve(family_name, verb_name)
  if not command then
    return {}
  end
  return copy(command.legacy_modifiers or {})
end

function M.supports_bang(family_name, verb_name)
  local command = M.resolve(family_name, verb_name)
  return command ~= nil and command.bang == true
end

function M.parse(args, opts)
  opts = opts or {}
  if type(args) ~= 'table' or #args == 0 or args[1] == '' then
    return error_result('missing command')
  end

  local family_name = args[1]
  local family = family_index[family_name]
  if not family then
    return error_result('unknown command: ' .. family_name)
  end

  local verb_token = args[2]
  local has_explicit_verb = verb_token ~= nil
    and (family.verbs[verb_token] ~= nil or (family.aliases and family.aliases[verb_token] ~= nil))
  local rest_index = has_explicit_verb and 3 or 2

  if not has_explicit_verb and not family.default_verb then
    if verb_token ~= nil then
      return error_result(unknown_verb_error(family_name, verb_token))
    end
    return error_result(missing_verb_error(family_name))
  end

  local command = M.resolve(family_name, has_explicit_verb and verb_token or nil)
  if not command then
    if verb_token ~= nil then
      return error_result(unknown_verb_error(family_name, verb_token))
    end
    return error_result(missing_verb_error(family_name))
  end

  command.bang = opts.bang == true
  if command.bang and not M.supports_bang(command.family, command.name) then
    return error_result('E477: No ! allowed', { code = 'E477' })
  end

  command.subjects = {}
  command.raw = copy(args)

  local declared_modifiers = command.modifiers or {}
  local legacy_modifiers = command.legacy_modifiers or {}
  local allowed_modifiers = {}
  for _, name in ipairs(declared_modifiers) do
    allowed_modifiers[name] = true
  end
  for _, name in ipairs(legacy_modifiers) do
    allowed_modifiers[name] = true
  end

  command.modifiers = {}
  command.declared_modifiers = declared_modifiers
  command.declared_legacy_modifiers = legacy_modifiers

  for i = rest_index, #args do
    local token = args[i]
    local name, value
    if token:match('^%-%-') then
      local body = token:sub(3)
      local eq = body:find('=', 1, true)
      if eq then
        name = body:sub(1, eq - 1)
        value = body:sub(eq + 1)
      else
        name = body
        value = true
      end
    else
      local eq = token:find('=', 1, true)
      if eq then
        name = token:sub(1, eq - 1)
        value = token:sub(eq + 1)
      elseif allowed_modifiers[token] and modifiers[token] and modifiers[token].kind == 'flag' then
        name = token
        value = true
      end
    end

    if name then
      if not allowed_modifiers[name] then
        return error_result('unknown modifier: ' .. name)
      end
      if command.modifiers[name] ~= nil then
        return error_result('duplicate modifier: ' .. name)
      end
      local spec = modifiers[name]
      if spec and spec.kind == 'flag' then
        command.modifiers[name] = true
      else
        command.modifiers[name] = value
      end
    else
      command.subjects[#command.subjects + 1] = token
    end
  end

  local subject = command.subject or { min = 0, max = 0 }
  local min = subject.min or 0
  local max = subject.max or min
  if #command.subjects < min then
    return error_result(subject_error(command.family, command.name, true))
  end
  if max ~= nil and #command.subjects > max then
    return error_result(subject_error(command.family, command.name, false))
  end

  for name, value in pairs(command.modifiers) do
    local spec = modifiers[name]
    local allowed_values = spec and spec.values or nil
    local verb_values = command.modifier_values and command.modifier_values[name] or nil
    local values = verb_values or allowed_values
    if type(value) == 'string' and values and not set_contains(values, value) then
      return error_result(('invalid value for %s: %s'):format(name, value))
    end
  end

  command.parsed_modifiers = {}
  local target = require('forge.target')
  local parse_opts = target_parse_opts()
  for name, value in pairs(command.modifiers) do
    local parser_name = target_modifier_parsers[name]
    if parser_name and type(value) == 'string' then
      local parsed, err = target[parser_name](value, parse_opts)
      if not parsed then
        return error_result(err)
      end
      command.parsed_modifiers[name] = parsed
    end
  end

  return command
end

function M.dispatch(command)
  local dispatcher = dispatchers[command.family]
  if not dispatcher then
    warn('unknown command: ' .. command.family)
    return false
  end
  dispatcher(command)
  return true
end

function M.run(opts)
  opts = opts or {}
  if vim.trim(opts.args or '') == '' then
    require('forge').open()
    return true
  end

  local command, err = M.parse(split_words(opts.args), { bang = opts.bang })
  if not command then
    if err and err.code == 'E477' then
      vim.api.nvim_err_writeln(err.message)
    elseif err and err.message then
      warn(err.message)
    end
    return false
  end

  return M.dispatch(command)
end

local function modifier_completion_items(command, legacy)
  local items = {}
  local names = legacy and command.declared_legacy_modifiers or command.declared_modifiers
  for _, name in ipairs(names or {}) do
    local spec = modifiers[name]
    local prefix = legacy and '--' or ''
    if spec and spec.kind == 'flag' then
      items[#items + 1] = prefix .. name
    else
      items[#items + 1] = prefix .. name .. '='
    end
  end
  return items
end

local function filter(candidates, arglead)
  return vim.tbl_filter(function(s)
    return s:find(arglead, 1, true) == 1
  end, candidates)
end

local function completion_values(family_name, verb_name, flag_name)
  local command = M.resolve(family_name, verb_name)
  if not command then
    return nil
  end
  if flag_name == 'template' then
    return require('forge').template_slugs()
  end
  if command.modifier_values and command.modifier_values[flag_name] then
    return command.modifier_values[flag_name]
  end
  local spec = modifiers[flag_name]
  if spec and spec.values then
    return spec.values
  end
  return nil
end

function M.complete(arglead, cmdline, _)
  local words = split_words(cmdline)
  local arg_idx = arglead == '' and #words or #words - 1
  local family_name = words[2]
  local family = family_index[family_name]
  local explicit_verb = family
      and words[3] ~= nil
      and (family.verbs[words[3]] ~= nil or (family.aliases and family.aliases[words[3]] ~= nil))
      and words[3]
    or nil

  local legacy_flag, legacy_prefix = arglead:match('^(%-%-[^=]+)=(.*)$')
  if legacy_flag then
    local values = completion_values(family_name, explicit_verb, legacy_flag:sub(3))
    if values then
      return vim.tbl_map(function(v)
        return legacy_flag .. '=' .. v
      end, filter(values, legacy_prefix))
    end
  end
  local flag, value_prefix = arglead:match('^([%w%-_]+)=(.*)$')
  if flag then
    local values = completion_values(family_name, explicit_verb, flag)
    if values then
      return vim.tbl_map(function(v)
        return flag .. '=' .. v
      end, filter(values, value_prefix))
    end
  end
  if arg_idx == 1 then
    return filter(M.family_names(), arglead)
  end
  if not family then
    return {}
  end
  if arg_idx == 2 then
    local candidates = {}
    for _, verb in ipairs(M.verb_names(family_name)) do
      if verb ~= family.default_verb then
        candidates[#candidates + 1] = verb
      end
    end
    local implicit = M.resolve(family_name)
    if implicit then
      vim.list_extend(candidates, modifier_completion_items(implicit, true))
    end
    if (family_name == 'ci' or family_name == 'commits') and not arglead:match('^%-') then
      vim.list_extend(
        candidates,
        vim.fn.systemlist('git for-each-ref --format=%(refname:short) refs/heads refs/tags')
      )
    end
    return filter(candidates, arglead)
  end
  if family_name == 'review' and words[3] == 'branch' and arg_idx == 3 then
    return filter(
      vim.fn.systemlist('git for-each-ref --format=%(refname:short) refs/heads refs/tags'),
      arglead
    )
  end
  if explicit_verb then
    local command = M.resolve(family_name, explicit_verb)
    if command then
      return filter(modifier_completion_items(command, true), arglead)
    end
  end
  return {}
end

return M
