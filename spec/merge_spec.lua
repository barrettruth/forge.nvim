local gh = require('forge.gh')
local merge = require('forge.merge')
local pr = require('forge.pr')
local view = require('forge.view')

local function watching(fail)
  local sent = {}
  local real = gh.graphql
  gh.graphql = function(req, on_done, on_fail)
    sent[#sent + 1] = req
    if fail then
      if on_fail then
        on_fail()
      end
    else
      on_done({})
    end
  end
  return sent, function()
    gh.graphql = real
  end
end

local function merges(sent)
  return vim.tbl_filter(function(req)
    return req.query:find('mergePullRequest', 1, true) ~= nil
  end, sent)
end

local function showing(over)
  local var = vim.tbl_extend('force', {
    kind = 'item',
    label = 'PR',
    repo = 'a/b',
    url = 'https://github.com/a/b/pull/151',
    tag = '#151',
    title = 'a title',
    state = 'OPEN',
    state_hl = 'OkMsg',
    badges = '',
    stat = '',
    id = 'PR_1',
    oid = 'deadbeef',
    can_update = true,
    can_squash = true,
    can_merge_commit = true,
    merge = {
      SQUASH = { headline = 'a title (#151)', body = '* one\n\n* two' },
      MERGE = { headline = 'Merge pull request #151 from a/b', body = 'a title' },
    },
  }, over or {})
  view.render({ project = 'a/b', collection = 'prs', number = 151 }, { 'x' }, var)
  return var
end

describe('writing the message a merge carries', function()
  after_each(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match('/merge/%a+$') then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.cmd('silent! only')
  end)

  it('opens beside the pull request, named for the method', function()
    local win = vim.api.nvim_get_current_win()
    merge.open(showing(), 'SQUASH')

    assert.are_not.equal(win, vim.api.nvim_get_current_win())
    assert.equals('forge://github.com/a/b/prs/151/merge/squash', vim.api.nvim_buf_get_name(0))
    assert.equals('acwrite', vim.bo.buftype)
    assert.equals('gitcommit', vim.bo.filetype)
  end)

  it('holds the message github would write for that method', function()
    merge.open(showing(), 'SQUASH')
    assert.same(
      { 'a title (#151)', '', '* one', '', '* two' },
      vim.api.nvim_buf_get_lines(0, 0, -1, false)
    )

    vim.cmd('silent! only')
    merge.open(showing(), 'MERGE')
    assert.same(
      { 'Merge pull request #151 from a/b', '', 'a title' },
      vim.api.nvim_buf_get_lines(0, 0, -1, false)
    )
  end)

  it('does not hand one method the message written for the other', function()
    merge.open(showing(), 'SQUASH')
    local squash = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(squash, 0, -1, false, { 'squash text' })

    vim.cmd('wincmd p')
    merge.open(showing(), 'MERGE')
    local commit = vim.api.nvim_get_current_buf()

    assert.are_not.equal(squash, commit)
    assert.equals('forge://github.com/a/b/prs/151/merge/commit', vim.api.nvim_buf_get_name(commit))
    assert.same(
      { 'Merge pull request #151 from a/b', '', 'a title' },
      vim.api.nvim_buf_get_lines(commit, 0, -1, false)
    )
  end)

  it('says which method it is, and when that goes past a rule', function()
    merge.open(showing(), 'SQUASH')
    local bar = vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str
    assert.equals('PR #151 SQUASH', bar)

    vim.cmd('silent! only')
    merge.open(showing({ can_bypass = true }), 'MERGE')
    bar = vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str
    assert.equals('PR #151 MERGE COMMIT BYPASS', bar)
  end)

  it('sends the message, the method and the head it was drawn from', function()
    merge.open(showing(), 'SQUASH')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a subject', '', 'a body' })
    local sent, restore = watching()
    vim.cmd('write')
    restore()

    local wrote = merges(sent)
    assert.equals(1, #wrote)
    assert.equals('PR_1', wrote[1].variables.id)
    assert.equals('deadbeef', wrote[1].variables.oid)
    assert.equals('a subject', wrote[1].variables.headline)
    assert.equals('a body', wrote[1].variables.body)
    assert.is_truthy(wrote[1].query:find('mergeMethod: SQUASH', 1, true))
  end)

  it('sends an empty body as one, github offering that for itself', function()
    merge.open(showing(), 'SQUASH')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a subject' })
    local sent, restore = watching()
    vim.cmd('write')
    restore()

    assert.equals('', merges(sent)[1].variables.body)
  end)

  it('sends nothing for an empty subject', function()
    merge.open(showing(), 'SQUASH')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '', '', 'a body and no subject' })
    local sent, restore = watching()
    vim.cmd('silent! write')
    restore()

    assert.same({}, merges(sent))
    assert.is_true(vim.bo.modified)
  end)

  it('keeps what you wrote when github refuses it, and writes again', function()
    merge.open(showing(), 'SQUASH')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a subject', '', 'retry me' })

    local sent, restore = watching(true)
    vim.cmd('write')
    restore()
    assert.equals(1, #merges(sent))
    assert.is_true(vim.bo.modified)
    assert.same({ 'a subject', '', 'retry me' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    sent, restore = watching()
    vim.cmd('write')
    restore()
    assert.equals(1, #merges(sent))
    assert.is_false(vim.bo.modified)
  end)

  it('sends once however many times it has been opened', function()
    merge.open(showing(), 'SQUASH')
    local buf = vim.api.nvim_get_current_buf()
    for _ = 1, 2 do
      vim.cmd('wincmd p')
      merge.open(showing(), 'SQUASH')
    end
    assert.equals(buf, vim.api.nvim_get_current_buf())

    local sent, restore = watching()
    vim.cmd('write')
    restore()
    assert.equals(1, #merges(sent))
  end)
end)

describe('a merge that waits', function()
  after_each(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match('merge/%a+$') then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.cmd('silent! only')
  end)

  local function labels(var)
    return vim.tbl_map(function(action)
      return action.label
    end, pr.actions(var))
  end

  local blocked = {
    state = 'OPEN',
    can_update = true,
    can_squash = true,
    can_rebase = true,
    can_bypass = true,
    can_auto = true,
  }

  it('is offered once per method, above the merges that happen now', function()
    assert.same({
      'Edit title and body',
      'Convert to draft',
      'Close pull request',
      'Enable auto-merge (squash)',
      'Enable auto-merge (rebase)',
      'Squash and merge (bypass)',
      'Rebase and merge (bypass)',
    }, labels(blocked))
  end)

  it('is not offered where github would merge now', function()
    local clean = vim.tbl_extend('force', vim.deepcopy(blocked), {
      can_bypass = false,
      can_auto = false,
    })
    assert.same({
      'Edit title and body',
      'Convert to draft',
      'Close pull request',
      'Squash and merge',
      'Rebase and merge',
    }, labels(clean))
  end)

  it('gives way to calling it off once one is waiting', function()
    local var = vim.tbl_extend('force', vim.deepcopy(blocked), {
      auto = 'SQUASH',
      can_unauto = true,
    })
    local said = labels(var)
    assert.is_truthy(vim.tbl_contains(said, 'Disable auto-merge'))
    for _, label in ipairs(said) do
      assert.is_falsy(label:find('Enable auto-merge', 1, true))
    end
  end)

  it('writes its message into its own buffer, and never says bypass', function()
    merge.open(showing({ can_bypass = true }), 'SQUASH', true)
    assert.equals('forge://github.com/a/b/prs/151/automerge/squash', vim.api.nvim_buf_get_name(0))
    local bar = vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str
    assert.equals('PR #151 AUTO SQUASH', bar)
  end)

  it('asks github to wait rather than to merge', function()
    merge.open(showing(), 'SQUASH', true)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a subject', '', 'a body' })
    local sent, restore = watching()
    vim.cmd('write')
    restore()

    local wrote = vim.tbl_filter(function(req)
      return req.query:find('enablePullRequestAutoMerge', 1, true) ~= nil
    end, sent)
    assert.equals(1, #wrote)
    assert.equals('a subject', wrote[1].variables.headline)
    assert.equals('deadbeef', wrote[1].variables.oid)
  end)
end)

describe('a base branch that merges through a queue', function()
  local function labels(var)
    return vim.tbl_map(function(action)
      return action.label
    end, pr.actions(var))
  end

  it('offers the queue where the merges would have been', function()
    assert.same({
      'Edit title and body',
      'Convert to draft',
      'Close pull request',
      'Add to merge queue',
    }, labels({ state = 'OPEN', can_update = true, queued = true }))
  end)

  it('offers the way out once it is in', function()
    local said = labels({
      state = 'OPEN',
      can_update = true,
      queued = true,
      in_queue = true,
    })
    assert.is_truthy(vim.tbl_contains(said, 'Remove from merge queue'))
    assert.is_falsy(vim.tbl_contains(said, 'Add to merge queue'))
  end)

  it('offers neither where the base branch has no queue', function()
    local said = labels({ state = 'OPEN', can_update = true, can_squash = true })
    for _, label in ipairs(said) do
      assert.is_falsy(label:find('merge queue', 1, true))
    end
  end)
end)

describe('which merges write a message first', function()
  local function acting(label, var)
    for _, action in ipairs(pr.actions(var)) do
      if action.label == label then
        return action
      end
    end
  end

  local open = {
    state = 'OPEN',
    can_update = true,
    can_squash = true,
    can_merge_commit = true,
    can_rebase = true,
  }

  it('opens a buffer for the two that write a commit', function()
    assert.is_function(acting('Squash and merge', open).run)
    assert.is_function(acting('Create a merge commit', open).run)
  end)

  it('sends a rebase as it always did, github writing it no message', function()
    local rebase = acting('Rebase and merge', open)
    assert.is_nil(rebase.run)
    assert.is_truthy(rebase.query:find('mergeMethod: REBASE', 1, true))
  end)
end)
