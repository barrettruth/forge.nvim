local text = require('forge.text')

--- @param days integer
--- @return string
local function ago(days)
  return os.date('!%Y-%m-%dT%H:%M:%SZ', os.time() - days * 86400) --[[@as string]]
end

describe('a body github wrote', function()
  it('loses the carriage returns a browser put in it', function()
    local lines = {}
    text.append_body(lines, 'first\r\nsecond\r\n\r\nthird')
    assert.same({ 'first', 'second', '', 'third' }, lines)
  end)

  it('is unharmed when it had none', function()
    local lines = {}
    text.append_body(lines, 'plain\nlf')
    assert.same({ 'plain', 'lf' }, lines)
  end)

  it('is nothing at all when there is no body', function()
    local lines = {}
    text.append_body(lines, nil)
    assert.same({ '' }, lines)
  end)
end)

describe('how long ago', function()
  it('counts in days for the first month', function()
    assert.equals('today', text.age(ago(0)))
    assert.equals('5 days ago', text.age(ago(5)))
  end)

  it('gives a date once "ago" stops telling you anything', function()
    for _, days in ipairs({ 45, 200, 400, 2800 }) do
      local epoch = os.time() - days * 86400
      assert.equals(os.date('%Y-%m-%d', epoch), text.age(ago(days)))
    end
  end)

  it('writes that date the one way nobody reads backwards', function()
    assert.is_truthy(text.age('2019-01-02T12:00:00Z'):match('^2019%-01%-0[123]$'))
  end)

  it('says so when it cannot tell', function()
    assert.equals('unknown', text.age(nil))
    assert.equals('not a date', text.age('not a date'))
  end)
end)

describe('a conversation', function()
  --- @param body string
  --- @return table
  local function comment(body)
    return {
      author = { login = 'someone' },
      authorAssociation = 'OWNER',
      createdAt = ago(0),
      body = body,
    }
  end

  it('starts each comment with a bar, not a heading', function()
    local lines, marks = {}, {}
    text.append_comments(lines, marks, { totalCount = 1, nodes = { comment('hello') } })
    assert.same({
      '',
      '## Comments (1)',
      '',
      '▎ someone  OWNER  today',
      '',
      'hello',
    }, lines)
  end)

  it('emphasises who said it and dims everything either side', function()
    local lines, marks = {}, {}
    text.append_comments(lines, marks, { totalCount = 1, nodes = { comment('hello') } })
    assert.equals('▎ someone  OWNER  today', lines[4])
    assert.same({
      { row = 3, col = 0, end_col = 3, group = 'Comment' },
      { row = 3, col = 4, end_col = 11, group = '@markup.italic' },
      { row = 3, col = 13, end_col = #lines[4], group = 'Comment' },
    }, marks)
  end)

  it('says nothing of the association github gives a passer-by', function()
    local lines, marks = {}, {}
    local anyone = vim.tbl_extend('force', comment('hi'), { authorAssociation = 'NONE' })
    text.append_comments(lines, marks, { totalCount = 1, nodes = { anyone } })
    assert.equals('▎ someone  today', lines[4])
  end)

  --- A body is markdown somebody else wrote, and one in a hundred of neovim's
  --- carries a heading. Nothing in it may look like the start of a comment.
  it('is not something a body can spell for itself', function()
    local lines, marks = {}, {}
    text.append_comments(lines, marks, {
      totalCount = 1,
      nodes = { comment('### Implementation Summary\n\n- a point\n\n===') },
    })
    local bars = vim.tbl_filter(function(l)
      return l:sub(1, 3) == '▎'
    end, lines)
    assert.equals(1, #bars)
    assert.equals(3, #marks)
  end)

  it('strips the carriage returns out of a comment too', function()
    local lines = {}
    text.append_comments(lines, {}, { totalCount = 1, nodes = { comment('one\r\ntwo') } })
    assert.equals('one', lines[#lines - 1])
    assert.equals('two', lines[#lines])
  end)

  it('says nothing when nobody replied', function()
    local lines = {}
    text.append_comments(lines, {}, { totalCount = 0, nodes = {} })
    text.append_comments(lines, nil)
    assert.same({}, lines)
  end)
end)
