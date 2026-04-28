vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.completion_policy', function()
  local policy
  local old_availability
  local old_surface_policy

  before_each(function()
    old_availability = package.preload['forge.availability']
    old_surface_policy = package.preload['forge.surface_policy']

    package.loaded['forge.completion_policy'] = nil
    package.loaded['forge.availability'] = nil
    package.loaded['forge.surface_policy'] = nil

    package.preload['forge.availability'] = function()
      return {
        pr_can_approve = function(_, entry)
          return entry.value.approve == true
        end,
        pr_can_merge = function(_, entry)
          return entry.value.merge == true
        end,
        pr_can_mark_draft = function(_, entry)
          return entry.value.draft == true
        end,
        pr_can_mark_ready = function(_, entry)
          return entry.value.ready == true
        end,
      }
    end

    package.preload['forge.surface_policy'] = function()
      return {
        pr_toggle_verb = function(entry)
          return entry and entry.value and entry.value.pr_toggle or nil
        end,
        issue_toggle_verb = function(entry)
          return entry and entry.value and entry.value.issue_toggle or nil
        end,
      }
    end

    policy = require('forge.completion_policy')
  end)

  after_each(function()
    package.preload['forge.availability'] = old_availability
    package.preload['forge.surface_policy'] = old_surface_policy

    package.loaded['forge.completion_policy'] = nil
    package.loaded['forge.availability'] = nil
    package.loaded['forge.surface_policy'] = nil
  end)

  it('returns slot-composition policies for family and argument slots', function()
    assert.same({
      slot_class = 'family',
      include_verbs = true,
      include_modifiers = false,
      include_subjects = false,
      static_before_dynamic = true,
    }, policy.family_slot(nil))

    assert.same({
      slot_class = 'family',
      include_verbs = true,
      include_modifiers = true,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.family_slot({ family = 'review', name = 'open' }))

    assert.same({
      slot_class = 'family',
      include_verbs = false,
      include_modifiers = true,
      include_subjects = false,
      static_before_dynamic = true,
    }, policy.family_slot({ family = 'browse', name = 'open' }))

    assert.same({
      slot_class = 'family',
      include_verbs = false,
      include_modifiers = false,
      include_subjects = false,
      static_before_dynamic = true,
    }, policy.family_slot({ family = 'clear', name = 'run' }))

    assert.same({
      slot_class = 'argument',
      include_modifiers = true,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.argument_slot({ family = 'pr', name = 'merge' }, {}))

    assert.same({
      slot_class = 'argument',
      include_modifiers = true,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.argument_slot({ family = 'release', name = 'browse' }, { subjects = {} }))

    assert.same({
      slot_class = 'argument',
      include_modifiers = false,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.argument_slot({ family = 'release', name = 'delete' }, { subjects = {} }))

    assert.same({
      slot_class = 'argument',
      include_modifiers = true,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.argument_slot(
      { family = 'release', name = 'delete' },
      { subjects = { 'v1.0.0' } }
    ))
  end)

  it('filters implicit PR family verbs through picker-aligned availability helpers', function()
    local command = { family = 'pr', name = 'open' }

    assert.is_true(policy.verb(command, 'browse', {}, nil))
    assert.is_false(policy.verb(command, 'merge', {}, nil))
    assert.is_true(policy.verb(command, 'merge', {}, { value = { merge = true } }))
    assert.is_false(policy.verb(command, 'merge', {}, { value = { merge = false } }))
    assert.is_true(policy.verb(command, 'close', {}, { value = { pr_toggle = 'close' } }))
    assert.is_true(policy.verb(command, 'reopen', {}, { value = { pr_toggle = 'reopen' } }))
    assert.is_false(policy.verb(command, 'reopen', {}, { value = { pr_toggle = 'close' } }))
  end)

  it('classifies numeric subject suppression and release cache preferences', function()
    local merge = policy.subject({ name = 'merge', subject = { kind = 'pr' } })
    local reopen = policy.subject({ name = 'reopen', subject = { kind = 'pr' } })
    local issue = policy.subject({ name = 'close', subject = { kind = 'issue' } })
    local ci = policy.subject({ name = 'open', subject = { kind = 'run' } })
    local release = policy.subject({ name = 'delete', subject = { kind = 'release' } })
    local none = policy.subject({ name = 'create', subject = { min = 0, max = 0 } })

    assert.equals('pr_number', merge.subject_kind)
    assert.equals('suppress', merge.cmdline_usefulness)
    assert.same({}, merge.states_to_consult)
    assert.is_nil(merge.fetch_state)
    assert.is_false(merge.allow_fetch_on_tab)
    assert.is_false(merge.allow_empty_prefix)

    assert.equals('pr_number', reopen.subject_kind)
    assert.equals('suppress', reopen.cmdline_usefulness)
    assert.same({}, reopen.states_to_consult)
    assert.is_nil(reopen.fetch_state)
    assert.is_false(reopen.allow_fetch_on_tab)

    assert.equals('issue_number', issue.subject_kind)
    assert.equals('suppress', issue.cmdline_usefulness)
    assert.same({}, issue.states_to_consult)
    assert.is_nil(issue.fetch_state)
    assert.is_false(issue.allow_fetch_on_tab)

    assert.equals('ci_run_id', ci.subject_kind)
    assert.equals('suppress', ci.cmdline_usefulness)
    assert.same({}, ci.states_to_consult)
    assert.is_nil(ci.fetch_state)
    assert.is_false(ci.allow_fetch_on_tab)

    assert.equals('release_tag', release.subject_kind)
    assert.equals('dynamic_allowed', release.cmdline_usefulness)
    assert.same({ 'list' }, release.states_to_consult)
    assert.equals('list', release.fetch_state)

    assert.equals('none', none.subject_kind)
    assert.same({}, none.states_to_consult)
    assert.is_false(none.allow_fetch_on_tab)
  end)

  it('reuses picker-aligned availability helpers for subject policies', function()
    local merge = policy.subject({ name = 'merge', subject = { kind = 'pr' } })
    local close = policy.subject({ name = 'close', subject = { kind = 'pr' } })
    local issue = policy.subject({ name = 'reopen', subject = { kind = 'issue' } })

    assert.is_true(merge.available('merge', {}, { value = { merge = true } }))
    assert.is_false(merge.available('merge', {}, { value = { merge = false } }))

    assert.is_true(close.available('close', {}, { value = { pr_toggle = 'close' } }))
    assert.is_false(close.available('close', {}, { value = { pr_toggle = 'reopen' } }))

    assert.is_true(issue.available('reopen', {}, { value = { issue_toggle = 'reopen' } }))
    assert.is_false(issue.available('reopen', {}, { value = { issue_toggle = 'close' } }))
  end)

  it('classifies local and static modifier-value policies', function()
    local command = {
      modifiers = { 'repo', 'branch', 'commit', 'head', 'target', 'adapter', 'state', 'method' },
      modifier_values = {
        state = { 'open', 'closed' },
      },
    }

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'repo',
    }, policy.modifier_value(command, 'repo'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'ref',
    }, policy.modifier_value(command, 'branch'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'ref',
    }, policy.modifier_value(command, 'commit'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'rev_address',
    }, policy.modifier_value(command, 'head'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'target',
    }, policy.modifier_value(command, 'target'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'local_only',
      allow_empty_prefix = true,
      source = 'adapter',
    }, policy.modifier_value(command, 'adapter'))

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'static_only',
      allow_empty_prefix = true,
      source = 'command_values',
    }, policy.modifier_value(command, 'state'))

    assert.same(
      {
        slot_class = 'modifier_value',
        cmdline_usefulness = 'dynamic_allowed',
        allow_empty_prefix = true,
        source = 'available_merge_methods',
      },
      policy.modifier_value(
        { family = 'pr', name = 'merge', modifiers = { 'method' } },
        'method',
        { values = { 'merge', 'squash', 'rebase' } }
      )
    )

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'static_only',
      allow_empty_prefix = true,
      source = 'modifier_values',
    }, policy.modifier_value(command, 'method', { values = { 'merge', 'squash', 'rebase' } }))

    assert.is_nil(policy.modifier_value(command, 'rev'))
    assert.is_nil(policy.modifier_value(command, 'missing'))
  end)
end)
