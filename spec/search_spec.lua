local search = require('forge.search')

describe('completing a search', function()
  it('offers qualifiers until one is named', function()
    assert.same({ 'label:' }, search.complete('lab'))
    assert.same({ 'is:' }, search.complete('is'))
    assert.is_true(#search.complete('') > 20)
  end)

  it('offers a qualifier a closed set of values', function()
    assert.same({ 'is:open' }, search.complete('is:o'))
    assert.same({ 'no:label' }, search.complete('no:l'))
    assert.same({ 'sort:updated-asc', 'sort:updated-desc' }, search.complete('sort:up'))
    assert.same({ 'review:changes_requested' }, search.complete('review:c'))
  end)

  it('offers the only person it can know', function()
    assert.same({ 'author:@me' }, search.complete('author:'))
    assert.same({ 'review-requested:@me' }, search.complete('review-requested:@'))
  end)

  it('offers nothing it would have to ask github for', function()
    assert.same({}, search.complete('label:b'))
    assert.same({}, search.complete('milestone:'))
    assert.same({}, search.complete('created:2026'))
  end)

  it('keeps a negation, since github takes one on either kind', function()
    assert.same({ '-label:' }, search.complete('-lab'))
    assert.same({ '-author:@me' }, search.complete('-author:'))
    assert.same({ '-is:open' }, search.complete('-is:o'))
  end)

  it('says nothing inside a quoted value, where the word it is given is a fragment', function()
    assert.same({}, search.complete('fir'))
    assert.same({}, search.complete('issue"'))
  end)

  it('asks github for nothing while it does any of that', function()
    local ran = false
    local real = vim.system
    --- @diagnostic disable-next-line: duplicate-set-field
    vim.system = function(...)
      ran = true
      return real(...)
    end
    for _, lead in ipairs({ '', 'is:', 'label:b', '-author:@' }) do
      search.complete(lead)
    end
    vim.system = real
    assert.is_false(ran)
  end)
end)

describe('a query on the command line', function()
  before_each(function()
    vim.g.loaded_forge = nil
    vim.cmd('source ./plugin/forge.lua')
  end)

  local function given(cmdline)
    local issue = require('forge.issue')
    local real, got = issue.open, nil
    issue.open = function(target)
      got = target
    end
    vim.cmd(cmdline)
    issue.open = real
    return got
  end

  it('keeps a quoted value, which github asks for on any label of two words', function()
    assert.equals(
      'label:"good first issue" is:open',
      given([[Issue label:"good first issue" is:open]])
    )
  end)

  it("keeps the rest of what github's syntax spells with punctuation", function()
    assert.equals('-label:lsp author:@me', given([[Issue -label:lsp author:@me]]))
    assert.equals('label:a,b in:title', given([[Issue label:a,b in:title]]))
  end)
end)
