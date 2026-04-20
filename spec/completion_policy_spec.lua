vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.completion_policy', function()
  local policy
  local old_availability
  local old_picker

  before_each(function()
    old_availability = package.preload['forge.availability']
    old_picker = package.preload['forge.picker']

    package.loaded['forge.completion_policy'] = nil
    package.loaded['forge.availability'] = nil
    package.loaded['forge.picker'] = nil

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

    package.preload['forge.picker'] = function()
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
    package.preload['forge.picker'] = old_picker

    package.loaded['forge.completion_policy'] = nil
    package.loaded['forge.availability'] = nil
    package.loaded['forge.picker'] = nil
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
      slot_class = 'argument',
      include_modifiers = true,
      include_subjects = true,
      static_before_dynamic = true,
    }, policy.argument_slot({ family = 'pr', name = 'merge' }, {}))
  end)

  it('classifies subject policies and cache preferences', function()
    local merge = policy.subject({ name = 'merge', subject = { kind = 'pr' } })
    local reopen = policy.subject({ name = 'reopen', subject = { kind = 'pr' } })
    local issue = policy.subject({ name = 'close', subject = { kind = 'issue' } })
    local ci = policy.subject({ name = 'open', subject = { kind = 'run' } })
    local release = policy.subject({ name = 'delete', subject = { kind = 'release' } })
    local none = policy.subject({ name = 'create', subject = { min = 0, max = 0 } })

    assert.equals('pr_number', merge.subject_kind)
    assert.same({ 'open', 'all' }, merge.states_to_consult)
    assert.equals('open', merge.fetch_state)
    assert.is_true(merge.allow_fetch_on_tab)
    assert.is_true(merge.allow_empty_prefix)

    assert.equals('pr_number', reopen.subject_kind)
    assert.same({ 'closed', 'all' }, reopen.states_to_consult)
    assert.equals('closed', reopen.fetch_state)

    assert.equals('issue_number', issue.subject_kind)
    assert.same({ 'open', 'all' }, issue.states_to_consult)
    assert.equals('open', issue.fetch_state)

    assert.equals('ci_run_id', ci.subject_kind)
    assert.same({ 'all' }, ci.states_to_consult)
    assert.equals('all', ci.fetch_state)

    assert.equals('release_tag', release.subject_kind)
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
      modifier_values = {
        adapter = { 'browse' },
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
      source = 'rev_address',
    }, policy.modifier_value(command, 'head'))

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

    assert.same({
      slot_class = 'modifier_value',
      cmdline_usefulness = 'static_only',
      allow_empty_prefix = true,
      source = 'modifier_values',
    }, policy.modifier_value(command, 'method', { values = { 'merge', 'squash', 'rebase' } }))

    assert.is_nil(policy.modifier_value(command, 'missing'))
  end)
end)
