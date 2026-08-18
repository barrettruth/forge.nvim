local uri = require('forge.uri')

describe('uri.parse', function()
  it('reads every form it writes', function()
    for _, name in ipairs({
      'forge://github.com/neovim/neovim/issues',
      'forge://github.com/neovim/neovim/issues/41310',
    }) do
      assert.equals(name, uri.tostring(assert(uri.parse(name))))
    end
  end)

  it('tells a list from an item by whether it is numbered', function()
    assert.equals(41310, assert(uri.parse('forge://github.com/a/b/issues/41310')).number)
    assert.is_nil(assert(uri.parse('forge://github.com/a/b/issues')).number)
  end)

  it('refuses what it cannot address', function()
    for _, bad in ipairs({
      'forge://',
      'forge://owner',
      'forge://owner/repo',
      'forge://owner/repo/bogus',
      'forge://owner/repo/issues/closed',
      'forge://owner/repo/issues/abc',
      'forge://owner/repo/issues/27/extra',
      'https://github.com/neovim/neovim/issues/1',
      'not a uri at all',
    }) do
      assert.is_nil(uri.parse(bad), bad .. ' should not parse')
    end
  end)
end)

describe('a search', function()
  it('is what anything forge cannot otherwise name means', function()
    local t = assert(uri.resolve('label:bug is:open', 'issues'))
    assert.equals('label:bug is:open', t.query)
    assert.is_nil(t.number)
  end)

  it('never swallows a form that names something', function()
    for _, target in ipairs({ '41310', '#41310', 'a/b', 'a/b#1', 'forge://github.com/a/b/issues' }) do
      assert.is_nil(assert(uri.resolve(target, 'issues')).query, target)
    end
  end)

  it('survives being written to a name and read back', function()
    for _, query in ipairs({
      'label:bug is:open',
      'label:"good first issue"',
      'author:@me -label:lsp',
      'label:"unicode  \u{1F4A9}"',
      '100% of it',
    }) do
      local u = assert(uri.of('a/b', { collection = 'issues', query = query }))
      local name = uri.tostring(u)
      assert.equals(query, assert(uri.parse(name), name).query)
    end
  end)

  it('keeps out of a name what a command line would eat', function()
    local u = assert(uri.of('a/b', { collection = 'issues', query = 'a % and a # and a space' }))
    local name = uri.tostring(u)
    assert.is_nil(name:find('[ #]'), name)
    assert.equals('forge://github.com/a/b/issues?q=a%20%25%20and%20a%20%23%20and%20a%20space', name)
  end)
end)

describe('uri.resolve', function()
  it('accepts every form that carries a repository', function()
    local cases = {
      ['neovim/neovim'] = 'forge://github.com/neovim/neovim/issues',
      ['neovim/neovim#41310'] = 'forge://github.com/neovim/neovim/issues/41310',
      ['https://github.com/neovim/neovim/issues'] = 'forge://github.com/neovim/neovim/issues',
      ['https://github.com/neovim/neovim/issues/41310'] = 'forge://github.com/neovim/neovim/issues/41310',
    }
    for target, want in pairs(cases) do
      local got, err = uri.resolve(target, 'issues')
      assert.is_nil(err, target .. ' -> ' .. tostring(err))
      assert.equals(want, uri.tostring(assert(got, target)))
    end
  end)

  it('leaves the repository to gh when the target named none', function()
    for _, target in ipairs({ '', '41310', '#41310' }) do
      local got = assert(uri.resolve(target, 'issues'), target)
      assert.is_nil(got.owner, target .. ' should not name an owner')
      assert.is_nil(got.repo, target .. ' should not name a repo')
    end
  end)

  it('never shells out, so it cannot fail for want of a remote', function()
    local ran = false
    local real = vim.system
    --- @diagnostic disable-next-line: duplicate-set-field
    vim.system = function(...)
      ran = true
      return real(...)
    end
    local got, err = uri.resolve('', 'issues')
    vim.system = real

    assert.is_false(ran)
    assert.is_nil(err)
    assert.is_not_nil(got)
  end)

  it('takes a bare number as a number, whichever command asked', function()
    assert.equals(41310, assert(uri.resolve('41310', 'issues')).number)
    assert.equals(41310, assert(uri.resolve('#41310', 'prs')).number)
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

describe('the referent of a bare command', function()
  it('is the issue list, because nothing identifies the current issue', function()
    local t = assert(uri.resolve('', 'issues'))
    assert.is_nil(t.head)
    assert.is_nil(t.number)
    assert.is_nil(t.state)
  end)

  it('is the pull request list, the same as it is for issues', function()
    local t = assert(uri.resolve('', 'prs'))
    assert.equals('prs', t.collection)
    assert.is_nil(t.number)
    assert.is_nil(t.state)
  end)

  it('is the list again once a repository is named, which is not "here"', function()
    local t = assert(uri.resolve('neovim/neovim', 'prs'))
    assert.equals('neovim/neovim', t.project)
    assert.is_nil(t.number)
  end)
end)

describe('uri.of', function()
  it('names a view after the repository github answered for', function()
    local t = { collection = 'issues', number = 41310 }
    assert.equals(
      'forge://github.com/neovim/neovim/issues/41310',
      uri.tostring(assert(uri.of('neovim/neovim', t)))
    )
  end)

  it("prefers github's spelling to the one that was typed", function()
    local t = { collection = 'issues', project = 'Neovim/Neovim' }
    assert.equals(
      'forge://github.com/neovim/neovim/issues',
      uri.tostring(assert(uri.of('neovim/neovim', t)))
    )
  end)

  it('has no name to give when github named nothing', function()
    assert.is_nil(uri.of(nil, { collection = 'issues' }))
    assert.is_nil(uri.of('', { collection = 'issues' }))
    assert.is_nil(uri.of('neovim', { collection = 'issues' }))
  end)
end)

describe('gh.slug', function()
  local gh = require('forge.gh')

  it('hands gh its own placeholders when no repository was named', function()
    local owner, repo = gh.slug({ collection = 'issues' })
    assert.equals('{owner}', owner)
    assert.equals('{repo}', repo)
  end)

  it('sends what the target named when it named one', function()
    local owner, repo = gh.slug({ collection = 'issues', project = 'neovim/neovim' })
    assert.equals('neovim', owner)
    assert.equals('neovim', repo)
  end)
end)

describe('uri for pull requests', function()
  it('uses our own word, and the same grammar as issues', function()
    for _, name in ipairs({
      'forge://github.com/neovim/neovim/prs',
      'forge://github.com/neovim/neovim/prs/41138',
    }) do
      assert.equals(name, uri.tostring(assert(uri.parse(name))))
    end
  end)

  it('believes a target that names its own collection', function()
    assert.equals('prs', assert(uri.resolve('forge://github.com/a/b/prs/1', 'issues')).collection)
    assert.equals(
      'issues',
      assert(uri.resolve('forge://github.com/a/b/issues/1', 'prs')).collection
    )
    assert.equals('prs', assert(uri.resolve('https://github.com/a/b/pull/1', 'issues')).collection)
  end)

  it('lets the caller decide only for a bare number', function()
    assert.equals('prs', assert(uri.resolve('a/b#1', 'prs')).collection)
    assert.equals('issues', assert(uri.resolve('a/b#1', 'issues')).collection)
  end)

  it('refuses a collection it does not know', function()
    assert.is_nil(uri.parse('forge://github.com/a/b/commits'))
    assert.is_nil(uri.parse('forge://github.com/a/b/commits/1'))
  end)
end)

describe('view.wants_window', function()
  local view = require('forge.view')

  it('sees every modifier that asks for a window', function()
    assert.is_true(view.wants_window({ split = 'botright' }))
    assert.is_true(view.wants_window({ vertical = true }))
    assert.is_true(view.wants_window({ horizontal = true }))
    assert.is_true(view.wants_window({ tab = 0 }))
    assert.is_true(view.wants_window({ tab = 2 }))
  end)

  it('is not fooled by the shape neovim reports when there are none', function()
    assert.is_false(view.wants_window())
    assert.is_false(view.wants_window({}))
    assert.is_false(view.wants_window({ split = '', vertical = false, tab = -1 }))
    assert.is_false(view.wants_window({ silent = true, tab = -1 }))
  end)
end)

describe('the change you are on', function()
  it('is spelled @, and only a pull request has one', function()
    local t = assert(uri.resolve('@', 'prs'))
    assert.is_true(t.head)
    assert.is_nil(t.number)

    local none, err = uri.resolve('@', 'issues')
    assert.is_nil(none)
    assert.is_truthy(err)
  end)

  it('is not what a bare command means', function()
    assert.is_nil(assert(uri.resolve('', 'prs')).head)
  end)
end)

describe('uri.parse on a path that is not two segments', function()
  it('keeps every group a gitlab project nests under', function()
    local u = assert(uri.parse('forge://gitlab.com/g/sub/deep/proj/prs/2'))
    assert.equals('gitlab.com', u.host)
    assert.equals('g/sub/deep/proj', u.project)
    assert.equals('prs', u.collection)
    assert.equals(2, u.number)
  end)

  it('reads the collection off the end, so a project may be named after one', function()
    local u = assert(uri.parse('forge://gitlab.com/group/issues/prs/7'))
    assert.equals('group/issues', u.project)
    assert.equals('prs', u.collection)
  end)

  it('round-trips what it parsed', function()
    local name = 'forge://gitlab.com/g/sub/proj/prs/2'
    assert.equals(name, uri.tostring(assert(uri.parse(name))))
  end)
end)

describe('uri.web', function()
  it('reads a gitlab merge request, nested groups and all', function()
    local t = assert(uri.web('https://gitlab.com/gitlab-org/ci-cd/runner/-/merge_requests/12'))
    assert.equals('gitlab.com', t.host)
    assert.equals('gitlab-org/ci-cd/runner', t.project)
    assert.equals('prs', t.collection)
    assert.equals(12, t.number)
  end)

  it('drops the anchor a note is linked by', function()
    local t = assert(uri.web('https://gitlab.com/g/p/-/issues/12#note_5'))
    assert.equals(12, t.number)
    assert.equals('issues', t.collection)
  end)

  it('still reads github, which separates nothing', function()
    local t = assert(uri.web('https://github.com/neovim/neovim/pull/41370'))
    assert.equals('github.com', t.host)
    assert.equals('neovim/neovim', t.project)
    assert.equals('prs', t.collection)
  end)

  it('names whatever host it was given, leaving the choice of backend to come', function()
    local t = assert(uri.web('https://example.com/a/b/issues/1'))
    assert.equals('example.com', t.host)
  end)

  it('is nothing for an address naming no collection', function()
    assert.is_nil(uri.web('https://github.com/neovim/neovim'))
  end)
end)
