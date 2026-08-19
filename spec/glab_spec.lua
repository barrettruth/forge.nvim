local glab = require('forge.glab')

local MR = {
  id = 520949156,
  iid = 2,
  project_id = 85501720,
  title = 'Change the third line',
  description = 'Touches `lib.txt`.',
  state = 'opened',
  created_at = '2026-08-18T22:33:34.784Z',
  web_url = 'https://gitlab.com/barrettruth/glab-fork-lab/-/merge_requests/2',
  source_branch = 'feat/one',
  target_branch = 'main',
  source_project_id = 85501720,
  target_project_id = 85501720,
  sha = '9ece12b1965a53639fc2b13c4c74bbdf3fbe1d7d',
  draft = false,
  detailed_merge_status = 'mergeable',
  has_conflicts = false,
  labels = { 'bug', 'ui' },
  assignees = { { username = 'barrettruth' } },
  reviewers = { { username = 'someone' } },
  author = { username = 'barrettruth' },
  head_pipeline = { status = 'failed' },
}

local ISSUE = {
  id = 197888235,
  iid = 1,
  title = 'Log view drops the last line',
  description = 'Expected the final line; got a blank.',
  state = 'opened',
  created_at = '2026-08-18T22:33:58.051Z',
  web_url = 'https://gitlab.com/barrettruth/glab-fork-lab/-/work_items/1',
  issue_type = 'issue',
  labels = {},
  assignees = {},
  author = { username = 'barrettruth' },
}

--- @param over table?
--- @return table
local function mr(over)
  return vim.tbl_extend('force', MR, over or {})
end

describe('the path gitlab addresses a project by', function()
  it('escapes the slashes a nested group path is spelled with', function()
    assert.equals(
      'gitlab-community%2Fgitlab-org%2Fcli',
      glab.path('gitlab-community/gitlab-org/cli')
    )
  end)

  it('leaves what a path may hold alone', function()
    assert.equals('barrettruth%2Fglab-fork-lab', glab.path('barrettruth/glab-fork-lab'))
    assert.equals('a.b_c~d', glab.path('a.b_c~d'))
  end)

  it("is glab's placeholder when nothing named a project", function()
    assert.equals(':fullpath', glab.path(nil))
    assert.equals(':fullpath', glab.path(''))
  end)
end)

describe('a merge request gitlab answered with', function()
  it('is numbered by its iid, never by the id that 404s on those routes', function()
    assert.equals(2, glab.node('prs', mr()).number)
    assert.equals('2', glab.node('prs', mr()).id)
  end)

  it('says what forge calls each of gitlab four states', function()
    assert.equals('OPEN', glab.node('prs', mr({ state = 'opened' })).state)
    assert.equals('CLOSED', glab.node('prs', mr({ state = 'closed' })).state)
    assert.equals('MERGED', glab.node('prs', mr({ state = 'merged' })).state)
    assert.equals('CLOSED', glab.node('prs', mr({ state = 'locked' })).state)
    assert.is_nil(glab.node('prs', mr({ state = 'something new' })).state)
  end)

  it('carries the branches and the head the view was drawn from', function()
    local node = glab.node('prs', mr())
    assert.equals('main', node.baseRefName)
    assert.equals('feat/one', node.headRefName)
    assert.equals('9ece12b1965a53639fc2b13c4c74bbdf3fbe1d7d', node.headRefOid)
    assert.is_false(node.isCrossRepository)
  end)

  it('is a fork when its branch is on another project', function()
    assert.is_true(glab.node('prs', mr({ source_project_id = 85501738 })).isCrossRepository)
  end)

  it('conflicts only once gitlab has looked', function()
    assert.equals('MERGEABLE', glab.node('prs', mr()).mergeable)
    assert.equals(
      'CONFLICTING',
      glab.node('prs', mr({ detailed_merge_status = 'conflict' })).mergeable
    )
    assert.equals('CONFLICTING', glab.node('prs', mr({ has_conflicts = true })).mergeable)
    assert.equals('UNKNOWN', glab.node('prs', mr({ detailed_merge_status = 'checking' })).mergeable)
    assert.equals(
      'UNKNOWN',
      glab.node('prs', mr({ detailed_merge_status = 'unchecked' })).mergeable
    )
  end)

  it('hangs a failing pipeline where the check rollup is read from', function()
    local node = glab.node('prs', mr())
    assert.equals('FAILURE', node.commits.nodes[1].commit.statusCheckRollup.state)
    assert.is_nil(glab.node('prs', mr({ head_pipeline = { status = 'success' } })).commits)
  end)

  it('says nothing github has no gitlab field for', function()
    local node = glab.node('prs', mr())
    assert.is_nil(node.stateReason)
    assert.is_nil(node.authorAssociation)
    assert.is_nil(node.viewerCanMergeAsAdmin)
    assert.is_nil(node.isMergeQueueEnabled)
    assert.is_nil(node.autoMergeRequest)
  end)
end)

describe('an issue gitlab answered with', function()
  it('reads its body out of the description', function()
    local node = glab.node('issues', ISSUE)
    assert.equals(1, node.number)
    assert.equals('Expected the final line; got a blank.', node.body)
    assert.equals('https://gitlab.com/barrettruth/glab-fork-lab/-/work_items/1', node.url)
  end)

  it('has no type worth a row until it is not an ordinary issue', function()
    assert.is_nil(glab.node('issues', ISSUE).issueType)
    local typed = vim.tbl_extend('force', ISSUE, { issue_type = 'incident' })
    assert.equals('incident', glab.node('issues', typed).issueType.name)
  end)

  it('joins no branches', function()
    assert.is_nil(glab.node('issues', ISSUE).baseRefName)
  end)
end)

describe('what gitlab answers as an array', function()
  it('becomes the connection the renderers index', function()
    local node = glab.node('prs', mr())
    assert.same({ { name = 'bug' }, { name = 'ui' } }, node.labels.nodes)
    assert.equals(2, node.labels.totalCount)
    assert.same({ { login = 'barrettruth' } }, node.assignees.nodes)
    assert.same({ { requestedReviewer = { login = 'someone' } } }, node.reviewRequests.nodes)
  end)

  it('counts only what was written, so nothing reads as truncated', function()
    local node = glab.node('prs', mr())
    assert.equals(#node.labels.nodes, node.labels.totalCount)
    assert.equals(#node.assignees.nodes, node.assignees.totalCount)
  end)
end)

describe('the notes under an item', function()
  local NOTES = {
    {
      system = true,
      body = 'mentioned in issue #1',
      created_at = '1',
      author = { username = 'a' },
    },
    { system = false, body = 'a plain comment', created_at = '2', author = { username = 'b' } },
    {
      system = false,
      type = 'DiffNote',
      body = 'anchored to a line',
      created_at = '3',
      author = { username = 'c' },
    },
    {
      system = false,
      type = 'DiscussionNote',
      body = 'a reply in a thread',
      created_at = '4',
      author = { username = 'd' },
    },
  }

  it('are the conversation, without gitlab narrating itself', function()
    local comments = glab.node('prs', mr(), NOTES).comments
    assert.equals(2, comments.totalCount)
    assert.equals('a plain comment', comments.nodes[1].body)
    assert.equals('a reply in a thread', comments.nodes[2].body)
  end)

  it('leave out a note anchored to a diff, as github leaves out a review', function()
    for _, comment in ipairs(glab.node('prs', mr(), NOTES).comments.nodes) do
      assert.not_equals('anchored to a line', comment.body)
    end
  end)

  it('are absent, rather than empty, where none were asked for', function()
    assert.is_nil(glab.node('prs', mr()).comments)
  end)

  it('name their author the way the renderer reads one', function()
    local first = glab.node('prs', mr(), NOTES).comments.nodes[1]
    assert.equals('b', first.author.login)
    assert.equals('2', first.createdAt)
  end)
end)

describe('the title that makes a merge request a draft', function()
  it('puts the prefix gitlab reads in front', function()
    assert.equals('Draft: not ready', glab.draft('not ready', true))
  end)

  it('takes it off again, in any of the spellings gitlab accepts', function()
    assert.equals('not ready', glab.draft('Draft: not ready', false))
    assert.equals('not ready', glab.draft('draft: not ready', false))
    assert.equals('not ready', glab.draft('[Draft] not ready', false))
    assert.equals('not ready', glab.draft('(Draft) not ready', false))
  end)

  it('leaves a title that was never a draft alone', function()
    assert.equals('not ready', glab.draft('not ready', false))
  end)

  it('never doubles the prefix, however many it started with', function()
    assert.equals('Draft: not ready', glab.draft('Draft: not ready', true))
    assert.equals('Draft: not ready', glab.draft('Draft: [Draft] not ready', true))
    assert.equals('not ready', glab.draft('Draft: Draft: not ready', false))
  end)

  it('does not mistake a title that merely mentions one', function()
    assert.equals('the draft: a novel', glab.draft('the draft: a novel', false))
  end)
end)
