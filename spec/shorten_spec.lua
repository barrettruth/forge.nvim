local github = require('forge.github')
local glab = require('forge.glab')
local text = require('forge.text')

local HERE = 'barrettruth/forge.nvim'
local THERE = 'gitlab-org/cli'

describe('an address github would draw short', function()
  local function short(url)
    return github.shorten(url, HERE)
  end

  it('names the repository it is not in', function()
    assert.equal('neovim/neovim#41138', short('https://github.com/neovim/neovim/issues/41138'))
    assert.equal('neovim/neovim#41370', short('https://github.com/neovim/neovim/pull/41370'))
    assert.equal('neovim/neovim#41138', short('https://github.com/neovim/neovim/discussions/41138'))
  end)

  it('drops the repository the view already names', function()
    assert.equal('#1', short('https://github.com/barrettruth/forge.nvim/issues/1'))
    assert.equal('#1', short('https://github.com/barrettruth/forge.nvim/issues/1/'))
  end)

  it('keeps it for another repository of the same owner', function()
    assert.equal('barrettruth/ci.nvim#1', short('https://github.com/barrettruth/ci.nvim/issues/1'))
  end)

  it('says which of a comment and a review a fragment names', function()
    local at = 'https://github.com/neovim/neovim/pull/41370'
    assert.equal('neovim/neovim#41370 (comment)', short(at .. '#issuecomment-25'))
    assert.equal('neovim/neovim#41370 (comment)', short(at .. '#discussion_r25'))
    assert.equal('neovim/neovim#41370 (comment)', short(at .. '#issue-25'))
    assert.equal('neovim/neovim#41370 (review)', short(at .. '#pullrequestreview-25'))
  end)

  it('takes a commit and a comparison to seven characters and a range', function()
    local sha = '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b'
    assert.equal('neovim/neovim@1a2b3c4', short('https://github.com/neovim/neovim/commit/' .. sha))
    assert.equal('1a2b3c4', short('https://github.com/barrettruth/forge.nvim/commit/' .. sha))
    assert.equal(
      'neovim/neovim@master...release-0.11',
      short('https://github.com/neovim/neovim/compare/master...release-0.11')
    )
    assert.equal(
      'main...dev',
      short('https://github.com/barrettruth/forge.nvim/compare/main...dev')
    )
  end)

  it('ignores a query github ignores', function()
    assert.equal('neovim/neovim#1', short('https://github.com/neovim/neovim/issues/1?foo=bar'))
  end)

  it('leaves alone every address github leaves alone', function()
    for _, url in ipairs({
      'https://github.com/neovim/neovim/pull/1/files',
      'https://github.com/neovim/neovim/blob/master/README.md',
      'https://github.com/neovim/neovim/tree/master',
      'https://github.com/neovim/neovim/releases/tag/v0.11.0',
      'https://github.com/neovim/neovim/milestone/1',
      'https://github.com/neovim/neovim/labels/bug',
      'https://github.com/neovim/neovim/wiki/Home',
      'https://github.com/orgs/neovim/projects/1',
      'https://github.com/neovim/neovim/issues/',
      'https://github.com/neovim/neovim',
      'https://github.com/neovim',
      'http://github.com/neovim/neovim/issues/1',
    }) do
      assert.is_nil(short(url), url)
    end
  end)
end)

describe('an address gitlab would draw short', function()
  local function short(url)
    return glab.shorten(url, THERE)
  end

  it('writes its own sigil for each collection', function()
    assert.equal('#8022', short('https://gitlab.com/gitlab-org/cli/-/issues/8022'))
    assert.equal('#6', short('https://gitlab.com/gitlab-org/cli/-/work_items/6'))
    assert.equal('!123', short('https://gitlab.com/gitlab-org/cli/-/merge_requests/123'))
  end)

  it('drops the namespace both projects share', function()
    assert.equal('gitlab#8022', short('https://gitlab.com/gitlab-org/gitlab/-/issues/8022'))
  end)

  it('keeps the whole path of a project under another namespace', function()
    assert.equal('gnachman/iterm2#1', short('https://gitlab.com/gnachman/iterm2/-/issues/1'))
    assert.equal('a/b/c#1', short('https://gitlab.com/a/b/c/-/issues/1'))
  end)

  it('names the tabs gitlab names', function()
    local at = 'https://gitlab.com/gitlab-org/cli/-/merge_requests/123'
    assert.equal('!123 (diffs)', short(at .. '/diffs'))
    assert.equal('!123 (commits)', short(at .. '/commits'))
    assert.equal('!123', short(at .. '/pipelines'))
  end)

  it('says a note is a comment without repeating its id', function()
    local at = 'https://gitlab.com/gitlab-org/cli/-/merge_requests/123'
    assert.equal('!123 (comment)', short(at .. '#note_2277571806'))
    assert.equal('!123 (diffs, comment)', short(at .. '/diffs#note_1'))
  end)

  it('answers for an epic against the group the view sits in', function()
    assert.equal('&1', short('https://gitlab.com/groups/gitlab-org/-/epics/1'))
    assert.equal('other&1', short('https://gitlab.com/groups/other/-/epics/1'))
  end)

  it('leaves alone every address gitlab leaves alone', function()
    for _, url in ipairs({
      'https://gitlab.com/gitlab-org/cli/-/commit/1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b',
      'https://gitlab.com/gitlab-org/cli/-/blob/main/README.md',
      'https://gitlab.com/gitlab-org/cli/-/pipelines/1',
      'https://gitlab.com/gitlab-org/cli/-/jobs/1',
      'https://gitlab.com/gitlab-org/cli/-/merge_requests/1/widget',
      'https://gitlab.com/gitlab-org/cli/-/issues/1/designs',
      'https://gitlab.com/gitlab-org/cli',
      'http://gitlab.com/gitlab-org/cli/-/issues/1',
    }) do
      assert.is_nil(short(url), url)
    end
  end)
end)

describe('a body holding an address of the forge that answered', function()
  before_each(function()
    text.host, text.project, text.shorten = 'github.com', HERE, github.shorten
  end)
  after_each(function()
    text.host, text.project, text.shorten = nil, nil, nil
  end)

  local function drawn(body)
    local lines, marks = {}, {}
    text.append_body(lines, marks, body)
    return lines, marks
  end

  it('is drawn as short as the forge draws it', function()
    local lines = drawn('Fixed by https://github.com/neovim/neovim/issues/41138 upstream.')
    assert.same({ 'Fixed by neovim/neovim#41138 upstream.' }, lines)
  end)

  it('leaves the punctuation prose wrapped it in', function()
    local lines = drawn('Also (https://github.com/barrettruth/forge.nvim/pull/2#issuecomment-1).')
    assert.same({ 'Also (#2 (comment)).' }, lines)
  end)

  it('keeps the address on the mark, for gx', function()
    local _, marks = drawn('see https://github.com/neovim/neovim/issues/41138')
    assert.same({
      {
        row = 0,
        col = 4,
        end_col = 23,
        group = { 'Tag', '@markup.link' },
        url = 'https://github.com/neovim/neovim/issues/41138',
      },
    }, marks)
  end)

  it('shortens every address on one line', function()
    local lines = drawn(
      'a https://github.com/neovim/neovim/issues/1 b https://github.com/neovim/neovim/pull/2 c'
    )
    assert.same({ 'a neovim/neovim#1 b neovim/neovim#2 c' }, lines)
  end)

  it('leaves an address the forge itself leaves whole', function()
    local body = 'see https://github.com/neovim/neovim/pull/1/files here'
    assert.same({ body }, (drawn(body)))
  end)

  it('leaves an address of another host alone', function()
    local body = 'see https://gitlab.com/a/b/-/issues/1 here'
    assert.same({ body }, (drawn(body)))
  end)

  it('leaves a fence and a code span alone', function()
    local at = 'https://github.com/neovim/neovim/issues/1'
    assert.same({ 'in `' .. at .. '` here' }, (drawn('in `' .. at .. '` here')))
    assert.same({ '```', at, '```' }, (drawn('```\n' .. at .. '\n```')))
  end)

  it('is left whole when no forge answered for the view', function()
    text.shorten, text.project = nil, nil
    local body = 'see https://github.com/neovim/neovim/issues/1'
    assert.same({ body }, (drawn(body)))
  end)
end)
