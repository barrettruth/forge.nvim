local M = {}

local detect = require('forge.detect')
local ops = require('forge.ops')
local surface = require('forge.surface')

---@type table<string, forge.ModifierSpec>
local modifiers = {
  state = { kind = 'value' },
  repo = { kind = 'value', target = 'repo' },
  branch = { kind = 'value', target = 'branch' },
  commit = { kind = 'value', target = 'commit' },
  target = { kind = 'value', target = 'location' },
  head = { kind = 'value', target = 'rev' },
  base = { kind = 'value', target = 'rev' },
  adapter = { kind = 'value' },
  method = { kind = 'value', values = { 'merge', 'squash', 'rebase' } },
  all = { kind = 'flag' },
  draft = { kind = 'flag' },
  fill = { kind = 'flag' },
  web = { kind = 'flag' },
  blank = { kind = 'flag' },
  template = { kind = 'value' },
}

local target_modifier_parsers = {
  repo = 'resolve_repo',
  branch = 'parse_branch',
  commit = 'parse_commit',
  target = 'parse_location',
  head = 'parse_rev',
  base = 'parse_rev',
}

---@type forge.CommandFamilyDef[]
local families = {
  {
    name = 'pr',
    surface = 'forge',
    default_verb = 'open',
    verb_order = {
      'open',
      'browse',
      'ci',
      'close',
      'reopen',
      'create',
      'edit',
      'approve',
      'merge',
      'draft',
      'ready',
      'refresh',
    },
    verbs = {
      open = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
      },
      browse = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo' },
      },
      ci = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
      },
      close = {
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
      refresh = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'review',
    surface = 'forge',
    default_verb = 'open',
    verb_order = { 'open' },
    verbs = {
      open = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head', 'adapter' },
      },
    },
  },
  {
    name = 'issue',
    surface = 'forge',
    verb_order = { 'browse', 'close', 'reopen', 'create', 'edit', 'refresh' },
    verbs = {
      browse = {
        subject = { kind = 'issue', min = 0, max = 1 },
        modifiers = { 'repo' },
      },
      close = {
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
      edit = {
        subject = { kind = 'issue', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      refresh = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'ci',
    surface = 'forge',
    default_verb = 'open',
    verb_order = { 'open', 'browse', 'refresh' },
    verbs = {
      open = {
        subject = { kind = 'run', min = 0, max = 1 },
        modifiers = { 'repo' },
      },
      browse = {
        subject = { kind = 'run', min = 0, max = 1 },
        modifiers = { 'repo' },
      },
      refresh = {
        subject = { min = 0, max = 0 },
        modifiers = { 'repo' },
      },
    },
  },
  {
    name = 'release',
    surface = 'forge',
    verb_order = { 'browse', 'delete', 'refresh' },
    verbs = {
      browse = {
        subject = { kind = 'release', min = 0, max = 1 },
        modifiers = { 'repo' },
      },
      delete = {
        subject = { kind = 'release', min = 1, max = 1 },
        modifiers = { 'repo' },
      },
      refresh = {
        subject = { min = 0, max = 0 },
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
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'branch', 'commit', 'target' },
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

---@type table<forge.CommandFamily, forge.CommandFamilyDef>
local family_index = {}

for _, family in ipairs(families) do
  family_index[family.name] = family
end

---@type table<string, string>
local subject_kind_patterns = {
  pr = '^%d+$',
  issue = '^%d+$',
}

---@type table<string, string>
local subject_kind_labels = {
  pr = 'PR number',
  issue = 'issue number',
}

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

local function token_is_modifier_like(token)
  if type(token) ~= 'string' then
    return false
  end
  return token:find('=', 1, true) ~= nil
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
  if family == 'review' then
    return missing and 'missing PR number' or 'too many arguments'
  end
  if family == 'release' then
    return missing and 'missing release tag' or 'too many arguments'
  end
  if family == 'ci' then
    return missing and 'missing run id' or 'too many arguments'
  end
  return missing and 'missing argument' or 'too many arguments'
end

local function missing_verb_error(_)
  return 'missing action'
end

local function unknown_verb_error(family, verb)
  if family == 'pr' then
    return 'unknown pr action: ' .. verb
  end
  if family == 'issue' then
    return 'unknown issue action: ' .. verb
  end
  if family == 'review' then
    return 'unknown review action: ' .. verb
  end
  if family == 'release' then
    return 'unknown release action: ' .. verb
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

---@return forge.TargetParseOpts
local function target_parse_opts()
  return require('forge.target').parse_opts()
end

---@param value forge.TargetValue|forge.HeadInput|forge.Scope|nil
---@return forge.RepoLike?
local function repo_target(value)
  return require('forge.target').repo_target(value)
end

local function default_policy(command, _)
  local policy = {}
  if not command.parsed_modifiers.repo and command.family == 'pr' and command.name == 'create' then
    policy.repo = 'collaboration'
  end
  if command.family == 'pr' and command.name == 'create' then
    if not command.parsed_modifiers.head then
      policy.head = 'current_push_context'
    end
    if not command.parsed_modifiers.base then
      policy.base = 'collaboration_default_branch'
    end
  elseif command.family == 'browse' and command.name == 'open' then
    policy.repo = 'current'
  end
  return next(policy) and policy or {}
end

local function default_targets(command, parse_opts)
  local target = require('forge.target')
  local policy = default_policy(command, parse_opts)
  local defaults = {}
  local repo = nil
  if policy.repo == 'collaboration' then
    repo = target.collaboration_repo(parse_opts)
  elseif policy.repo == 'current' then
    repo = target.current_repo(parse_opts)
  end
  if repo then
    defaults.repo = repo
  end
  if policy.rev == 'current_branch' then
    defaults.rev = target.branch_rev(target.current_branch(), repo)
  end
  if policy.head == 'current_push_context' then
    defaults.head = target.push_rev(parse_opts)
  end
  if policy.base == 'collaboration_default_branch' then
    defaults.base =
      target.default_branch_rev(defaults.repo or target.collaboration_repo(parse_opts))
  end
  return policy, defaults
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

---@param command forge.Command
---@param forge_name forge.ScopeKind
---@return forge.Scope?
local function resolve_scope_modifier(command, forge_name)
  local target = require('forge.target')
  local repo = repo_target(command.parsed_modifiers.target)
    or repo_target(command.parsed_modifiers.base)
    or repo_target(command.parsed_modifiers.head)
    or repo_target(command.parsed_modifiers.repo)
    or repo_target(command.default_targets.target)
    or repo_target(command.default_targets.rev)
    or repo_target(command.default_targets.base)
    or repo_target(command.default_targets.head)
    or repo_target(command.default_targets.repo)
  return target.resolve_scope(repo, forge_name, target_parse_opts())
end

local function resolve_repo_modifier(command, forge_name)
  local target = require('forge.target')
  local repo = repo_target(command.parsed_modifiers.repo)
    or repo_target(command.default_targets.repo)
  return target.resolve_scope(repo, forge_name, target_parse_opts())
end

local function current_pr_resolution_opts(command, f)
  local opts = {
    forge = f,
  }
  if command.parsed_modifiers.repo ~= nil then
    opts.repo = command.parsed_modifiers.repo
  end
  if command.parsed_modifiers.head ~= nil then
    opts.head = command.parsed_modifiers.head
  end
  return opts
end

local function resolve_current_pr_or_warn(command, f)
  local pr, err = require('forge').current_pr(current_pr_resolution_opts(command, f))
  if err then
    warn(err.message)
    return nil
  end
  if pr then
    return pr
  end
  warn(('no open %s found for this branch'):format((f.labels and f.labels.pr_one) or 'PR'))
  return nil
end

local function dispatch_pr(command)
  if not require_git_or_warn() then
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local num = command.subjects[1]
  if command.name == 'create' then
    local target = require('forge.target')
    local parse_opts = target_parse_opts()
    local head = command.parsed_modifiers.head or command.default_targets.head
    local base = command.parsed_modifiers.base or command.default_targets.base
    local scope = resolve_repo_modifier(command, f.name)
    ops.pr_create({
      draft = command.modifiers.draft == true,
      instant = command.modifiers.fill == true,
      web = command.modifiers.web == true,
      scope = scope,
      head_branch = head and head.rev or nil,
      head_scope = target.resolve_scope(head, f.name, parse_opts),
      base_branch = base and base.rev or nil,
      base_scope = target.resolve_scope(base, f.name, parse_opts) or scope,
    })
    return
  end
  if command.name == 'open' then
    if num then
      ops.pr_edit({ num = num, scope = resolve_repo_modifier(command, f.name) })
      return
    end
    local pr = resolve_current_pr_or_warn(command, f)
    if not pr then
      return
    end
    ops.pr_edit(pr)
    return
  end
  if command.name == 'ci' then
    local pr = num and { num = num, scope = resolve_repo_modifier(command, f.name) }
      or resolve_current_pr_or_warn(command, f)
    if not pr then
      return
    end
    ops.pr_ci(f, pr)
    return
  end
  if command.name == 'browse' then
    local scope = resolve_repo_modifier(command, f.name)
    if num then
      ops.pr_browse(f, { num = num, scope = scope })
    else
      ops.list_browse(f, 'pr', { scope = scope })
    end
    return
  end
  if command.name == 'refresh' then
    require('forge').clear_list_kind('pr')
    require('forge.logger').info('refreshed ' .. ((f.labels and f.labels.pr) or 'pr') .. ' list')
    return
  end
  local scope = resolve_repo_modifier(command, f.name)
  if command.name == 'edit' then
    ops.pr_edit({ num = num, scope = scope })
    return
  end
  if command.name == 'approve' then
    ops.pr_approve(f, { num = num, scope = scope })
    return
  end
  if command.name == 'merge' then
    ops.pr_merge(f, { num = num, scope = scope }, command.modifiers.method)
    return
  end
  if command.name == 'draft' then
    ops.pr_toggle_draft(f, { num = num, scope = scope }, false)
    return
  end
  if command.name == 'ready' then
    ops.pr_toggle_draft(f, { num = num, scope = scope }, true)
    return
  end
  if command.name == 'close' then
    ops.pr_close(f, { num = num, scope = scope })
    return
  end
  if command.name == 'reopen' then
    ops.pr_reopen(f, { num = num, scope = scope })
    return
  end
  warn(('unsupported pr action: %s'):format(command.name))
end

local function dispatch_review(command)
  if not require_git_or_warn() then
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local num = command.subjects[1]
  local opts = {
    adapter = command.modifiers.adapter ~= true and command.modifiers.adapter or nil,
  }
  if num then
    ops.pr_review(f, { num = num, scope = resolve_repo_modifier(command, f.name) }, opts)
    return
  end
  local pr = resolve_current_pr_or_warn(command, f)
  if not pr then
    return
  end
  ops.pr_review(f, pr, opts)
end

local function dispatch_issue(command)
  if not require_git_or_warn() then
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local num = command.subjects[1]
  local scope = resolve_repo_modifier(command, f.name)
  if command.name == 'create' then
    local template = command.modifiers.template
    ops.issue_create({
      web = command.modifiers.web == true,
      blank = command.modifiers.blank == true,
      template = template ~= true and template or nil,
      scope = scope,
    })
    return
  end
  if command.name == 'browse' then
    if num then
      ops.issue_browse(f, { num = num, scope = scope })
    else
      ops.list_browse(f, 'issue', { scope = scope })
    end
    return
  end
  if command.name == 'edit' then
    ops.issue_edit({ num = num, scope = scope })
    return
  end
  if command.name == 'close' then
    ops.issue_close(f, { num = num, scope = scope })
    return
  end
  if command.name == 'reopen' then
    ops.issue_reopen(f, { num = num, scope = scope })
    return
  end
  if command.name == 'refresh' then
    require('forge').clear_list_kind('issue')
    require('forge.logger').info('refreshed issue list')
    return
  end
  warn(('unsupported issue action: %s'):format(command.name))
end

local function dispatch_ci(command)
  if not require_git_or_warn() then
    return
  end
  if command.name == 'open' and command.subjects[1] == nil then
    require('forge').ci(command.parsed_modifiers.repo ~= nil and {
      repo = command.parsed_modifiers.repo,
    } or nil)
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local scope = resolve_repo_modifier(command, f.name)
  if command.name == 'open' then
    ops.ci_open(f, { id = command.subjects[1], scope = scope })
    return
  end
  if command.name == 'browse' then
    local id = command.subjects[1]
    if id then
      ops.ci_browse(f, { id = id, scope = scope })
    else
      ops.list_browse(f, 'ci', { scope = scope })
    end
    return
  end
  if command.name == 'refresh' then
    require('forge').clear_list_kind('ci')
    require('forge.logger').info('refreshed CI run list')
    return
  end
  warn(('unsupported ci action: %s'):format(command.name))
end

local function dispatch_release(command)
  if not require_git_or_warn() then
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local tag = command.subjects[1]
  local scope = resolve_repo_modifier(command, f.name)
  if command.name == 'browse' then
    if tag then
      ops.release_browse(f, { tag = tag, scope = scope })
    else
      ops.list_browse(f, 'release', { scope = scope })
    end
    return
  end
  if command.name == 'delete' then
    ops.release_delete(f, { tag = tag, scope = scope })
    return
  end
  if command.name == 'refresh' then
    require('forge').clear_list_kind('release')
    require('forge.logger').info('refreshed release list')
    return
  end
end

local function dispatch_browse(command)
  if not require_git_or_warn() then
    return
  end
  local f = require_forge_or_warn()
  if not f then
    return
  end
  local scope = resolve_scope_modifier(command, f.name)
  local subject = command.subjects[1]
  if subject then
    ops.browse_subject(f, { num = subject, scope = scope })
    return
  end
  local location = command.parsed_modifiers.target
  if location then
    ops.browse_location(f, location, scope)
    return
  end
  local commit = command.parsed_modifiers.commit
  if commit and commit.commit then
    ops.browse_commit({ commit = commit.commit, scope = scope })
    return
  end
  local branch = command.parsed_modifiers.branch
  local file_loc = require('forge').file_loc(command.range)
  if branch and branch.branch then
    if ops.browse_file(f, file_loc, branch.branch, scope) then
      return
    end
    ops.browse_branch(branch.branch, { scope = scope })
    return
  end
  local ctx = require('forge').current_context()
  local ctx_branch = type(ctx) == 'table' and ctx.branch or nil
  if ops.browse_file(f, file_loc, ctx_branch, scope) then
    return
  end
  ops.browse_repo({ scope = scope })
end

local dispatchers = {
  pr = dispatch_pr,
  review = dispatch_review,
  issue = dispatch_issue,
  ci = dispatch_ci,
  release = dispatch_release,
  browse = dispatch_browse,
  clear = function()
    require('forge').clear_cache()
    require('forge.logger').info('cache cleared')
  end,
}

---@param opts? forge.SurfaceNamesOpts
---@return string[]
function M.family_names(opts)
  opts = opts or {}
  local names = {}
  for _, family in ipairs(families) do
    names[#names + 1] = family.name
    if opts.include_aliases then
      for _, alias in ipairs(surface.family_aliases(family.name, opts.forge_name)) do
        names[#names + 1] = alias
      end
    end
  end
  return names
end

---@param name string
---@param opts? forge.SurfaceOpts
---@return string
local function resolved_family_name(name, opts)
  local resolved = surface.resolve_family(name, opts and opts.forge_name)
  if resolved then
    return resolved.canonical
  end
  return name
end

---@param family_name string
---@param opts? forge.SurfaceOpts
---@return string[]
function M.verb_names(family_name, opts)
  local family = family_index[resolved_family_name(family_name, opts)]
  if not family then
    return {}
  end
  return copy(family.verb_order or {})
end

---@param name string
---@return forge.ModifierSpec?
function M.modifier(name)
  local spec = modifiers[name]
  if not spec then
    return nil
  end
  return copy(spec)
end

---@param name string
---@param opts? forge.SurfaceOpts
---@return forge.CommandFamilyDef?
function M.family(name, opts)
  local family = family_index[resolved_family_name(name, opts)]
  if not family then
    return nil
  end
  return copy(family)
end

---@param family_name string
---@param verb_name string?
---@param opts? forge.SurfaceOpts
---@return forge.Command?
function M.resolve(family_name, verb_name, opts)
  local resolved_family = surface.resolve_family(family_name, opts and opts.forge_name)
  if not resolved_family then
    return nil
  end
  local family = family_index[resolved_family.canonical]
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
  command.invoked_family = resolved_family.invoked
  command.family_alias = resolved_family.alias
  command.name = resolved
  command.surface = family.surface
  command.implicit = implicit
  command.alias = alias
  return command
end

---@param family_name string
---@param verb_name string?
---@param opts? forge.SurfaceOpts
---@return string[]
function M.modifier_names(family_name, verb_name, opts)
  local command = M.resolve(family_name, verb_name, opts)
  if not command then
    return {}
  end
  return copy(command.modifiers or {})
end

---@param args string[]
---@param opts? forge.SurfaceOpts
---@return forge.Command?, forge.CmdError?
function M.parse(args, opts)
  opts = opts or {}
  if type(args) ~= 'table' or #args == 0 or args[1] == '' then
    return error_result('missing command')
  end

  local family_name = args[1]
  local family = M.family(family_name, opts)
  if not family then
    return error_result('unknown command: ' .. family_name)
  end

  local verb_token = args[2]
  local has_explicit_verb = verb_token ~= nil
    and (family.verbs[verb_token] ~= nil or (family.aliases and family.aliases[verb_token] ~= nil))
  local rest_index = has_explicit_verb and 3 or 2
  local implicit_command = not has_explicit_verb
      and family.default_verb
      and M.resolve(family_name, nil, opts)
    or nil

  if implicit_command and verb_token ~= nil and not token_is_modifier_like(verb_token) then
    local subject = implicit_command.subject or {}
    local kind = subject.kind
    local only_default_verb = #(family.verb_order or {}) <= 1
    local looks_like_subject = only_default_verb
      or (kind ~= 'pr' and kind ~= 'issue' and kind ~= 'run')
      or (verb_token:match('^%d+$') ~= nil)
    if not looks_like_subject then
      return error_result(unknown_verb_error(family.name, verb_token))
    end
  end

  if not has_explicit_verb and not family.default_verb then
    if verb_token ~= nil then
      return error_result(unknown_verb_error(family.name, verb_token))
    end
    return error_result(missing_verb_error(family_name))
  end

  local command = M.resolve(family_name, has_explicit_verb and verb_token or nil, opts)
  if not command then
    if verb_token ~= nil then
      return error_result(unknown_verb_error(family.name, verb_token))
    end
    return error_result(missing_verb_error(family_name))
  end

  command.subjects = {}
  command.raw = copy(args)

  local declared_modifiers = command.modifiers or {}
  local allowed_modifiers = {}
  for _, name in ipairs(declared_modifiers) do
    allowed_modifiers[name] = true
  end

  command.modifiers = {}
  command.declared_modifiers = declared_modifiers

  for i = rest_index, #args do
    local token = args[i]
    local name, value
    local eq = token:find('=', 1, true)
    if eq then
      name = token:sub(1, eq - 1)
      value = token:sub(eq + 1)
    elseif allowed_modifiers[token] and modifiers[token] and modifiers[token].kind == 'flag' then
      name = token
      value = true
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

  local subject_pattern = subject.kind and subject_kind_patterns[subject.kind] or nil
  if subject_pattern then
    local subject_label = subject_kind_labels[subject.kind] or 'subject'
    for _, value in ipairs(command.subjects) do
      if not value:match(subject_pattern) then
        return error_result(('invalid %s: %s'):format(subject_label, value))
      end
    end
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

  for _, name in ipairs(command.required_modifiers or {}) do
    if command.modifiers[name] == nil then
      return error_result('missing modifier: ' .. name)
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

  command.default_policy, command.default_targets = default_targets(command, parse_opts)

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
    warn('missing command')
    return false
  end

  local command, err = M.parse(split_words(opts.args), {
    forge_name = detect.forge_name(),
  })
  if not command then
    if err and err.message then
      warn(err.message)
    end
    return false
  end

  if (opts.range or 0) > 0 then
    command.range = {
      start_line = opts.line1,
      end_line = opts.line2,
    }
  end

  return M.dispatch(command)
end

local function completion_state(command, args)
  local state = {
    subjects = {},
    modifiers = {},
  }
  for _, token in ipairs(args) do
    local name, value
    local eq = token:find('=', 1, true)
    if eq then
      name = token:sub(1, eq - 1)
      value = token:sub(eq + 1)
    end
    if name and list_contains(command.declared_modifiers or {}, name) then
      if state.modifiers[name] == nil then
        state.modifiers[name] = value
      end
    else
      state.subjects[#state.subjects + 1] = token
    end
  end
  return state
end

local function filtered_modifier_completion_items(command, state)
  local items = {}
  local names = command.declared_modifiers or command.modifiers
  for _, name in ipairs(names or {}) do
    if state.modifiers[name] == nil then
      local spec = modifiers[name]
      if spec and spec.kind == 'flag' then
        items[#items + 1] = name
      else
        items[#items + 1] = name .. '='
      end
    end
  end
  return items
end

local function filter(candidates, arglead)
  return vim.tbl_filter(function(s)
    return s:find(arglead, 1, true) == 1
  end, candidates)
end

local function system_lines(cmd)
  if type(cmd) == 'table' then
    local result = vim.system(cmd, { text = true }):wait()
    if result.code ~= 0 then
      return {}
    end
    local output = vim.trim(result.stdout or '')
    return output == '' and {} or vim.split(output, '\n', { plain = true, trimempty = true })
  end
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return lines
end

local function add_completion_candidate(items, seen, value)
  if type(value) ~= 'string' or value == '' or seen[value] then
    return
  end
  seen[value] = true
  items[#items + 1] = value
end

local function repo_completion_values(prefix)
  local target = require('forge.target')
  local parse_opts = target_parse_opts()
  local items = {}
  local seen = {}

  local alias_names = {}
  for name in pairs(parse_opts.aliases or {}) do
    alias_names[#alias_names + 1] = name
  end
  table.sort(alias_names)
  for _, name in ipairs(alias_names) do
    add_completion_candidate(items, seen, name)
  end

  for _, remote in ipairs(system_lines({ 'git', 'remote' })) do
    add_completion_candidate(items, seen, remote)
    local resolved = target.resolve_repo(remote, parse_opts)
    if resolved then
      add_completion_candidate(items, seen, resolved.slug)
      if resolved.host and resolved.slug then
        add_completion_candidate(items, seen, resolved.host .. '/' .. resolved.slug)
      end
    end
  end

  for _, repo in ipairs({
    target.current_repo(parse_opts),
    target.push_repo(parse_opts),
    target.collaboration_repo(parse_opts),
  }) do
    if repo then
      add_completion_candidate(items, seen, repo.slug)
      if repo.host and repo.slug then
        add_completion_candidate(items, seen, repo.host .. '/' .. repo.slug)
      end
    end
  end

  return filter(items, prefix)
end

local function ref_completion_values(prefix)
  local items = {}
  local seen = {}
  for _, ref in
    ipairs(system_lines('git for-each-ref --format=%(refname:short) refs/heads refs/tags'))
  do
    add_completion_candidate(items, seen, ref)
  end
  for _, sha in
    ipairs(system_lines({ 'git', 'rev-list', '--max-count=20', '--abbrev-commit', 'HEAD' }))
  do
    add_completion_candidate(items, seen, sha)
  end
  return filter(items, prefix)
end

local function rev_address_completion_values(prefix)
  local items = {}
  local seen = {}
  local at = prefix:find('@', 1, true)
  if at then
    local repo = prefix:sub(1, at - 1)
    local rev_prefix = prefix:sub(at + 1)
    local base = repo ~= '' and (repo .. '@') or '@'
    for _, ref in ipairs(ref_completion_values(rev_prefix)) do
      add_completion_candidate(items, seen, base .. ref)
    end
    return items
  end

  for _, repo in ipairs(repo_completion_values(prefix)) do
    add_completion_candidate(items, seen, repo .. '@')
  end
  for _, ref in ipairs(ref_completion_values('')) do
    add_completion_candidate(items, seen, '@' .. ref)
  end
  return filter(items, prefix)
end

local function target_completion_values(prefix)
  if prefix:find(':', 1, true) then
    return {}
  end
  local items = {}
  local seen = {}
  local at = prefix:find('@', 1, true)
  if at then
    for _, value in ipairs(rev_address_completion_values(prefix)) do
      add_completion_candidate(items, seen, value .. ':')
    end
    return items
  end

  for _, repo in ipairs(repo_completion_values(prefix)) do
    add_completion_candidate(items, seen, repo .. '@')
  end
  for _, ref in ipairs(ref_completion_values('')) do
    add_completion_candidate(items, seen, '@' .. ref .. ':')
  end
  return filter(items, prefix)
end

local completion_limits = {
  pr = 100,
  issue = 100,
  ci = 30,
  release = 30,
}

local function json_list(cmd)
  if type(cmd) ~= 'table' then
    return nil
  end
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, result.stdout or '[]')
  if not ok or type(data) ~= 'table' then
    return nil
  end
  return data
end

local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

local function completion_scope_key(forge_mod, scope)
  if type(forge_mod.scope_key) == 'function' then
    return forge_mod.scope_key(scope)
  end
  return ''
end

local function completion_limit(forge_mod, kind)
  local cfg = type(forge_mod.config) == 'function' and forge_mod.config() or nil
  local display = type(cfg) == 'table' and cfg.display or nil
  local limits = type(display) == 'table' and display.limits or nil
  if kind == 'pr' then
    return type(limits) == 'table' and limits.pulls or completion_limits.pr
  end
  if kind == 'issue' then
    return type(limits) == 'table' and limits.issues or completion_limits.issue
  end
  if kind == 'ci' then
    return type(limits) == 'table' and limits.runs or completion_limits.ci
  end
  if kind == 'release' then
    return type(limits) == 'table' and limits.releases or completion_limits.release
  end
  return 50
end

local function completion_scope(forge_mod, f, state)
  local repo = state.modifiers.repo
  if type(repo) == 'string' and repo ~= '' then
    local target = require('forge.target')
    local resolved = target.resolve_repo(repo, target_parse_opts())
    if resolved then
      return target.repo_scope(resolved, f.name)
    end
  end
  if type(forge_mod.current_scope) == 'function' then
    return forge_mod.current_scope(f.name)
  end
  return nil
end

local function completion_forge(state)
  local ok, forge_mod = pcall(require, 'forge')
  if not ok or type(forge_mod) ~= 'table' or type(forge_mod.detect) ~= 'function' then
    return nil, nil, nil
  end
  local f = forge_mod.detect()
  if not f then
    return nil, forge_mod, nil
  end
  return f, forge_mod, completion_scope(forge_mod, f, state)
end

local function completion_list_key(forge_mod, kind, state, scope)
  return forge_mod.list_key(kind, scoped_id(state, completion_scope_key(forge_mod, scope)))
end

local function cached_completion_list(forge_mod, kind, states, scope)
  local items = {}
  local found = false
  for _, state in ipairs(states) do
    local cached = forge_mod.get_list(completion_list_key(forge_mod, kind, state, scope))
    if type(cached) == 'table' then
      found = true
      for _, item in ipairs(cached) do
        items[#items + 1] = item
      end
    end
  end
  if found then
    return items
  end
  return nil
end

local function fetch_completion_list(forge_mod, f, kind, state, scope)
  local limit = completion_limit(forge_mod, kind)
  local cmd
  if kind == 'pr' and type(f.list_pr_json_cmd) == 'function' then
    cmd = f:list_pr_json_cmd(state, limit, scope)
  elseif kind == 'issue' and type(f.list_issue_json_cmd) == 'function' then
    cmd = f:list_issue_json_cmd(state, limit, scope)
  elseif kind == 'ci' and type(f.list_runs_json_cmd) == 'function' then
    cmd = f:list_runs_json_cmd(state == 'all' and nil or state, scope, limit)
  elseif kind == 'release' and type(f.list_releases_json_cmd) == 'function' then
    cmd = f:list_releases_json_cmd(scope, limit)
  end
  local data = json_list(cmd)
  if type(data) ~= 'table' then
    return {}
  end
  if kind == 'ci' and type(f.normalize_run) == 'function' then
    local normalized = {}
    for _, item in ipairs(data) do
      normalized[#normalized + 1] = f:normalize_run(item)
    end
    data = normalized
  end
  forge_mod.set_list(completion_list_key(forge_mod, kind, state, scope), data)
  return data
end

local function completion_list(forge_mod, f, kind, states, fetch_state, scope)
  return cached_completion_list(forge_mod, kind, states, scope)
    or fetch_completion_list(forge_mod, f, kind, fetch_state or states[1], scope)
end

local function completion_entry(value)
  return { value = value }
end

local function complete_pr_subjects(command, state, prefix, policy)
  local f, forge_mod, scope = completion_forge(state)
  if not f or not forge_mod then
    return {}
  end
  local prs =
    completion_list(forge_mod, f, 'pr', policy.states_to_consult, policy.fetch_state, scope)
  local fields = f.pr_fields or {}
  local items = {}
  local seen = {}
  for _, pr in ipairs(prs or {}) do
    local num = tostring(pr[fields.number] or '')
    local entry = completion_entry({
      num = num,
      scope = scope,
      state = pr[fields.state],
      is_draft = fields.is_draft and pr[fields.is_draft] or nil,
    })
    if not policy.available or policy.available(command.name, f, entry) then
      add_completion_candidate(items, seen, num)
    end
  end
  return filter(items, prefix)
end

local function complete_issue_subjects(command, state, prefix, policy)
  local f, forge_mod, scope = completion_forge(state)
  if not f or not forge_mod then
    return {}
  end
  local issues =
    completion_list(forge_mod, f, 'issue', policy.states_to_consult, policy.fetch_state, scope)
  local fields = f.issue_fields or {}
  local items = {}
  local seen = {}
  for _, issue in ipairs(issues or {}) do
    local num = tostring(issue[fields.number] or '')
    local entry = completion_entry({
      num = num,
      scope = scope,
      state = issue[fields.state],
    })
    if not policy.available or policy.available(command.name, f, entry) then
      add_completion_candidate(items, seen, num)
    end
  end
  return filter(items, prefix)
end

local function complete_run_subjects(state, prefix, policy)
  local f, forge_mod, scope = completion_forge(state)
  if not f or not forge_mod then
    return {}
  end
  local runs =
    completion_list(forge_mod, f, 'ci', policy.states_to_consult, policy.fetch_state, scope)
  local items = {}
  local seen = {}
  for _, run in ipairs(runs or {}) do
    add_completion_candidate(items, seen, tostring(run.id or ''))
  end
  return filter(items, prefix)
end

local function complete_release_subjects(state, prefix, policy)
  local f, forge_mod, scope = completion_forge(state)
  if not f or not forge_mod then
    return {}
  end
  local releases =
    completion_list(forge_mod, f, 'release', policy.states_to_consult, policy.fetch_state, scope)
  local fields = f.release_fields or {}
  local items = {}
  local seen = {}
  for _, release in ipairs(releases or {}) do
    add_completion_candidate(items, seen, tostring(release[fields.tag] or ''))
  end
  return filter(items, prefix)
end

---@param opts? forge.SurfaceOpts
local function completion_values(family_name, verb_name, flag_name, prefix, opts)
  local command = M.resolve(family_name, verb_name, opts)
  if not command then
    return nil
  end
  local spec = modifiers[flag_name]
  local policy = require('forge.completion_policy').modifier_value(command, flag_name, spec)
  if not policy then
    return nil
  end
  if policy.source == 'repo' then
    return repo_completion_values(prefix or '')
  end
  if policy.source == 'ref' then
    return ref_completion_values(prefix or '')
  end
  if policy.source == 'rev_address' then
    return rev_address_completion_values(prefix or '')
  end
  if policy.source == 'target' then
    return target_completion_values(prefix or '')
  end
  if policy.source == 'template' then
    return filter(require('forge').template_slugs(), prefix or '')
  end
  if policy.source == 'adapter' then
    return filter(require('forge').review_adapter_names(), prefix or '')
  end
  if policy.source == 'command_values' then
    return filter(command.modifier_values[flag_name], prefix or '')
  end
  if policy.source == 'modifier_values' then
    return filter(spec.values, prefix or '')
  end
  return nil
end

local function subject_completion_items(command, state, arglead)
  local subject = command.subject or { min = 0, max = 0 }
  local max = subject.max or subject.min or 0
  if max ~= nil and #state.subjects >= max then
    return {}
  end
  if subject.kind == 'branch' then
    return ref_completion_values(arglead)
  end
  if subject.kind == 'rev' then
    return ref_completion_values(arglead)
  end
  if subject.kind == 'sha' then
    return filter(
      system_lines({ 'git', 'rev-list', '--max-count=20', '--abbrev-commit', 'HEAD' }),
      arglead
    )
  end
  local policy = require('forge.completion_policy').subject(command)
  if policy.cmdline_usefulness == 'suppress' then
    return {}
  end
  if not policy.allow_empty_prefix and arglead == '' then
    return {}
  end
  if policy.subject_kind == 'pr_number' then
    return complete_pr_subjects(command, state, arglead, policy)
  end
  if policy.subject_kind == 'issue_number' then
    return complete_issue_subjects(command, state, arglead, policy)
  end
  if policy.subject_kind == 'ci_run_id' then
    return complete_run_subjects(state, arglead, policy)
  end
  if policy.subject_kind == 'release_tag' then
    return complete_release_subjects(state, arglead, policy)
  end
  return {}
end

function M.complete(arglead, cmdline, _)
  local words = split_words(cmdline)
  local arg_idx = arglead == '' and #words or #words - 1
  local family_name = words[2]
  local surface_opts = {
    forge_name = detect.forge_name(),
  }
  local family = M.family(family_name, surface_opts)
  local explicit_verb = family
      and words[3] ~= nil
      and (family.verbs[words[3]] ~= nil or (family.aliases and family.aliases[words[3]] ~= nil))
      and words[3]
    or nil

  local flag, value_prefix = arglead:match('^([%w%-_]+)=(.*)$')
  if flag then
    local values = completion_values(family_name, explicit_verb, flag, value_prefix, surface_opts)
    if values then
      return vim.tbl_map(function(v)
        return flag .. '=' .. v
      end, values)
    end
  end
  if arg_idx == 1 then
    return filter(
      M.family_names({
        include_aliases = true,
        forge_name = surface_opts.forge_name,
      }),
      arglead
    )
  end
  if not family then
    return {}
  end
  if arg_idx == 2 then
    local command = M.resolve(family_name, nil, surface_opts)
    local state = command and completion_state(command, {}) or { modifiers = {}, subjects = {} }
    local slot_policy = require('forge.completion_policy').family_slot(command)
    local candidates = {}
    if slot_policy.include_verbs then
      for _, verb in ipairs(M.verb_names(family_name, surface_opts)) do
        candidates[#candidates + 1] = verb
      end
    end
    if command then
      if slot_policy.include_modifiers then
        vim.list_extend(candidates, filtered_modifier_completion_items(command, state))
      end
      if slot_policy.include_subjects then
        vim.list_extend(candidates, subject_completion_items(command, state, arglead))
      end
    end
    return filter(candidates, arglead)
  end
  local command = M.resolve(family_name, explicit_verb, surface_opts)
  if not command then
    return {}
  end
  command.declared_modifiers = command.modifiers or {}
  local rest_index = explicit_verb and 4 or 3
  local consumed = {}
  for i = rest_index, arglead == '' and #words or (#words - 1) do
    consumed[#consumed + 1] = words[i]
  end
  local state = completion_state(command, consumed)
  local slot_policy = require('forge.completion_policy').argument_slot(command, state)
  local candidates = {}
  if slot_policy.include_modifiers then
    vim.list_extend(candidates, filtered_modifier_completion_items(command, state))
  end
  if slot_policy.include_subjects then
    vim.list_extend(candidates, subject_completion_items(command, state, arglead))
  end
  return filter(candidates, arglead)
end

return M
