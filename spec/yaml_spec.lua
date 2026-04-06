vim.opt.runtimepath:prepend(vim.fn.getcwd())

local yaml = require('forge.yaml')

local function read_template(name)
  local path = vim.fn.getcwd() .. '/.github/ISSUE_TEMPLATE/' .. name
  local stat = vim.uv.fs_stat(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  local content = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return content
end

describe('parse', function()
  it('parses simple key-value pairs', function()
    local doc = yaml.parse('name: Bug Report\ndescription: Report a bug')
    assert.equals('Bug Report', doc.name)
    assert.equals('Report a bug', doc.description)
  end)

  it('parses single-quoted values with colons', function()
    assert.equals('bug: ', yaml.parse("title: 'bug: '").title)
  end)

  it('parses double-quoted values', function()
    assert.equals('feat: ', yaml.parse('title: "feat: "').title)
  end)

  it('parses inline lists', function()
    assert.same({ 'bug' }, yaml.parse('labels: [bug]').labels)
    assert.same({ 'bug', 'enhancement' }, yaml.parse('labels: [bug, enhancement]').labels)
  end)

  it('skips comments and blank lines', function()
    assert.equals('Test', yaml.parse('# comment\n\nname: Test').name)
  end)

  it('parses literal block scalar', function()
    assert.equals('a\nb\nc', yaml.parse('v: |\n  a\n  b\n  c').v)
  end)

  it('parses folded block scalar', function()
    assert.equals('a b c', yaml.parse('v: >\n  a\n  b\n  c').v)
  end)

  it('parses nested mappings', function()
    local doc = yaml.parse('attrs:\n  label: Name\n  desc: Enter name')
    assert.equals('Name', doc.attrs.label)
    assert.equals('Enter name', doc.attrs.desc)
  end)

  it('parses sequence of plain scalars', function()
    local doc = yaml.parse('items:\n  - alpha\n  - beta')
    assert.same({ 'alpha', 'beta' }, doc.items)
  end)

  it('parses sequence of mappings', function()
    local text = 'body:\n  - type: textarea\n    attributes:\n      label: Desc'
    local doc = yaml.parse(text)
    assert.equals('textarea', doc.body[1].type)
    assert.equals('Desc', doc.body[1].attributes.label)
  end)

  it('parses nested sequence inside sequence item', function()
    local text = table.concat({
      'body:',
      '  - type: dropdown',
      '    attributes:',
      '      options:',
      '        - alpha',
      '        - beta',
    }, '\n')
    assert.same({ 'alpha', 'beta' }, yaml.parse(text).body[1].attributes.options)
  end)

  it('parses checkbox options as maps', function()
    local text = table.concat({
      'body:',
      '  - type: checkboxes',
      '    attributes:',
      '      options:',
      '        - label: I agree',
      '          required: true',
      '        - label: I searched',
    }, '\n')
    local opts = yaml.parse(text).body[1].attributes.options
    assert.equals('I agree', opts[1].label)
    assert.equals('true', opts[1].required)
    assert.equals('I searched', opts[2].label)
  end)

  it('parses multiline plain scalars', function()
    local text = table.concat({
      'body:',
      '  - type: checkboxes',
      '    attributes:',
      '      options:',
      '        - label:',
      '            I have searched [existing',
      '            issues](https://example.com)',
      '          required: true',
    }, '\n')
    local opts = yaml.parse(text).body[1].attributes.options
    assert.equals('I have searched [existing issues](https://example.com)', opts[1].label)
    assert.equals('true', opts[1].required)
  end)

  it('parses block scalar inside sequence item', function()
    local text = table.concat({
      'body:',
      '  - type: textarea',
      '    attributes:',
      '      value: |',
      '        1.',
      '        2.',
    }, '\n')
    assert.equals('1.\n2.', yaml.parse(text).body[1].attributes.value)
  end)

  describe('bug_report.yaml', function()
    local doc = yaml.parse(read_template('bug_report.yaml'))

    it('parses top-level fields', function()
      assert.equals('Bug Report', doc.name)
      assert.equals('bug: ', doc.title)
      assert.same({ 'bug' }, doc.labels)
    end)

    it('parses all body fields', function()
      assert.equals(8, #doc.body)
      assert.equals('checkboxes', doc.body[1].type)
      assert.equals('textarea', doc.body[2].type)
      assert.equals('input', doc.body[3].type)
    end)

    it('parses multiline checkbox label', function()
      local label = doc.body[1].attributes.options[1].label
      assert.truthy(label:match('searched'))
      assert.truthy(label:match('issues'))
    end)

    it('parses quoted labels', function()
      assert.equals('Neovim version', doc.body[2].attributes.label)
    end)

    it('parses block scalar value', function()
      assert.truthy(doc.body[5].attributes.value:match('^1%.'))
    end)

    it('parses multiline repro script', function()
      assert.truthy(doc.body[8].attributes.value:match('LAZY_STDPATH'))
    end)
  end)

  describe('feature_request.yaml', function()
    local doc = yaml.parse(read_template('feature_request.yaml'))

    it('parses top-level fields', function()
      assert.equals('Feature Request', doc.name)
      assert.equals('feat: ', doc.title)
      assert.same({ 'enhancement' }, doc.labels)
    end)

    it('parses all body fields', function()
      assert.equals(4, #doc.body)
    end)
  end)
end)

describe('render', function()
  it('renders markdown verbatim', function()
    local doc = { body = { { type = 'markdown', attributes = { value = 'Hello **world**' } } } }
    assert.equals('Hello **world**', yaml.render(doc).body)
  end)

  it('renders textarea with label and description', function()
    local body = yaml.render({
      body = {
        { type = 'textarea', attributes = { label = 'Desc', description = 'What happened?' } },
      },
    }).body
    assert.truthy(body:match('### Desc'))
    assert.truthy(body:match('<!%-%- What happened%?'))
  end)

  it('renders input with placeholder', function()
    local body = yaml.render({
      body = { { type = 'input', attributes = { label = 'OS', placeholder = 'e.g. Linux' } } },
    }).body
    assert.truthy(body:match('### OS'))
    assert.truthy(body:match('<!%-%- e%.g%. Linux'))
  end)

  it('renders dropdown as checkbox list', function()
    local body = yaml.render({
      body = { { type = 'dropdown', attributes = { label = 'Sev', options = { 'Low', 'High' } } } },
    }).body
    assert.truthy(body:match('%- %[ %] Low'))
    assert.truthy(body:match('%- %[ %] High'))
  end)

  it('renders checkboxes as checkbox list', function()
    local body = yaml.render({
      body = {
        {
          type = 'checkboxes',
          attributes = { options = { { label = 'I agree' }, { label = 'I searched' } } },
        },
      },
    }).body
    assert.truthy(body:match('%- %[ %] I agree'))
    assert.truthy(body:match('%- %[ %] I searched'))
  end)

  it('returns title and labels', function()
    local result = yaml.render({ title = 'bug: ', labels = { 'bug' }, body = {} })
    assert.equals('bug: ', result.title)
    assert.same({ 'bug' }, result.labels)
  end)

  it('wraps string labels into table', function()
    assert.same({ 'bug' }, yaml.render({ labels = 'bug', body = {} }).labels)
  end)

  describe('bug_report.yaml end-to-end', function()
    local result = yaml.render(yaml.parse(read_template('bug_report.yaml')))

    it('returns title and labels', function()
      assert.equals('bug: ', result.title)
      assert.same({ 'bug' }, result.labels)
    end)

    it('body has section headings', function()
      assert.truthy(result.body:match('### Prerequisites'))
      assert.truthy(result.body:match('### Neovim version'))
      assert.truthy(result.body:match('### Operating system'))
      assert.truthy(result.body:match('### Description'))
    end)

    it('body has checkbox items', function()
      assert.truthy(result.body:match('%- %[ %]'))
    end)

    it('body has placeholder for OS', function()
      assert.truthy(result.body:match('<!%-%- e%.g%. Arch Linux'))
    end)
  end)
end)
