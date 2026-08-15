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

  it('counts in months, and says one of them in the singular', function()
    assert.equals('1 month ago', text.age(ago(45)))
    assert.equals('6 months ago', text.age(ago(200)))
  end)

  it('stops counting months before the number stops meaning anything', function()
    assert.equals('1 year ago', text.age(ago(400)))
    assert.equals('7 years ago', text.age(ago(2800)))
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

  it('heads each comment, so markdown can navigate between them', function()
    local lines = {}
    text.append_comments(lines, { totalCount = 1, nodes = { comment('hello') } })
    assert.same({
      '',
      '## Comments (1)',
      '',
      '### someone (OWNER) — today',
      '',
      'hello',
    }, lines)
  end)

  it('strips the carriage returns out of a comment too', function()
    local lines = {}
    text.append_comments(lines, { totalCount = 1, nodes = { comment('one\r\ntwo') } })
    assert.equals('one', lines[#lines - 1])
    assert.equals('two', lines[#lines])
  end)

  it('says nothing when nobody replied', function()
    local lines = {}
    text.append_comments(lines, { totalCount = 0, nodes = {} })
    text.append_comments(lines, nil)
    assert.same({}, lines)
  end)
end)
