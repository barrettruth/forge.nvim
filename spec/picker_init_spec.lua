vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.picker.pr_toggle_verb', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('returns close for open prs', function()
    assert.equals('close', picker.pr_toggle_verb({ value = { num = '1', state = 'OPEN' } }))
  end)

  it('returns close for lowercase opened state (gitlab)', function()
    assert.equals('close', picker.pr_toggle_verb({ value = { num = '1', state = 'opened' } }))
  end)

  it('returns reopen for closed (non-merged) prs', function()
    assert.equals('reopen', picker.pr_toggle_verb({ value = { num = '1', state = 'CLOSED' } }))
  end)

  it('returns nil for merged prs because merged is a terminal state', function()
    assert.is_nil(picker.pr_toggle_verb({ value = { num = '1', state = 'MERGED' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(picker.pr_toggle_verb({ placeholder = true, value = { state = 'OPEN' } }))
    assert.is_nil(picker.pr_toggle_verb({ load_more = true, value = { state = 'OPEN' } }))
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(picker.pr_toggle_verb(nil))
    assert.is_nil(picker.pr_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.picker.issue_toggle_verb', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('returns close for open issues', function()
    assert.equals('close', picker.issue_toggle_verb({ value = { num = '1', state = 'opened' } }))
  end)

  it('returns reopen for closed issues', function()
    assert.equals('reopen', picker.issue_toggle_verb({ value = { num = '1', state = 'closed' } }))
  end)

  it('does not treat merged as a valid issue state', function()
    assert.is_nil(picker.issue_toggle_verb({ value = { num = '1', state = 'merged' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(picker.issue_toggle_verb({ placeholder = true, value = { state = 'OPEN' } }))
    assert.is_nil(picker.issue_toggle_verb({ load_more = true, value = { state = 'OPEN' } }))
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(picker.issue_toggle_verb(nil))
    assert.is_nil(picker.issue_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.picker.ci_toggle_verb', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('returns cancel for in-progress runs', function()
    for _, status in ipairs({ 'in_progress', 'queued', 'pending', 'running' }) do
      assert.equals(
        'cancel',
        picker.ci_toggle_verb({ value = { id = '1', status = status } }),
        'status=' .. status
      )
    end
  end)

  it('returns rerun for completed runs', function()
    for _, status in ipairs({ 'success', 'failure', 'cancelled', 'timed_out' }) do
      assert.equals(
        'rerun',
        picker.ci_toggle_verb({ value = { id = '1', status = status } }),
        'status=' .. status
      )
    end
  end)

  it('returns nil for skipped runs', function()
    assert.is_nil(picker.ci_toggle_verb({ value = { id = '1', status = 'skipped' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(picker.ci_toggle_verb({ placeholder = true, value = { status = 'running' } }))
    assert.is_nil(picker.ci_toggle_verb({ load_more = true, value = { status = 'running' } }))
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(picker.ci_toggle_verb(nil))
    assert.is_nil(picker.ci_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.picker.resolve_label', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('returns string labels verbatim', function()
    assert.equals('merge', picker.resolve_label({ name = 'merge', label = 'merge' }))
  end)

  it('invokes function labels with the entry', function()
    local captured
    local def = {
      name = 'toggle',
      label = function(entry)
        captured = entry
        return 'close'
      end,
    }
    local label = picker.resolve_label(def, { value = { state = 'OPEN' } })
    assert.equals('close', label)
    assert.same({ value = { state = 'OPEN' } }, captured)
  end)

  it('returns nil when a function label raises', function()
    local def = {
      name = 'toggle',
      label = function()
        error('boom')
      end,
    }
    assert.is_nil(picker.resolve_label(def, nil))
  end)

  it('reports dynamic labels', function()
    assert.is_true(picker.has_dynamic_label({ name = 'a', label = function() end }))
    assert.is_false(picker.has_dynamic_label({ name = 'b', label = 'static' }))
    assert.is_false(picker.has_dynamic_label({ name = 'c' }))
  end)
end)
