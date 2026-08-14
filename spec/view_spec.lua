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
    local first = view.render(uri('pulls', 9), { 'one' }, 'PR')
    local again = view.render(uri('pulls', 9), { 'two' }, 'PR')

    assert.equals(first, again)
    assert.same({ 'two' }, vim.api.nvim_buf_get_lines(again, 0, -1, false))
  end)
end)
