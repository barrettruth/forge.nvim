local ref = require('forge.ref')
local view = require('forge.view')

--- Put one line in a scratch buffer and the cursor somewhere on it.
--- @param line string
--- @param col integer zero-based, as |nvim_win_set_cursor()| counts
local function reading(line, col)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, col })
end

--- Stand in the view a reference is being read from.
--- @param collection forge.Collection
local function inside(collection)
  local u = { owner = 'a', repo = 'b', collection = collection, number = 1, state = 'OPEN' }
  local buf = view.render(u, { 'body' }, {
    kind = 'item',
    label = 'ISSUE',
    repo = 'a/b',
    state = 'OPEN',
    state_hl = 'OkMsg',
    tag = '#1',
    title = '',
    badges = '',
  })
  vim.api.nvim_win_set_buf(0, buf)
end

describe('ref.at_cursor', function()
  it('leaves behind the punctuation prose wraps a reference in', function()
    for _, case in ipairs({
      { 'closes #123 now', 8 },
      { 'closes (#123) now', 9 },
      { 'closes #123. Then', 8 },
      { 'closes #123, and', 8 },
      { 'closes `#123` now', 9 },
      { 'closes "#123" now', 9 },
      { 'see [#123](https://github.com/a/b/issues/123)', 6 },
    }) do
      reading(case[1], case[2])
      assert.equals('#123', ref.at_cursor(), case[1])
    end
  end)

  it('answers for either half of a markdown link', function()
    reading('see [#123](https://github.com/a/b/issues/123)', 15)
    assert.equals('https://github.com/a/b/issues/123', ref.at_cursor())
  end)

  it('keeps a reference that carries its own repository', function()
    reading('blocked by neovim/neovim#41138 here', 15)
    assert.equals('neovim/neovim#41138', ref.at_cursor())

    reading('at forge://neovim/neovim/prs/41138 there', 12)
    assert.equals('forge://neovim/neovim/prs/41138', ref.at_cursor())
  end)

  it('does not read a url github would not have linked', function()
    reading('at https://example.com/a/b/issues/1 there', 10)
    assert.is_nil(ref.at_cursor())
  end)

  it('refuses a github url that names no item, which most of them do not', function()
    for _, case in ipairs({
      { 'shot https://github.com/user-attachments/assets/9d1d-4c is here', 12 },
      { 'see https://github.com/o/r/blob/main/README.md there', 12 },
      { 'in https://github.com/o/r/releases/tag/v1.0 now', 12 },
      { 'over at https://github.com/o/r itself', 16 },
    }) do
      reading(case[1], case[2])
      assert.is_nil(ref.at_cursor(), case[1])
    end
  end)

  it('says so when the cursor is on nothing', function()
    reading('   ', 1)
    local token, err = ref.at_cursor()
    assert.is_nil(token)
    assert.equals('nothing under the cursor', err)
  end)

  it('refuses what is not a reference, and says what it saw', function()
    reading('an ordinary word here', 3)
    local token, err = ref.at_cursor()
    assert.is_nil(token)
    assert.equals('not a reference: ordinary', err)
  end)

  it('refuses a bare owner/repo, because that is also a path', function()
    for _, case in ipairs({
      { 'see spec/helpers.lua for it', 9 },
      { 'over in neovim/neovim there', 12 },
    }) do
      reading(case[1], case[2])
      assert.is_nil(ref.at_cursor(), case[1])
    end
  end)

  it('refuses a mention, which <cfile> hands over without its @', function()
    reading('cc @barrettruth thanks', 6)
    assert.is_nil(ref.at_cursor())

    reading('cc @org/team-name please', 8)
    assert.is_nil(ref.at_cursor())
  end)
end)

describe('ref.include', function()
  it('gives a bare number the repository of the view it was read in', function()
    inside('issues')
    assert.equals('forge://a/b/issues/123', ref.include('#123'))
  end)

  it('reads a bare number as the collection it was read in', function()
    inside('prs')
    assert.equals('forge://a/b/prs/123', ref.include('#123'))
  end)

  it('believes a reference that names its own repository', function()
    inside('issues')
    assert.equals('forge://neovim/neovim/issues/7', ref.include('neovim/neovim#7'))
    assert.equals('forge://o/r/prs/9', ref.include('https://github.com/o/r/pull/9'))
    assert.equals('forge://o/r/issues/closed', ref.include('forge://o/r/issues/closed'))
  end)

  it('hands back anything it cannot address, so gf still opens a file', function()
    inside('issues')
    for _, fname in ipairs({ 'spec/helpers.lua', 'lua/forge/ref.lua', './notes.md', 'word' }) do
      assert.equals(fname, ref.include(fname), fname)
    end
  end)

  it('hands back a github url that names no item, rather than its list', function()
    inside('issues')
    for _, fname in ipairs({
      'https://github.com/user-attachments/assets/9d1d-4c',
      'https://github.com/o/r/blob/main/README.md',
      'https://github.com/o/r',
    }) do
      assert.equals(fname, ref.include(fname), fname)
    end
  end)

  it('has no repository to lend outside a view, and lends none', function()
    reading('closes #123 now', 8)
    assert.equals('#123', ref.include('#123'))
  end)
end)

describe('a rendered buffer', function()
  it("points 'includeexpr' at forge, so gf follows a reference", function()
    local u = { owner = 'a', repo = 'b', collection = 'issues', number = 5, state = 'OPEN' }
    local buf = view.render(u, { 'closes #123' }, {
      kind = 'item',
      label = 'ISSUE',
      repo = 'a/b',
      state = 'OPEN',
      state_hl = 'OkMsg',
      tag = '#5',
      title = '',
      badges = '',
    })
    assert.equals('v:lua.require("forge.ref").include(v:fname)', vim.bo[buf].includeexpr)
  end)
end)
