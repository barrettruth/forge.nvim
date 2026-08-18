local text = require('forge.text')

local function profile(login)
  return 'https://github.com/' .. login
end

local function ago(days)
  return os.date('!%Y-%m-%dT%H:%M:%SZ', os.time() - days * 86400) --[[@as string]]
end

describe('a body github wrote', function()
  it('loses the carriage returns a browser put in it', function()
    local lines = {}
    text.append_body(lines, {}, 'first\r\nsecond\r\n\r\nthird')
    assert.same({ 'first', 'second', '', 'third' }, lines)
  end)

  it('is unharmed when it had none', function()
    local lines = {}
    text.append_body(lines, {}, 'plain\nlf')
    assert.same({ 'plain', 'lf' }, lines)
  end)

  it('marks what github itself would have linked in it', function()
    local lines, marks = {}, {}
    text.append_body(lines, marks, 'thanks @clason, see #123 and o/r#4')
    assert.same({
      {
        row = 0,
        col = 7,
        end_col = 14,
        group = { '@markup.italic', '@markup.link' },
        url = 'https://github.com/clason',
      },
      { row = 0, col = 29, end_col = 34, group = { 'Tag', '@markup.link' } },
      { row = 0, col = 20, end_col = 24, group = { 'Tag', '@markup.link' } },
    }, marks)
  end)

  it('marks nothing inside a fence, where github links nothing either', function()
    local lines, marks = {}, {}
    text.append_body(
      lines,
      marks,
      table.concat({
        'ask @clason',
        '```lua',
        '--- @param x see #1',
        '```',
        'or @justinmk',
      }, '\n')
    )
    assert.same(
      { 0, 4 },
      vim.tbl_map(function(m)
        return m.row
      end, marks)
    )
  end)

  it('leaves a mention alone when it is part of a word', function()
    local lines, marks = {}, {}
    text.append_body(lines, marks, 'mail me@example.com about x#1')
    assert.same({}, marks)
  end)

  it('says what it was given to say for an empty one, dimmed', function()
    local said = 'No description provided.'
    for _, body in ipairs({ { '' }, { '  \r\n\n ' }, {} }) do
      local lines, marks = {}, {}
      text.append_body(lines, marks, body[1], said)
      assert.same({ said }, lines)
      assert.same({ { row = 0, col = 0, end_col = #said, group = 'Comment' } }, marks)
    end
  end)

  it('says nothing for an empty one when given no words for it', function()
    local lines, marks = {}, {}
    text.append_body(lines, marks, '', nil)
    assert.same({}, lines)
    assert.same({}, marks)
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
  local function comment(body)
    return {
      author = { login = 'someone' },
      authorAssociation = 'OWNER',
      createdAt = ago(0),
      body = body,
    }
  end

  it('aligns what is known in a column, and leaves out what is not', function()
    local lines, marks = {}, {}
    text.append_rows(lines, marks, {
      { key = 'Assignees', values = { 'clason' }, group = text.LOGIN, link = profile },
      { key = 'Reviewers', values = {}, group = text.LOGIN, link = profile },
      { key = 'Labels', values = { 'bug', 'ui' }, group = 'Tag' },
      { key = 'Milestone', values = { nil }, group = 'Tag' },
    })
    assert.same({
      '  Assignees:  clason',
      '  Labels:     bug, ui',
    }, lines)
    assert.same({
      { row = 0, col = 0, end_col = 12, group = 'Comment' },
      {
        row = 0,
        col = 14,
        end_col = 20,
        group = { '@markup.italic', '@markup.link' },
        url = 'https://github.com/clason',
      },
      { row = 1, col = 0, end_col = 9, group = 'Comment' },
      { row = 1, col = 14, end_col = 17, group = 'Tag' },
      { row = 1, col = 19, end_col = 21, group = 'Tag' },
    }, marks)
  end)

  it('reads a login out of whichever shape github answered with', function()
    assert.same({ 'a', 'b' }, text.logins({ nodes = { { login = 'a' }, {}, { name = 'b' } } }))
    assert.same({}, text.logins(nil))
  end)

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
      {
        row = 3,
        col = 4,
        end_col = 11,
        group = { '@markup.italic', '@markup.link' },
        url = 'https://github.com/someone',
      },
      { row = 3, col = 13, end_col = #lines[4], group = 'Comment' },
    }, marks)
  end)

  it('says nothing of the association github gives a passer-by', function()
    local lines, marks = {}, {}
    local anyone = vim.tbl_extend('force', comment('hi'), { authorAssociation = 'NONE' })
    text.append_comments(lines, marks, { totalCount = 1, nodes = { anyone } })
    assert.equals('▎ someone  today', lines[4])
  end)

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

  it('leaves an empty comment empty, having no description to be missing', function()
    local lines, marks = {}, {}
    text.append_comments(lines, marks, {
      totalCount = 1,
      nodes = { { author = { login = 'someone' }, createdAt = ago(0), body = '' } },
    })
    assert.same({ '', '## Comments (1)', '', '▎ someone  today', '' }, lines)
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
