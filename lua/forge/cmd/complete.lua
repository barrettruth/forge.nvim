local M = {}

local collections = require('forge.collections')
local detect = require('forge.detect')
local issue_mod = require('forge.issue')
local pr_mod = require('forge.pr')
local resolve_mod = require('forge.resolve')
local review_mod = require('forge.review')
local source_mod = require('forge.cmd.complete_source')
local state_mod = require('forge.state')

---@param command forge.Command
---@param args string[]
---@return forge.CommandCompletionState
local function completion_state(command, args)
  local state = {
    subjects = {},
    modifiers = {},
  }
  for _, token in ipairs(args) do
    local name = nil
    local value = nil
    local eq = token:find('=', 1, true)
    if eq then
      name = token:sub(1, eq - 1)
      value = token:sub(eq + 1)
    end
    if name and collections.list_contains(command.declared_modifiers or {}, name) then
      if state.modifiers[name] == nil then
        state.modifiers[name] = value
      end
    else
      state.subjects[#state.subjects + 1] = token
    end
  end
  return state
end

---@param cmd_mod table
---@param command forge.Command
---@param state forge.CommandCompletionState
---@return string[]
local function filtered_modifier_completion_items(cmd_mod, command, state)
  local items = {}
  local names = command.declared_modifiers or command.modifiers
  for _, name in ipairs(names or {}) do
    if state.modifiers[name] == nil then
      local spec = cmd_mod.modifier(name)
      if spec and spec.kind == 'flag' then
        items[#items + 1] = name
      else
        items[#items + 1] = name .. '='
      end
    end
  end
  return items
end

---@param value any
---@return forge.PickerEntry
local function completion_entry(value)
  return { value = value }
end

---@param items string[]
---@param seen table<string, boolean>
---@param value string
local function add_completion_candidate(items, seen, value)
  if value == '' or seen[value] then
    return
  end
  seen[value] = true
  items[#items + 1] = value
end

---@param state forge.CommandCompletionState
---@param f forge.Forge
---@param include_head boolean?
---@return forge.CurrentPROpts?
local function completion_current_pr_opts(state, f, include_head)
  local opts = {
    forge = f,
  }
  if state.modifiers.repo ~= nil then
    local scope = source_mod.repo_scope(state.modifiers.repo, f.name)
    if not scope then
      return nil
    end
    opts.repo = scope
  end
  if include_head ~= false and state.modifiers.head ~= nil then
    local head = source_mod.head(state.modifiers.head)
    if not head then
      return nil
    end
    opts.head = head
  end
  return opts
end

---@param pr forge.PRRef
---@param state string
---@param pr_state forge.PRState?
---@return forge.PickerEntry
local function pr_completion_entry(pr, state, pr_state)
  local value = {
    num = pr.num,
    scope = pr.scope,
    state = state,
  }
  if type(pr_state) == 'table' then
    value.is_draft = pr_state.is_draft
    value.review_decision = pr_state.review_decision
    value.mergeable = pr_state.mergeable
  end
  return completion_entry(value)
end

---@param state forge.CommandCompletionState
---@return forge.PRCompletionTarget?
local function implicit_pr_completion_target(state)
  local f = detect.detect()
  if not f then
    return nil
  end
  local opts = completion_current_pr_opts(state, f)
  if not opts then
    return nil
  end
  ---@type forge.PRRef?
  local pr
  ---@type forge.CmdError?
  local err
  pr, err = pr_mod.current_pr(opts)
  if err then
    return nil
  end
  if pr then
    local pr_state = state_mod.pr_state(f, pr.num, pr.scope)
    local state_name = type(pr_state) == 'table' and pr_state.state or nil
    return {
      forge = f,
      entry = pr_completion_entry(pr, state_name or 'OPEN', pr_state),
    }
  end
  pr, err = resolve_mod.branch_pr(opts, {
    searches = { { 'closed' } },
  })
  if err then
    return nil
  end
  if pr then
    return {
      forge = f,
      entry = pr_completion_entry(pr, 'CLOSED'),
    }
  end
  pr, err = resolve_mod.branch_pr(opts, {
    searches = { { 'merged' } },
  })
  if err then
    return nil
  end
  if pr then
    return {
      forge = f,
      entry = pr_completion_entry(pr, 'MERGED'),
    }
  end
  return nil
end

---@param command forge.Command
---@param state forge.CommandCompletionState
---@return forge.PRCompletionTarget?
local function merge_method_completion_target(command, state)
  if command.family ~= 'pr' or command.name ~= 'merge' then
    return nil
  end
  local f = detect.detect()
  if not f then
    return nil
  end
  local opts = completion_current_pr_opts(state, f, false)
  if not opts then
    return nil
  end
  local num = state.subjects[1]
  if num then
    local scope = source_mod.repo_like_scope(opts.repo)
    local pr_state = state_mod.pr_state(f, num, scope)
    local state_name = type(pr_state) == 'table' and pr_state.state or nil
    return {
      forge = f,
      entry = pr_completion_entry({ num = num, scope = scope }, state_name or 'OPEN', pr_state),
    }
  end
  local pr, err = pr_mod.current_pr(opts)
  if err or not pr then
    return nil
  end
  local pr_state = state_mod.pr_state(f, pr.num, pr.scope)
  local state_name = type(pr_state) == 'table' and pr_state.state or nil
  return {
    forge = f,
    entry = pr_completion_entry(pr, state_name or 'OPEN', pr_state),
  }
end

---@param command forge.Command?
---@param state forge.CommandCompletionState
---@param values string[]
---@return string[]
local function filter_family_verb_completion_items(command, state, values)
  if not command then
    return values
  end
  local items = {}
  local target = nil
  if command.family == 'pr' and command.name == 'open' then
    target = implicit_pr_completion_target(state)
  end
  local policy = require('forge.completion_policy')
  for _, value in ipairs(values) do
    local forge = target and target.forge or nil
    local entry = target and target.entry or nil
    if policy.verb(command, value, forge, entry) then
      items[#items + 1] = value
    end
  end
  return items
end

---@param command forge.Command
---@param state forge.CommandCompletionState
---@param prefix string
---@param policy table
---@return string[]
local function complete_pr_subjects(command, state, prefix, policy)
  local f, scope = source_mod.forge(state)
  if not f then
    return {}
  end
  local prs = source_mod.list(f, 'pr', policy.states_to_consult, policy.fetch_state, scope)
  local fields = f.pr_fields or {}
  local number_field = fields.number
  local state_field = fields.state
  local draft_field = fields['is_draft']
  local items = {}
  local seen = {}
  for _, pr in ipairs(prs or {}) do
    local num = tostring(pr[number_field] or '')
    local entry = completion_entry({
      num = num,
      scope = scope,
      state = pr[state_field],
      is_draft = draft_field and pr[draft_field] or nil,
    })
    if not policy.available or policy.available(command.name, f, entry) then
      add_completion_candidate(items, seen, num)
    end
  end
  return source_mod.filter(items, prefix)
end

---@param command forge.Command
---@param state forge.CommandCompletionState
---@param prefix string
---@param policy table
---@return string[]
local function complete_issue_subjects(command, state, prefix, policy)
  local f, scope = source_mod.forge(state)
  if not f then
    return {}
  end
  local issues = source_mod.list(f, 'issue', policy.states_to_consult, policy.fetch_state, scope)
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
  return source_mod.filter(items, prefix)
end

---@param state forge.CommandCompletionState
---@param prefix string
---@param policy table
---@return string[]
local function complete_run_subjects(state, prefix, policy)
  local f, scope = source_mod.forge(state)
  if not f then
    return {}
  end
  local runs = source_mod.list(f, 'ci', policy.states_to_consult, policy.fetch_state, scope)
  local items = {}
  local seen = {}
  for _, run in ipairs(runs or {}) do
    add_completion_candidate(items, seen, tostring(run.id or ''))
  end
  return source_mod.filter(items, prefix)
end

---@param state forge.CommandCompletionState
---@param prefix string
---@param policy table
---@return string[]
local function complete_release_subjects(state, prefix, policy)
  local f, scope = source_mod.forge(state)
  if not f then
    return {}
  end
  local releases =
    source_mod.list(f, 'release', policy.states_to_consult, policy.fetch_state, scope)
  local fields = f.release_fields or {}
  local items = {}
  local seen = {}
  for _, release in ipairs(releases or {}) do
    add_completion_candidate(items, seen, tostring(release[fields.tag] or ''))
  end
  return source_mod.filter(items, prefix)
end

---@param cmd_mod table
---@param command forge.Command
---@param state forge.CommandCompletionState
---@param flag_name string
---@param prefix string?
---@return string[]?
local function completion_values(cmd_mod, command, state, flag_name, prefix)
  local spec = cmd_mod.modifier(flag_name)
  local policy = require('forge.completion_policy').modifier_value(command, flag_name, spec)
  if not policy then
    return nil
  end
  if policy.source == 'repo' then
    return source_mod.repo_values(prefix or '')
  end
  if policy.source == 'ref' then
    return source_mod.ref_values(prefix or '')
  end
  if policy.source == 'rev_address' then
    return source_mod.rev_values(prefix or '')
  end
  if policy.source == 'target' then
    return source_mod.target_values(prefix or '')
  end
  if policy.source == 'template' then
    return source_mod.filter(issue_mod.template_slugs(), prefix or '')
  end
  if policy.source == 'adapter' then
    return source_mod.filter(review_mod.names(), prefix or '')
  end
  if policy.source == 'available_merge_methods' then
    local target = merge_method_completion_target(command, state)
    if not target then
      return source_mod.filter(spec.values, prefix or '')
    end
    return source_mod.filter(
      require('forge.availability').pr_merge_methods(target.forge, target.entry),
      prefix or ''
    )
  end
  if policy.source == 'command_values' then
    return source_mod.filter(command.modifier_values[flag_name], prefix or '')
  end
  if policy.source == 'modifier_values' then
    return source_mod.filter(spec.values, prefix or '')
  end
  return nil
end

---@param command forge.Command
---@param state forge.CommandCompletionState
---@param arglead string
---@return string[]
local function subject_completion_items(command, state, arglead)
  local subject = command.subject or { min = 0, max = 0 }
  local max = subject.max or subject.min or 0
  if max ~= nil and #state.subjects >= max then
    return {}
  end
  if subject.kind == 'branch' or subject.kind == 'rev' then
    return source_mod.ref_values(arglead)
  end
  if subject.kind == 'sha' then
    return source_mod.sha_values(arglead)
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

---@param cmd_mod table
---@param arglead string
---@param cmdline string
---@param split_words fun(text: string): string[]
---@return string[]
function M.complete(cmd_mod, arglead, cmdline, split_words)
  local words = split_words(cmdline)
  local arg_idx = arglead == '' and #words or #words - 1
  local family_name = words[2]
  local surface_opts = {
    forge_name = detect.forge_name(),
  }
  local family = cmd_mod.family(family_name, surface_opts)
  local explicit_verb = family
      and words[3] ~= nil
      and (family.verbs[words[3]] ~= nil or (family.aliases and family.aliases[words[3]] ~= nil))
      and words[3]
    or nil
  local flag, value_prefix = arglead:match('^([%w%-_]+)=(.*)$')
  if flag then
    local command = cmd_mod.resolve(family_name, explicit_verb, surface_opts)
    if command then
      command.declared_modifiers = command.modifiers or {}
      local rest_index = explicit_verb and 4 or 3
      local consumed = {}
      for i = rest_index, #words - 1 do
        consumed[#consumed + 1] = words[i]
      end
      local state = completion_state(command, consumed)
      local values = completion_values(cmd_mod, command, state, flag, value_prefix)
      if values then
        return vim.tbl_map(function(v)
          return flag .. '=' .. v
        end, values)
      end
    end
  end
  if arg_idx == 1 then
    return source_mod.filter(
      cmd_mod.family_names({
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
    local command = cmd_mod.resolve(family_name, nil, surface_opts)
    local state = command and completion_state(command, {}) or { modifiers = {}, subjects = {} }
    local slot_policy = require('forge.completion_policy').family_slot(command)
    local candidates = {}
    if slot_policy.include_verbs then
      for _, verb in
        ipairs(
          filter_family_verb_completion_items(
            command,
            state,
            cmd_mod.verb_names(family_name, surface_opts)
          )
        )
      do
        candidates[#candidates + 1] = verb
      end
    end
    if command then
      if slot_policy.include_modifiers then
        vim.list_extend(candidates, filtered_modifier_completion_items(cmd_mod, command, state))
      end
      if slot_policy.include_subjects then
        vim.list_extend(candidates, subject_completion_items(command, state, arglead))
      end
    end
    return source_mod.filter(candidates, arglead)
  end
  local command = cmd_mod.resolve(family_name, explicit_verb, surface_opts)
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
    vim.list_extend(candidates, filtered_modifier_completion_items(cmd_mod, command, state))
  end
  if slot_policy.include_subjects then
    vim.list_extend(candidates, subject_completion_items(command, state, arglead))
  end
  return source_mod.filter(candidates, arglead)
end

return M
