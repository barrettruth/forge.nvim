vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('collections helpers', function()
  local collections

  before_each(function()
    package.loaded['forge.collections'] = nil
    collections = require('forge.collections')
  end)

  it('finds values in sequential lists', function()
    assert.is_true(collections.list_contains({ 'repo', 'head', 'base' }, 'head'))
    assert.is_false(collections.list_contains({ 'repo', 'head', 'base' }, 'branch'))
  end)

  it('treats nil lists as empty for list membership checks', function()
    assert.is_false(collections.list_contains(nil, 'repo'))
  end)

  it('only treats tables as sets for set membership checks', function()
    assert.is_true(collections.set_contains({ 'open', 'closed' }, 'closed'))
    assert.is_false(collections.set_contains(nil, 'closed'))
    assert.is_false(collections.set_contains('open,closed', 'closed'))
  end)
end)
