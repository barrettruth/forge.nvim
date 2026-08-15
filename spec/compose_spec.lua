local compose = require('forge.compose')

--- @return forge.Template
local function form()
  return {
    name = 'Feature request',
    path = 'x.yml',
    title = '[feature]: ',
    labels = { 'enhancement' },
    assignees = {},
    guidance = { [1] = 'Read this first', [2] = 'One line' },
    fields = {
      { kind = 'input', label = 'Summary', required = true },
      { kind = 'textarea', label = 'Detail', required = false },
      {
        kind = 'checkboxes',
        label = 'Acknowledgements',
        required = false,
        options = { 'I read it', 'I will help' },
        required_options = { true, false },
      },
    },
  }
end

describe('compose.skeleton', function()
  it('writes the markdown that will be filed, and nothing else', function()
    local lines = compose.skeleton(form())
    assert.same({
      '[feature]: ',
      '',
      '### Summary',
      '',
      '### Detail',
      '',
      '### Acknowledgements',
      '',
      '- [ ] I read it',
      '- [ ] I will help',
      '',
    }, lines)
  end)

  it('keeps guidance out of the text entirely', function()
    local lines = compose.skeleton(form())
    for _, line in ipairs(lines) do
      assert.is_nil(line:find('Read this first', 1, true))
      assert.is_nil(line:find('One line', 1, true))
    end
  end)

  it('marks what is required, above the line and at its end', function()
    local _, marks = compose.skeleton(form())
    local above, eol = 0, 0
    for _, mark in ipairs(marks) do
      if mark[3].virt_lines then
        above = above + 1
      else
        eol = eol + 1
        assert.equals('', mark[3].virt_text[1][2])
        assert.equals('*', mark[3].virt_text[2][1])
        assert.equals('DiagnosticError', mark[3].virt_text[2][2])
      end
    end
    assert.equals(2, above)
    assert.equals(2, eol)
  end)

  it('uses a markdown template whole', function()
    local lines = compose.skeleton({
      name = 'Bug',
      path = 'x.md',
      title = '[bug]: ',
      labels = {},
      assignees = {},
      guidance = {},
      body = '## What happened\n\n<!-- keep me -->',
    })
    assert.same({ '[bug]: ', '', '## What happened', '', '<!-- keep me -->' }, lines)
  end)
end)

describe('compose.contents', function()
  local fields = form().fields

  it('refuses without a title, which github will not invent', function()
    local title, _, err = compose.contents({ '', '', '### Summary', '', 'x' }, fields)
    assert.is_nil(title)
    assert.is_truthy(err:find('title', 1, true))
  end)

  it('refuses while a required answer is blank', function()
    local title, _, err = compose.contents({ 'a title', '', '### Summary', '', '' }, fields)
    assert.is_nil(title)
    assert.equals('Summary is required', err)
  end)

  it('writes _No response_ where github would', function()
    local title, body = compose.contents({
      'a title',
      '',
      '### Summary',
      '',
      'it is summarised',
      '',
      '### Detail',
      '',
      '',
      '### Acknowledgements',
      '',
      '- [x] I read it',
      '- [ ] I will help',
    }, fields)
    assert.equals('a title', title)
    assert.equals(
      table.concat({
        '### Summary',
        '',
        'it is summarised',
        '',
        '### Detail',
        '',
        '_No response_',
        '',
        '### Acknowledgements',
        '',
        '- [x] I read it\n- [ ] I will help',
      }, '\n'),
      body
    )
  end)

  it('sends a template with no fields exactly as written', function()
    local title, body = compose.contents({ 'a title', '', 'free', 'text' }, {})
    assert.equals('a title', title)
    assert.equals('free\ntext', body)
  end)
end)
