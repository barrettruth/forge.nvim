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

  it('keeps guidance apart from the fields it belongs above', function()
    if not fixture() then
      return
    end
    local found = assert(issue_template('Feature request'))
    assert.is_truthy(found.guidance[0]:find('Before you start', 1, true))
    assert.equals('One line, in the imperative.', found.guidance[1])
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
