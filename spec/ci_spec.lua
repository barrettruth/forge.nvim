vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.ci', function()
  local ci

  before_each(function()
    package.loaded['forge.ci'] = nil
    ci = require('forge.ci')
  end)

  it('treats active run statuses as in progress', function()
    for _, status in ipairs({ 'in_progress', 'queued', 'pending', 'running' }) do
      assert.is_true(ci.in_progress(status), 'status=' .. status)
      assert.equals('cancel', ci.toggle_verb({ status = status }), 'status=' .. status)
    end
  end)

  it('treats skipped runs as untoggleable', function()
    assert.is_false(ci.in_progress('skipped'))
    assert.is_nil(ci.toggle_verb({ status = 'skipped' }))
  end)

  it('treats completed and unknown statuses as rerunnable', function()
    for _, status in ipairs({ 'success', 'failure', 'cancelled', 'timed_out', 'unknown', '' }) do
      assert.is_false(ci.in_progress(status), 'status=' .. status)
      assert.equals('rerun', ci.toggle_verb({ status = status }), 'status=' .. status)
    end
  end)

  it('accepts run-like tables or raw status strings', function()
    assert.is_true(ci.in_progress({ status = 'running' }))
    assert.equals('cancel', ci.toggle_verb('queued'))
    assert.equals('rerun', ci.toggle_verb({ id = '1' }))
  end)
end)
