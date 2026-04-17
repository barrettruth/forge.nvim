vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.picker.state_verb', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('returns close for open pr entries', function()
    local verb = picker.state_verb('pr', { value = { num = '1', state = 'OPEN' } })
    assert.equals('close', verb)
  end)

  it('returns reopen for closed pr entries', function()
    local verb = picker.state_verb('pr', { value = { num = '1', state = 'CLOSED' } })
    assert.equals('reopen', verb)
  end)

  it('returns reopen for merged pr entries', function()
    local verb = picker.state_verb('pr', { value = { num = '1', state = 'MERGED' } })
    assert.equals('reopen', verb)
  end)

  it('returns close for open issue entries', function()
    local verb = picker.state_verb('issue', { value = { num = '1', state = 'opened' } })
    assert.equals('close', verb)
  end)

  it('returns reopen for closed issue entries', function()
    local verb = picker.state_verb('issue', { value = { num = '1', state = 'closed' } })
    assert.equals('reopen', verb)
  end)

  it('returns cancel for in-progress ci entries', function()
    for _, status in ipairs({ 'in_progress', 'queued', 'pending', 'running' }) do
      local verb = picker.state_verb('ci', { value = { id = '1', status = status } })
      assert.equals('cancel', verb, 'status=' .. status)
    end
  end)

  it('returns rerun for completed ci entries', function()
    for _, status in ipairs({ 'success', 'failure', 'cancelled', 'timed_out' }) do
      local verb = picker.state_verb('ci', { value = { id = '1', status = status } })
      assert.equals('rerun', verb, 'status=' .. status)
    end
  end)

  it('returns nil for skipped ci entries', function()
    local verb = picker.state_verb('ci', { value = { id = '1', status = 'skipped' } })
    assert.is_nil(verb)
  end)

  it('returns nil for placeholder or load_more entries', function()
    assert.is_nil(picker.state_verb('pr', { placeholder = true, value = { state = 'OPEN' } }))
    assert.is_nil(picker.state_verb('ci', { load_more = true, value = { status = 'running' } }))
  end)

  it('returns nil for entries missing value tables', function()
    assert.is_nil(picker.state_verb('pr', nil))
    assert.is_nil(picker.state_verb('pr', { value = 'not-a-table' }))
  end)

  it('returns nil for unknown picker names', function()
    assert.is_nil(picker.state_verb('release', { value = { state = 'OPEN' } }))
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
