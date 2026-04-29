local M = {}

local availability = require('forge.surface.availability')
local collections = require('forge.collections')
local surface_policy = require('forge.surface.policy')

local implicit_pr_completion_verbs = {
  approve = true,
  merge = true,
  close = true,
  draft = true,
  ready = true,
  reopen = true,
}

local function pr_completion_available(verb, f, entry)
  if verb == 'approve' then
    return availability.pr_can_approve(f, entry)
  end
  if verb == 'merge' then
    return availability.pr_can_merge(f, entry)
  end
  if verb == 'draft' then
    return availability.pr_can_mark_draft(f, entry)
  end
  if verb == 'ready' then
    return availability.pr_can_mark_ready(f, entry)
  end
  if verb == 'close' then
    return surface_policy.pr_toggle_verb(entry) == 'close'
  end
  if verb == 'reopen' then
    return surface_policy.pr_toggle_verb(entry) == 'reopen'
  end
  return true
end

local function issue_completion_available(verb, _, entry)
  if verb == 'close' then
    return surface_policy.issue_toggle_verb(entry) == 'close'
  end
  if verb == 'reopen' then
    return surface_policy.issue_toggle_verb(entry) == 'reopen'
  end
  return true
end

local function declares_modifier(command, flag_name)
  if type(command) ~= 'table' then
    return false
  end
  return collections.list_contains(command.declared_modifiers or command.modifiers, flag_name)
end

function M.family_slot(command)
  if command and command.family == 'browse' and command.name == 'open' then
    return {
      slot_class = 'family',
      include_verbs = false,
      include_modifiers = true,
      include_subjects = false,
      static_before_dynamic = true,
    }
  end
  if command and command.family == 'clear' and command.name == 'run' then
    return {
      slot_class = 'family',
      include_verbs = false,
      include_modifiers = false,
      include_subjects = false,
      static_before_dynamic = true,
    }
  end
  return {
    slot_class = 'family',
    include_verbs = true,
    include_modifiers = command ~= nil,
    include_subjects = command ~= nil,
    static_before_dynamic = true,
  }
end

local function release_delete_subject_slot(state)
  return type(state) == 'table' and #(state.subjects or {}) == 0
end

function M.argument_slot(command, state)
  if command and command.family == 'release' and command.name == 'delete' then
    return {
      slot_class = 'argument',
      include_modifiers = not release_delete_subject_slot(state),
      include_subjects = true,
      static_before_dynamic = true,
    }
  end
  return {
    slot_class = 'argument',
    include_modifiers = command ~= nil,
    include_subjects = command ~= nil,
    static_before_dynamic = true,
  }
end

function M.verb(command, verb, f, entry)
  if
    type(command) == 'table'
    and command.family == 'pr'
    and command.name == 'open'
    and implicit_pr_completion_verbs[verb]
  then
    return entry ~= nil and pr_completion_available(verb, f, entry)
  end
  return true
end

function M.subject(command)
  local subject = command.subject or { min = 0, max = 0 }
  if subject.kind == 'pr' then
    return {
      slot_class = 'subject',
      subject_kind = 'pr_number',
      cmdline_usefulness = 'suppress',
      states_to_consult = {},
      fetch_state = nil,
      allow_fetch_on_tab = false,
      allow_empty_prefix = false,
      available = pr_completion_available,
    }
  end
  if subject.kind == 'issue' then
    return {
      slot_class = 'subject',
      subject_kind = 'issue_number',
      cmdline_usefulness = 'suppress',
      states_to_consult = {},
      fetch_state = nil,
      allow_fetch_on_tab = false,
      allow_empty_prefix = false,
      available = issue_completion_available,
    }
  end
  if subject.kind == 'run' then
    return {
      slot_class = 'subject',
      subject_kind = 'ci_run_id',
      cmdline_usefulness = 'suppress',
      states_to_consult = {},
      fetch_state = nil,
      allow_fetch_on_tab = false,
      allow_empty_prefix = false,
    }
  end
  if subject.kind == 'release' then
    return {
      slot_class = 'subject',
      subject_kind = 'release_tag',
      cmdline_usefulness = 'dynamic_allowed',
      states_to_consult = { 'list' },
      fetch_state = 'list',
      allow_fetch_on_tab = true,
      allow_empty_prefix = true,
    }
  end
  return {
    slot_class = 'subject',
    subject_kind = 'none',
    cmdline_usefulness = 'static_only',
    states_to_consult = {},
    allow_fetch_on_tab = false,
    allow_empty_prefix = true,
  }
end

function M.modifier_value(command, flag_name, spec)
  if not declares_modifier(command, flag_name) then
    return nil
  end
  if flag_name == 'repo' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'repo',
    }
  end
  if flag_name == 'branch' or flag_name == 'commit' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'ref',
    }
  end
  if flag_name == 'head' or flag_name == 'base' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'rev_address',
    }
  end
  if flag_name == 'target' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'target',
    }
  end
  if flag_name == 'template' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'template',
    }
  end
  if flag_name == 'adapter' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'adapter',
    }
  end
  if command.family == 'pr' and command.name == 'merge' and flag_name == 'method' then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'dynamic_allowed',
      allow_empty_prefix = true,
      source = 'available_merge_methods',
    }
  end
  if command.modifier_values and command.modifier_values[flag_name] then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'static_only',
      allow_empty_prefix = true,
      source = 'command_values',
    }
  end
  if spec and spec.values then
    return {
      slot_class = 'modifier_value',
      cmdline_usefulness = 'static_only',
      allow_empty_prefix = true,
      source = 'modifier_values',
    }
  end
  return nil
end

return M
