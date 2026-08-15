local gh = require('forge.gh')
local issue = require('forge.issue')
local pr = require('forge.pr')

local NOW = os.date('!%Y-%m-%dT%H:%M:%SZ') --[[@as string]]

--- Answer the next request with `data`, whatever was asked.
--- @param data table
--- @param fn fun()
local function answering(data, fn)
  local real = gh.graphql
  --- @diagnostic disable-next-line: duplicate-set-field
  gh.graphql = function(_, on_done)
    on_done(data)
  end
  local ok, err = pcall(fn)
  gh.graphql = real
  assert(ok, err)
end

--- @return string[] lines, forge.BufVar info
local function drawn()
  local buf = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.b[buf].forge
end

describe('an issue github answered with', function()
  local function response(over)
    return {
      repository = {
        nameWithOwner = 'neovim/neovim',
        issue = vim.tbl_extend('force', {
          number = 41310,
          title = 'Something broke',
          state = 'OPEN',
          body = 'Line one\r\nLine two',
          createdAt = NOW,
          author = { login = 'someone' },
          authorAssociation = 'CONTRIBUTOR',
          labels = { totalCount = 2, nodes = { { name = 'bug' }, { name = 'ui' } } },
          comments = {
            totalCount = 1,
            nodes = {
              {
                author = { login = 'other' },
                authorAssociation = 'NONE',
                createdAt = NOW,
                body = 'a reply',
              },
            },
          },
        }, over or {}),
      },
    }
  end

  it('becomes a markdown document with a header and a conversation', function()
    answering(response(), function()
      issue.show({ owner = 'neovim', repo = 'neovim', collection = 'issues', number = 41310 }, {})
    end)

    local lines = drawn()
    assert.same({
      '# Something broke',
      '',
      '- Author: someone (CONTRIBUTOR)',
      '- State: OPEN, opened today',
      '- Labels: bug, ui',
      '',
      'Line one',
      'Line two',
      '',
      '## Comments (1)',
      '',
      '### other (NONE) — today',
      '',
      'a reply',
    }, lines)
  end)

  it('is filed under the name github spelled, not the one asked for', function()
    answering(response(), function()
      issue.show({ owner = 'Neovim', repo = 'Neovim', collection = 'issues', number = 41310 }, {})
    end)
    assert.equals(
      'forge://neovim/neovim/issues/41310',
      vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    )
  end)

  it('tells the winbar what it is', function()
    answering(response(), function()
      issue.show({ owner = 'neovim', repo = 'neovim', collection = 'issues', number = 41310 }, {})
    end)

    local _, info = drawn()
    assert.equals('item', info.kind)
    assert.equals('ISSUE', info.label)
    assert.equals('#41310', info.tag)
    assert.equals('OPEN', info.state)
    assert.equals('OkMsg', info.state_hl)
    assert.equals('Something broke', info.title)
    assert.equals('', info.badges)
  end)

  it('leaves out a label line when there are no labels', function()
    answering(response({ labels = { totalCount = 0, nodes = {} } }), function()
      issue.show({ owner = 'neovim', repo = 'neovim', collection = 'issues', number = 41310 }, {})
    end)
    for _, line in ipairs(drawn()) do
      assert.is_nil(line:match('^%- Labels:'))
    end
  end)

  it('calls an author nobody claims a ghost', function()
    local anonymous = response()
    anonymous.repository.issue.author = nil
    anonymous.repository.issue.authorAssociation = nil

    answering(anonymous, function()
      issue.show({ owner = 'neovim', repo = 'neovim', collection = 'issues', number = 41310 }, {})
    end)
    assert.equals('- Author: ghost (NONE)', drawn()[3])
  end)
end)

describe('a pull request github answered with', function()
  local function response(over)
    return {
      repository = {
        nameWithOwner = 'neovim/neovim',
        pullRequest = vim.tbl_extend('force', {
          number = 41138,
          title = 'Fix the thing',
          state = 'MERGED',
          body = 'the body',
          createdAt = NOW,
          isDraft = false,
          additions = 10,
          deletions = 2,
          changedFiles = 3,
          baseRefName = 'master',
          headRefName = 'fix-the-thing',
          author = { login = 'someone' },
          authorAssociation = 'MEMBER',
          labels = { totalCount = 0, nodes = {} },
          comments = { totalCount = 0, nodes = {} },
        }, over or {}),
      },
    }
  end

  local function show()
    pr.show({ owner = 'neovim', repo = 'neovim', collection = 'prs', number = 41138 }, {})
  end

  it('says which branches it joins, under the state', function()
    answering(response(), show)
    assert.same({
      '# Fix the thing',
      '',
      '- Author: someone (MEMBER)',
      '- State: MERGED, opened today',
      '- Branch: fix-the-thing into master',
      '',
      'the body',
    }, drawn())
  end)

  it('carries its diffstat and its branches into the buffer variable', function()
    answering(response(), show)
    local _, info = drawn()
    assert.equals('PR', info.label)
    assert.equals('MERGED', info.state)
    assert.equals('Special', info.state_hl)
    assert.equals(' %#Added#+10%* %#Removed#-2%*', info.badges)
    assert.equals('master', info.base)
    assert.equals('fix-the-thing', info.head)
  end)

  it('shows a draft as a draft, not as the open it really is', function()
    answering(response({ state = 'OPEN', isDraft = true }), show)
    local _, info = drawn()
    assert.equals('DRAFT', info.state)
    assert.equals('Normal', info.state_hl)
  end)
end)

describe('a list github answered with', function()
  local function response(nodes, over)
    return {
      repository = {
        nameWithOwner = 'neovim/neovim',
        issues = vim.tbl_extend('force', {
          totalCount = #nodes,
          pageInfo = { hasNextPage = false },
          nodes = nodes,
        }, over or {}),
      },
    }
  end

  local function show(state)
    issue.show({ owner = 'neovim', repo = 'neovim', collection = 'issues', state = state }, {})
  end

  it('lines the numbers up so the titles start in one column', function()
    answering(
      response({ { number = 7, title = 'short' }, { number = 1234, title = 'long' } }),
      function()
        show('OPEN')
      end
    )
    assert.same({ '#7    short', '#1234 long' }, drawn())
  end)

  it('marks each number rather than matching one out of the title afterwards', function()
    answering(response({ { number = 7, title = 'a title mentioning #12' } }), function()
      show('OPEN')
    end)
    local buf = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_get_namespaces()['forge']
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    assert.equals(1, #marks)
    assert.equals(0, marks[1][2])
    assert.equals(0, marks[1][3])
    assert.equals(2, marks[1][4].end_col)
    assert.equals('Tag', marks[1][4].hl_group)
  end)

  it('says so, once, when a half of the collection is empty', function()
    answering(response({}), function()
      show('CLOSED')
    end)
    assert.same({ 'No closed issues.' }, drawn())
  end)

  it('counts the pages from the total, not from what came back', function()
    answering(response({ { number = 1, title = 'a' } }, { totalCount = 250 }), function()
      show('OPEN')
    end)
    local _, info = drawn()
    assert.equals('list', info.kind)
    assert.equals('ISSUES', info.label)
    assert.equals('neovim/neovim', info.repo)
    assert.equals('open', info.state)
    assert.equals('1/3', info.pages)
    assert.equals('250', info.total)
  end)
end)
