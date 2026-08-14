local uri = require('forge.uri')

--- Resolving needs a repository for the forms that do not carry one, and the
--- origin remote is not ours to depend on in a test.
local function stub_origin(owner, repo)
  local real = uri.origin
  uri.origin = function()
    return owner, repo
  end
  return function()
    uri.origin = real
  end
end

describe('uri.parse', function()
  it('reads every form it writes', function()
    for _, name in ipairs({
      'forge://neovim/neovim/issues',
      'forge://neovim/neovim/issues/closed',
      'forge://neovim/neovim/issues/41310',
    }) do
      assert.equals(name, uri.tostring(assert(uri.parse(name))))
    end
  end)

  it('tells a number from a state', function()
    assert.equals(41310, assert(uri.parse('forge://a/b/issues/41310')).number)
    assert.is_nil(assert(uri.parse('forge://a/b/issues/closed')).number)
    assert.equals('CLOSED', assert(uri.parse('forge://a/b/issues/closed')).state)
  end)

  it('refuses what it cannot address', function()
    for _, bad in ipairs({
      'forge://',
      'forge://owner',
      'forge://owner/repo',
      'forge://owner/repo/bogus',
      'forge://owner/repo/issues/abc',
      'forge://owner/repo/issues/27/extra',
      'https://github.com/neovim/neovim/issues/1',
      'not a uri at all',
    }) do
      assert.is_nil(uri.parse(bad), bad .. ' should not parse')
    end
  end)
end)

describe('uri.resolve', function()
  it('accepts the forms a person would type', function()
    local restore = stub_origin('barrettruth', 'forge.nvim')
    local cases = {
      ['41310'] = 'forge://barrettruth/forge.nvim/issues/41310',
      ['#41310'] = 'forge://barrettruth/forge.nvim/issues/41310',
      [''] = 'forge://barrettruth/forge.nvim/issues',
      ['neovim/neovim'] = 'forge://neovim/neovim/issues',
      ['neovim/neovim#41310'] = 'forge://neovim/neovim/issues/41310',
      ['https://github.com/neovim/neovim/issues'] = 'forge://neovim/neovim/issues',
      ['https://github.com/neovim/neovim/issues/41310'] = 'forge://neovim/neovim/issues/41310',
      ['forge://neovim/neovim/issues/closed'] = 'forge://neovim/neovim/issues/closed',
    }
    for target, want in pairs(cases) do
      local got, err = uri.resolve(target, 'issues')
      assert.is_nil(err, target .. ' -> ' .. tostring(err))
      assert.equals(want, uri.tostring(assert(got, target)))
    end
    restore()
  end)

  it('reports one error and no uri for a malformed forge uri', function()
    local got, err = uri.resolve('forge://owner/repo/bogus', 'issues')
    assert.is_nil(got)
    assert.equals('not a forge uri: forge://owner/repo/bogus', err)
  end)

  it('reports no error when it succeeds', function()
    local got, err = uri.resolve('neovim/neovim#1', 'issues')
    assert.is_not_nil(got)
    assert.is_nil(err)
  end)
end)

describe('uri.web', function()
  it('is github.com with the scheme swapped, except for a filter', function()
    local cases = {
      ['forge://neovim/neovim/issues'] = 'https://github.com/neovim/neovim/issues',
      ['forge://neovim/neovim/issues/41310'] = 'https://github.com/neovim/neovim/issues/41310',
      ['forge://neovim/neovim/issues/closed'] = 'https://github.com/neovim/neovim/issues?q=is%3Aissue+is%3Aclosed',
    }
    for name, want in pairs(cases) do
      assert.equals(want, uri.web(assert(uri.parse(name))))
    end
  end)
end)

describe('uri for pull requests', function()
  it('uses the same grammar as issues', function()
    for _, name in ipairs({
      'forge://neovim/neovim/pulls',
      'forge://neovim/neovim/pulls/closed',
      'forge://neovim/neovim/pulls/41138',
    }) do
      assert.equals(name, uri.tostring(assert(uri.parse(name))))
    end
  end)

  it('follows github into the singular only on the web', function()
    assert.equals(
      'https://github.com/neovim/neovim/pull/41138',
      uri.web(assert(uri.parse('forge://neovim/neovim/pulls/41138')))
    )
    assert.equals(
      'https://github.com/neovim/neovim/pulls',
      uri.web(assert(uri.parse('forge://neovim/neovim/pulls')))
    )
  end)

  it('believes a target that names its own collection', function()
    assert.equals('pulls', assert(uri.resolve('forge://a/b/pulls/1', 'issues')).collection)
    assert.equals('issues', assert(uri.resolve('forge://a/b/issues/1', 'pulls')).collection)
    assert.equals(
      'pulls',
      assert(uri.resolve('https://github.com/a/b/pull/1', 'issues')).collection
    )
  end)

  it('lets the caller decide only for a bare number', function()
    assert.equals('pulls', assert(uri.resolve('a/b#1', 'pulls')).collection)
    assert.equals('issues', assert(uri.resolve('a/b#1', 'issues')).collection)
  end)

  it('refuses a collection it does not know', function()
    assert.is_nil(uri.parse('forge://a/b/commits'))
    assert.is_nil(uri.parse('forge://a/b/commits/1'))
  end)
end)
