local view = require('forge.view')

local function uri(collection, number)
  return { project = 'a/b', collection = collection, number = number }
end

local function info(kind, over)
  return vim.tbl_extend('force', {
    kind = kind,
    label = kind == 'item' and 'ISSUE' or 'ISSUES',
    repo = 'a/b',
    url = 'https://github.com/a/b',
    state = 'OPEN',
    state_hl = 'OkMsg',
    tag = '#1',
    title = '',
    about = '',
    badges = '',
    pages = '1/1',
    total = '1',
  }, over or {})
end

describe('view.render', function()
  it('gives a list its own buffer when an item is already open', function()
    local item = view.render(uri('issues', 27), { 'the issue' }, info('item'))
    local list = view.render(uri('issues'), { 'the list' }, info('list'))

    assert.are_not.equal(item, list)
    assert.equals('forge://github.com/a/b/issues/27', vim.api.nvim_buf_get_name(item))
    assert.equals('forge://github.com/a/b/issues', vim.api.nvim_buf_get_name(list))
    assert.same({ 'the issue' }, vim.api.nvim_buf_get_lines(item, 0, -1, false))
    assert.same({ 'the list' }, vim.api.nvim_buf_get_lines(list, 0, -1, false))
  end)

  it('reuses the buffer a view already has', function()
    local first = view.render(uri('prs', 9), { 'one' }, info('item'))
    local again = view.render(uri('prs', 9), { 'two' }, info('item'))

    assert.equals(first, again)
    assert.same({ 'two' }, vim.api.nvim_buf_get_lines(again, 0, -1, false))
  end)
end)

describe('a rendered buffer', function()
  it('is a scratch buffer nothing can write to or undo', function()
    local buf = view.render(uri('issues', 31), { 'x' }, info('item'))

    assert.equals('nofile', vim.bo[buf].buftype)
    assert.equals('hide', vim.bo[buf].bufhidden)
    assert.is_false(vim.bo[buf].swapfile)
    assert.is_false(vim.bo[buf].modifiable)
    assert.is_true(vim.bo[buf].readonly)
    assert.is_false(vim.bo[buf].modified)
    assert.is_false(vim.bo[buf].modeline)
    assert.equals(-1, vim.bo[buf].undolevels)
  end)

  it('keeps no undo history to grow across refreshes', function()
    local buf = view.render(uri('issues', 32), { 'one' }, info('item'))
    view.render(uri('issues', 32), { 'two' }, info('item'), nil, nil, { keep = true })
    view.render(uri('issues', 32), { 'three' }, info('item'), nil, nil, { keep = true })

    assert.equals(0, vim.fn.undotree(buf).seq_last)
  end)

  it('reads as markdown when it is an item, and as its own filetype when a list', function()
    assert.equals(
      'markdown',
      vim.bo[view.render(uri('issues', 33), { 'x' }, info('item'))].filetype
    )
    assert.equals('forge', vim.bo[view.render(uri('issues'), { 'x' }, info('list'))].filetype)
  end)
end)

describe('the winbar', function()
  it('says the same thing in every window showing a view', function()
    local buf = view.render(uri('prs', 41), { 'x' }, info('item', { label = 'PR', tag = '#41' }))
    vim.cmd('split')
    local wins = vim.fn.win_findbuf(buf)
    assert.is_true(#wins > 1)

    local seen = {}
    for _, win in ipairs(wins) do
      seen[#seen + 1] = vim.trim(
        vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
      )
    end
    assert.equals('PR #41 OPEN', seen[1])
    assert.equals(seen[1], seen[2])
    vim.cmd('only')
  end)

  it('follows the buffer variable, so a redraw cannot leave one stale', function()
    local buf = view.render(uri('prs', 42), { 'x' }, info('item', { label = 'PR', tag = '#42' }))
    vim.cmd('split')
    local other = vim.fn.win_findbuf(buf)[2]

    view.render(
      uri('prs', 42),
      { 'x' },
      info('item', { label = 'PR', tag = '#42', state = 'MERGED', state_hl = 'Special' }),
      nil,
      nil,
      { keep = true }
    )

    local str =
      vim.api.nvim_eval_statusline(vim.wo[other].winbar, { winid = other, use_winbar = true }).str
    str = vim.trim(str)
    assert.equals('PR #42 MERGED', str)
    vim.cmd('only')
  end)

  it('leaves a title alone however much it looks like a format item', function()
    local buf = view.render(
      uri('issues', 43),
      { 'x' },
      info('item', { tag = '#43', about = '100% of %{system("id")} %#ErrorMsg#x%*' })
    )
    local win = vim.fn.win_findbuf(buf)[1]
    local str = vim.trim(
      vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
    )
    assert.equals('ISSUE #43 OPEN | 100% of %{system("id")} %#ErrorMsg#x%*', str)
  end)
end)

describe('a window showing a view', function()
  it('wraps an item on a word boundary and hangs the indent', function()
    local buf = view.render(uri('issues', 51), { 'x' }, info('item'))
    local win = vim.fn.win_findbuf(buf)[1]

    assert.is_true(vim.wo[win].wrap)
    assert.is_true(vim.wo[win].linebreak)
    assert.is_true(vim.wo[win].breakindent)
    assert.is_false(vim.wo[win].number)
  end)

  it('holds a list to one line per item, and shows which one', function()
    local buf = view.render(uri('issues'), { '#1 a', '#2 b' }, info('list'))
    local win = vim.fn.win_findbuf(buf)[1]

    assert.is_false(vim.wo[win].wrap)
    assert.is_true(vim.wo[win].cursorline)
  end)

  it('gives the settings back when it shows something else', function()
    local buf = view.render(uri('issues'), { '#1 a' }, info('list'))
    local win = vim.fn.win_findbuf(buf)[1]
    assert.is_true(vim.wo[win].cursorline)

    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(false, true))
    assert.is_false(vim.wo[win].cursorline)
    assert.equals('', vim.wo[win].winbar)
  end)
end)

describe('a reply that came back late', function()
  it('does not take the window from the answer to a newer question', function()
    local wanted = view.render(uri('issues', 61), { 'the one asked for last' }, info('item'))
    local win = vim.api.nvim_get_current_win()
    assert.equals(wanted, vim.api.nvim_win_get_buf(win))

    local stale = view.render(
      uri('issues', 62),
      { 'overtaken' },
      info('item'),
      nil,
      nil,
      { seq = 1 }
    )

    assert.equals(wanted, vim.api.nvim_win_get_buf(win))
    assert.same({ 'overtaken' }, vim.api.nvim_buf_get_lines(stale, 0, -1, false))
  end)

  it('does not overwrite a newer reply already drawn in its own buffer', function()
    local u = uri('issues', 63)
    local buf = view.render(u, { 'fresh' }, info('item'), nil, nil, { seq = 9000 })
    view.render(u, { 'stale' }, info('item'), nil, nil, { seq = 8999 })

    assert.same({ 'fresh' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)

describe('where a list got to', function()
  it('keeps a page number as a page number', function()
    local buf = vim.api.nvim_create_buf(false, true)
    view.paged(buf, 2, { [2] = 'CURSOR2' }, true)

    local paging = view.paging(buf)
    assert.equals(2, paging.page)
    assert.is_nil(paging.cursors[1])
    assert.equals('CURSOR2', paging.cursors[2])
    assert.is_true(paging.has_next)
  end)

  it('starts at the first page for a buffer it has never seen', function()
    local paging = view.paging(vim.api.nvim_create_buf(false, true))
    assert.equals(1, paging.page)
    assert.same({}, paging.cursors)
    assert.is_false(paging.has_next)
  end)

  it('is not a buffer variable, so nothing serialises the hole at page one', function()
    local buf = vim.api.nvim_create_buf(false, true)
    view.paged(buf, 1, { [2] = 'CURSOR2' }, true)

    assert.is_nil(vim.b[buf].forge)
    assert.is_nil(view.paging(buf).cursors[1])
  end)

  it('is dropped with the buffer', function()
    local buf = vim.api.nvim_create_buf(false, true)
    view.paged(buf, 3, {}, false)
    view.forget(buf)
    assert.equals(1, view.paging(buf).page)
  end)
end)

describe('a capped connection', function()
  local log = require('forge.log')

  local function capture()
    local said = {}
    local real = log.warn
    log.warn = function(msg)
      said[#said + 1] = msg
    end
    return said, function()
      log.warn = real
    end
  end

  it('says so when the tail was lost', function()
    local said, restore = capture()
    view.check_truncated({ nodes = { 1, 2 }, totalCount = 25 }, 'labels')
    restore()
    assert.same({ 'showing 2 of 25 labels' }, said)
  end)

  it('stays quiet when nothing was lost', function()
    local said, restore = capture()
    view.check_truncated({ nodes = { 1, 2 }, totalCount = 2 }, 'labels')
    view.check_truncated({ nodes = {} }, 'comments')
    view.check_truncated(nil, 'comments')
    restore()
    assert.same({}, said)
  end)

  it('has nothing to say when no count came back to measure it against', function()
    local said, restore = capture()
    view.check_truncated({ nodes = { 1, 2 } }, 'comments')
    view.check_truncated({ nodes = { 1, 2 }, totalCount = vim.NIL }, 'comments')
    restore()
    assert.same({}, said)
  end)
end)

local function drawn()
  vim.cmd('redraw!')
  local bar = vim.wo.winbar
  local shown = vim.api.nvim_eval_statusline(bar, { winid = 0, use_winbar = true })
  return vim.trim(shown.str), bar ~= ''
end

describe("a view's winbar", function()
  it('says what the view is', function()
    view.render(uri('issues', 27), { 'body' }, info('item', { about = 'a title', badges = ' x' }))
    local text, kept = drawn()
    assert.is_true(kept)
    assert.equals('ISSUE #1 OPEN | a title x', (text:gsub('%s%s+', ' ')))

    view.render(uri('issues'), { '#1 x' }, info('list', { total = '124' }))
    text, kept = drawn()
    assert.is_true(kept)
    assert.equals('ISSUES a/b 1/1 (124)', text)
  end)

  it('leaves the brackets out where the list holds an unknown number', function()
    local uncounted = info('list', { pages = '1/?' })
    uncounted.total = nil
    view.render(uri('issues'), { '#1 x' }, uncounted)
    local text, kept = drawn()
    assert.is_true(kept)
    assert.equals('ISSUES a/b 1/?', text)
  end)

  it('survives a shape it was not given, rather than emptying itself', function()
    local buf = view.render(uri('issues', 31), { 'body' }, info('item'))
    vim.b[buf].forge = { kind = 'item', label = 'ISSUE', repo = 'a/b', state = 'OPEN' }
    local text, kept = drawn()
    assert.is_true(kept)
    assert.equals('ISSUE  OPEN', text)

    vim.b[buf].forge = nil
    local _, still = drawn()
    assert.is_true(still)
  end)
end)

describe('view.yank', function()
  local log = require('forge.log')
  local real = log.info

  before_each(function()
    log.info = function() end
  end)
  after_each(function()
    log.info = real
  end)

  it('yanks what the buffer shows, not what the cursor is on', function()
    local url = 'https://github.example.com/a/b/pull/71'
    view.render(uri('prs', 71), { '#70 another' }, info('item', { url = url }))
    view.yank()
    assert.equals(url, vim.fn.getreg('"'))
  end)

  it('takes the register it was given', function()
    vim.keymap.set('n', '<Plug>(forge-yank)', view.yank)
    view.render(uri('issues'), { '#1 x' }, info('list'))
    vim.cmd('normal "agy')
    assert.equals('https://github.com/a/b', vim.fn.getreg('a'))
  end)
end)

describe('what an issue can be asked to do', function()
  local issue = require('forge.issue')

  local function offered(state, can_update)
    return vim.tbl_map(function(action)
      return action.label
    end, issue.actions({ state = state, can_update = can_update ~= false }))
  end

  it('names the reason, because github records one either way', function()
    assert.same(
      { 'Edit title and body', 'Close as completed', 'Close as not planned' },
      offered('OPEN')
    )
  end)

  it('reopens from every way an issue can be closed', function()
    for _, state in ipairs({ 'CLOSED', 'COMPLETED', 'DUPLICATE', 'NOT PLANNED' }) do
      assert.same({ 'Edit title and body', 'Reopen issue' }, offered(state))
    end
  end)

  it('offers nothing github would refuse', function()
    assert.same({}, offered('OPEN', false))
    assert.same({}, offered('COMPLETED', false))
  end)
end)

describe('the menu those are offered in', function()
  local function prompting(module, var)
    local asked
    local real = vim.ui.select
    --- @diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_, opts)
      asked = opts.prompt
    end
    vim.b.forge = var
    module.act()
    vim.ui.select = real
    return asked
  end

  it('names the change, the thing, and that a list follows', function()
    assert.equals(
      'Change issue #27:',
      prompting(require('forge.issue'), { tag = '#27', state = 'OPEN', can_update = true })
    )
    assert.equals(
      'Change pull request #42:',
      prompting(require('forge.pr'), { tag = '#42', state = 'OPEN', can_update = true })
    )
  end)
end)

describe('what a pull request can be asked to do', function()
  local pr = require('forge.pr')

  local function offered(state, can_update)
    return vim.tbl_map(function(action)
      return action.label
    end, pr.actions({ state = state, can_update = can_update ~= false }))
  end

  it('offers only the ways the state can go, the reversible one first', function()
    assert.same(
      { 'Edit title and body', 'Convert to draft', 'Close pull request' },
      offered('OPEN')
    )
    assert.same(
      { 'Edit title and body', 'Ready for review', 'Close pull request' },
      offered('DRAFT')
    )
    assert.same({ 'Edit title and body', 'Reopen pull request' }, offered('CLOSED'))
  end)

  it('offers nothing github would refuse, whatever the state', function()
    assert.same({}, offered('OPEN', false))
    assert.same({}, offered('DRAFT', false))
    assert.same({}, offered('CLOSED', false))
  end)

  it('still edits a merged one, which github allows and nothing else does', function()
    assert.same({ 'Edit title and body' }, offered('MERGED'))
  end)

  local function merges(var)
    return vim.tbl_filter(
      function(label)
        return label:find('merge') ~= nil
      end,
      vim.tbl_map(function(action)
        return action.label
      end, pr.actions(var))
    )
  end

  it('offers a merge once per method github would take', function()
    assert.same(
      { 'Squash and merge', 'Rebase and merge' },
      merges({ state = 'OPEN', can_update = true, can_squash = true, can_rebase = true })
    )
  end)

  it('offers no merge where github would take none', function()
    assert.same({}, merges({ state = 'OPEN', can_update = true }))
    assert.same({}, merges({ state = 'DRAFT', can_update = true, can_squash = true }))
    assert.same({}, merges({ state = 'CLOSED', can_update = true, can_squash = true }))
  end)

  it('names a merge for the rule it would go past, where there is one', function()
    assert.same(
      { 'Squash and merge (bypass)', 'Rebase and merge (bypass)' },
      merges({
        state = 'OPEN',
        can_update = true,
        can_squash = true,
        can_rebase = true,
        can_bypass = true,
      })
    )
  end)

  it('offers each merge once however it is named', function()
    for _, bypass in ipairs({ true, false }) do
      local var = {
        state = 'OPEN',
        can_update = true,
        can_squash = true,
        can_merge_commit = true,
        can_rebase = true,
        can_bypass = bypass,
      }
      assert.equals(3, #merges(var))
    end
  end)

  it('leaves a merge where it stood, whichever name it wears', function()
    local var = { state = 'OPEN', can_update = true, can_squash = true, can_bypass = true }
    local labels = vim.tbl_map(function(action)
      return action.label
    end, pr.actions(var))
    assert.same(
      { 'Edit title and body', 'Convert to draft', 'Close pull request' },
      vim.list_slice(labels, 1, 3)
    )
    assert.equals('Squash and merge (bypass)', labels[#labels])
  end)
end)

describe('starting something new', function()
  --- @return string[]? argv, string? opened
  local function asked(collection, url)
    local cmd, opened
    local system, open = vim.system, vim.ui.open
    vim.system = function(argv)
      cmd = argv
      return {}
    end
    vim.ui.open = function(target)
      opened = target
    end
    view.render(uri(collection, 27), { 'x' }, info('item', { url = url }))
    view.create()
    vim.system, vim.ui.open = system, open
    return cmd, opened
  end

  it('leaves a pull request to gh, which has a branch to push first', function()
    local cmd, opened = asked('prs', 'https://github.com/a/b/pull/27')
    assert.same({ 'gh', 'pr', 'create', '--repo', 'a/b', '--web' }, cmd)
    assert.is_nil(opened)
  end)

  it('opens a new issue itself, there being nothing for gh to work out', function()
    local cmd, opened = asked('issues', 'https://github.com/a/b/issues/27')
    assert.is_nil(cmd)
    assert.equals('https://github.com/a/b/issues/new', opened)
  end)

  it('keeps to the host that answered, and to what a search narrowed', function()
    local _, opened = asked('issues', 'https://git.example.com/a/b/issues?q=is:open')
    assert.equals('https://git.example.com/a/b/issues/new', opened)
  end)
end)

describe('view.field', function()
  it('is empty for anything b:forge does not hold', function()
    vim.b.forge = { tag = '#7' }
    assert.equals('#7', view.field('tag'))
    assert.equals('', view.field('title'))
    vim.b.forge = nil
    assert.equals('', view.field('tag'))
    vim.b.forge = 'not a table'
    assert.equals('', view.field('tag'))
    vim.b.forge = nil
  end)
end)
