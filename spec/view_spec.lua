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

describe('where a list got to', function()
  it('survives the buffer variable it is kept in', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].forge = { page = 1, cursors = { [view.at(2)] = 'CURSOR2' }, has_next = true }

    local paging = view.paging(buf)
    assert.is_nil(paging.cursors[view.at(1)])
    assert.equals('CURSOR2', paging.cursors[view.at(2)])
  end)

  it('would not, keyed by number: the first page has no cursor', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].forge = { cursors = { [2] = 'CURSOR2' } }

    local cursors = view.paging(buf).cursors
    assert.equals(vim.NIL, cursors[1])
    assert.is_truthy(cursors[1])
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

describe('a capped connection', function()
  local log = require('forge.log')

  --- @return string[] warnings, fun() restore
  local function capture()
    local said = {}
    local real = log.warn
    --- @diagnostic disable-next-line: duplicate-set-field
    log.warn = function(msg)
      said[#said + 1] = msg
    end
    return said, function()
      log.warn = real
    end
  end

  it('says so when the tail was lost', function()
    local said, restore = capture()
    view.check_truncated({ nodes = { 1, 2 }, totalCount = 25 }, 'labels')
    restore()
    assert.same({ 'showing 2 of 25 labels' }, said)
  end)

  it('stays quiet when nothing was lost', function()
    local said, restore = capture()
    view.check_truncated({ nodes = { 1, 2 }, totalCount = 2 }, 'labels')
    view.check_truncated({ nodes = {} }, 'comments')
    view.check_truncated(nil, 'comments')
    restore()
    assert.same({}, said)
  end)
end)
