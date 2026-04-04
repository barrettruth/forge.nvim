vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

local forge = require('forge')
local discover = forge._discover_templates
local load_template = forge._load_template
local normalize = forge._normalize_body

local repo_root = vim.fn.getcwd()

describe('discover_templates', function()
  it('finds yaml templates and skips config.yaml', function()
    local result, templates = discover({ '.github/ISSUE_TEMPLATE/' }, repo_root)
    assert.is_nil(result)
    assert.is_table(templates)
    assert.equals(2, #templates)
    for _, t in ipairs(templates) do
      assert.is_not.equals('config.yaml', t.name)
    end
  end)

  it('returns sorted entries with display names from yaml', function()
    local _, templates = discover({ '.github/ISSUE_TEMPLATE/' }, repo_root)
    assert.equals('Bug Report', templates[1].display)
    assert.equals('Feature Request', templates[2].display)
  end)

  it('marks yaml entries correctly', function()
    local _, templates = discover({ '.github/ISSUE_TEMPLATE/' }, repo_root)
    for _, t in ipairs(templates) do
      assert.is_true(t.is_yaml)
    end
  end)

  it('returns single file directly as result', function()
    local result, templates = discover({ '.github/pull_request_template.md' }, repo_root)
    assert.is_table(result)
    assert.is_string(result.body)
    assert.truthy(result.body:match('Problem'))
    assert.is_nil(templates)
  end)

  it('returns nil for nonexistent paths', function()
    local result, templates = discover({ '.github/NONEXISTENT/' }, repo_root)
    assert.is_nil(result)
    assert.is_nil(templates)
  end)
end)

describe('load_template', function()
  it('loads a yaml template into TemplateResult', function()
    local _, templates = discover({ '.github/ISSUE_TEMPLATE/' }, repo_root)
    local bug = templates[1]
    local result = load_template(bug)
    assert.is_table(result)
    assert.equals('bug: ', result.title)
    assert.same({ 'bug' }, result.labels)
    assert.truthy(result.body:match('### Prerequisites'))
  end)

  it('loads a feature request template', function()
    local _, templates = discover({ '.github/ISSUE_TEMPLATE/' }, repo_root)
    local feat = templates[2]
    local result = load_template(feat)
    assert.equals('feat: ', result.title)
    assert.same({ 'enhancement' }, result.labels)
  end)
end)

describe('normalize_body', function()
  it('trims and collapses whitespace', function()
    assert.equals('a b c', normalize('  a   b\n  c  '))
  end)

  it('matches bodies differing only in whitespace', function()
    local a = '## Problem\n\n## Solution\n'
    local b = '## Problem\n\n\n## Solution'
    assert.equals(normalize(a), normalize(b))
  end)

  it('does not match different content', function()
    assert.is_not.equals(normalize('## Problem'), normalize('## Solution'))
  end)

  it('detects unchanged template title', function()
    local template_title = 'bug: '
    local user_title = 'bug: '
    assert.equals(normalize(template_title), normalize(user_title))
  end)

  it('allows modified title to pass', function()
    local template_title = 'bug: '
    local user_title = 'bug: login page crashes on submit'
    assert.is_not.equals(normalize(template_title), normalize(user_title))
  end)
end)
