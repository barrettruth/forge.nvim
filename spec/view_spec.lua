local view = require('forge.view')

local function uri(collection, number)
  return { owner = 'a', repo = 'b', collection = collection, number = number, state = 'OPEN' }
end

describe('view.render', function()
  it('gives a list its own buffer when an item is already open', function()
    local item = view.render(uri('issues', 27), { 'the issue' }, 'ITEM')
    local list = view.render(uri('issues'), { 'the list' }, 'LIST')

    assert.are_not.equal(item, list)
    assert.equals('forge://a/b/issues/27', vim.api.nvim_buf_get_name(item))
    assert.equals('forge://a/b/issues', vim.api.nvim_buf_get_name(list))
    assert.same({ 'the issue' }, vim.api.nvim_buf_get_lines(item, 0, -1, false))
    assert.same({ 'the list' }, vim.api.nvim_buf_get_lines(list, 0, -1, false))
  end)

  it('reuses the buffer a view already has', function()
    local first = view.render(uri('prs', 9), { 'one' }, 'PR')
    local again = view.render(uri('prs', 9), { 'two' }, 'PR')

    assert.equals(first, again)
    assert.same({ 'two' }, vim.api.nvim_buf_get_lines(again, 0, -1, false))
  end)
end)

describe('an item opened from a list', function()
  it('remembers which half of the collection it came from', function()
    local buf = view.render(
      { owner = 'a', repo = 'b', collection = 'issues', number = 5, state = 'CLOSED' },
      { 'x' },
      'ITEM'
    )
    assert.equals('CLOSED', vim.b[buf].forge.state)
  end)

  it('does not forget it when refreshed by name', function()
    local from_list =
      { owner = 'a', repo = 'b', collection = 'issues', number = 6, state = 'CLOSED' }
    local by_name = { owner = 'a', repo = 'b', collection = 'issues', number = 6 }

    local buf = view.render(from_list, { 'x' }, 'ITEM')
    view.render(by_name, { 'x again' }, 'ITEM')

    assert.equals('CLOSED', vim.b[buf].forge.state)
  end)
end)
