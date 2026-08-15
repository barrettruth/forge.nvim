local template = require('forge.template')

local FIXTURE = vim.fn.expand('~/dev/forge-fixture')

--- The fixture is a private repository that only Barrett has, so these are
--- skipped rather than failed anywhere else.
local function fixture()
  return vim.uv.fs_stat(FIXTURE .. '/.github') ~= nil
end

--- @param name string
--- @return forge.Template?
local function issue_template(name)
  for _, found in ipairs(template.all('issues', FIXTURE)) do
    if found.name == name then
      return found
    end
  end
end

describe('template.all', function()
  it('finds forms and markdown, and never config.yml', function()
    if not fixture() then
      return
    end
    local names = {}
    for _, found in ipairs(template.all('issues', FIXTURE)) do
      names[#names + 1] = found.name
    end
    assert.same({ 'Feature request', 'Question', 'Bug report' }, names)
  end)

  it('counts a case-insensitive filesystem once', function()
    if not fixture() then
      return
    end
    assert.equals(1, #template.all('prs', FIXTURE))
  end)

  it('finds nothing where there is nothing', function()
    assert.same({}, template.all('issues', '/tmp'))
  end)
end)

describe('a markdown template', function()
  it('reads front matter as a list or as one comma-separated string', function()
    if not fixture() then
      return
    end
    local bug = assert(issue_template('Bug report'))
    assert.same({ 'bug', 'needs-triage' }, bug.labels)
    assert.same({ 'barrettruth', 'octocat' }, bug.assignees)
    assert.equals('[bug]: ', bug.title)
  end)

  it('keeps the body whole', function()
    if not fixture() then
      return
    end
    local body = assert(assert(issue_template('Bug report')).body)
    assert.is_not.equal('---', body:sub(1, 3))
    assert.is_truthy(body:find('<!--', 1, true))
    assert.is_truthy(body:find('```', 1, true))
  end)
end)

describe('a form', function()
  it('reads every element type github accepts', function()
    if not fixture() then
      return
    end
    local kinds = {}
    for _, field in ipairs(assert(assert(issue_template('Feature request')).fields)) do
      kinds[#kinds + 1] = field.kind
    end
    assert.same(
      { 'input', 'input', 'textarea', 'textarea', 'dropdown', 'dropdown', 'checkboxes' },
      kinds
    )
  end)

  it('reads what each element was asked to do', function()
    if not fixture() then
      return
    end
    local fields = assert(assert(issue_template('Feature request')).fields)
    assert.is_true(fields[1].required)
    assert.is_false(fields[2].required)
    assert.equals('lua', fields[4].render)
    assert.same({ 'lua', 'python', 'go' }, fields[5].options)
    assert.is_false(fields[5].multiple)
    assert.is_true(fields[6].multiple)
    assert.same({ true, false }, fields[7].required_options)
  end)

  it('gathers what belongs above a field onto that field', function()
    if not fixture() then
      return
    end
    local found = assert(issue_template('Feature request'))
    assert.is_nil(found.guidance[0])
    assert.is_truthy(found.guidance[1]:find('Before you start', 1, true))
    assert.is_truthy(found.guidance[1]:find('One line, in the imperative.', 1, true))
    assert.equals('Optional on purpose, so a reader sees a false requirement.', found.guidance[2])
  end)

  it('takes the header github would apply', function()
    if not fixture() then
      return
    end
    local found = assert(issue_template('Feature request'))
    assert.equals('[feature]: ', found.title)
    assert.same({ 'enhancement', 'needs-triage' }, found.labels)
    assert.same({ 'barrettruth' }, found.assignees)
  end)
end)

describe('what a template is called', function()
  it('prefers the name it gave itself', function()
    if not fixture() then
      return
    end
    local names = {}
    for _, found in ipairs(template.all('issues', FIXTURE)) do
      names[#names + 1] = found.name
    end
    assert.same({ 'Feature request', 'Question', 'Bug report' }, names)
  end)

  it('makes one from the filename when there is none', function()
    if not fixture() then
      return
    end
    assert.equals('Pull Request Template', template.all('prs', FIXTURE)[1].name)
  end)
end)

describe('when a form cannot be read', function()
  it('says so instead of pretending there was no template', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/.github/ISSUE_TEMPLATE', 'p')
    vim.fn.writefile({ '' }, dir .. '/.git')
    vim.fn.writefile(
      { 'name: X', 'body:', '  - type: input' },
      dir .. '/.github/ISSUE_TEMPLATE/a.yml'
    )

    local real = vim.treesitter.get_string_parser
    vim.treesitter.get_string_parser = function()
      error('No parser for language "yaml"')
    end
    local found, err = template.all('issues', dir)
    vim.treesitter.get_string_parser = real

    assert.equals(0, #found)
    assert.is_truthy(err and err:find('yaml', 1, true))
    vim.fn.delete(dir, 'rf')
  end)
end)

describe('guidance in a form', function()
  --- @param body string[]
  --- @return forge.Template
  local function parse(body)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/.github/ISSUE_TEMPLATE', 'p')
    vim.fn.writefile({ '' }, dir .. '/.git')
    vim.fn.writefile(body, dir .. '/.github/ISSUE_TEMPLATE/a.yml')
    local found = template.all('issues', dir)[1]
    vim.fn.delete(dir, 'rf')
    return found
  end

  it('belongs to the field it comes before, not the one behind it', function()
    local found = assert(parse({
      'name: X',
      'description: d',
      'body:',
      '  - type: input',
      '    attributes:',
      '      label: First',
      '  - type: markdown',
      '    attributes:',
      '      value: between the two',
      '  - type: input',
      '    attributes:',
      '      label: Second',
    }))
    assert.equals(2, #found.fields)
    assert.is_nil(found.guidance[1])
    assert.equals('between the two', found.guidance[2])
  end)

  it('keeps a block and a description that share a field', function()
    local found = assert(parse({
      'name: X',
      'description: d',
      'body:',
      '  - type: markdown',
      '    attributes:',
      '      value: read this',
      '  - type: input',
      '    attributes:',
      '      label: First',
      '      description: and this',
    }))
    assert.equals('read this\n\nand this', found.guidance[1])
  end)
end)
