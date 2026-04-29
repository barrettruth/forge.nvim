local M = {}
local collections = require('forge.collections')

local detect = require('forge.detect')
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
  target = 'parse_browse_target',
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
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
      },
      reopen = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
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
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
      },
      merge = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head', 'method' },
      },
      draft = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
      },
      ready = {
        subject = { kind = 'pr', min = 0, max = 1 },
        modifiers = { 'repo', 'head' },
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
        modifiers = { 'repo', 'head' },
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

local function subject_error(family, verb, missing)
  if family == 'pr' then
    if verb == 'edit' then
      local f = detect.detect()
      return ('missing %s number'):format((f and f.labels and f.labels.pr_one) or 'PR')
    end
    return missing and 'missing argument' or 'too many arguments'
  end
  if family == 'issue' then
    return missing and 'missing issue number' or 'too many arguments'
  end
  if family == 'review' then
    if missing then
      local f = detect.detect()
      return ('missing %s number'):format((f and f.labels and f.labels.pr_one) or 'PR')
    end
    return 'too many arguments'
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
    local subject_label
    if subject.kind == 'pr' then
      local f = detect.detect()
      subject_label = ((f and f.labels and f.labels.pr_one) or 'PR') .. ' number'
    elseif subject.kind == 'issue' then
      subject_label = 'issue number'
    else
      subject_label = 'subject'
    end
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
    if type(value) == 'string' and values and not collections.set_contains(values, value) then
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
  return require('forge.cmd.dispatch').dispatch(command)
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

function M.complete(arglead, cmdline, _)
  return require('forge.cmd.complete').complete(M, arglead, cmdline, split_words)
end

return M
