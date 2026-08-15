local edit = require('forge.edit')
local gh = require('forge.gh')
local view = require('forge.view')

--- @return table sent, fun() restore
local function watching(fail)
  local sent = {}
  local real = gh.graphql
  --- @diagnostic disable-next-line: duplicate-set-field
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

--- Of what was sent, the writes: drawing the item again is a request too.
--- @param sent table[]
--- @return table[]
local function writes(sent)
  return vim.tbl_filter(function(req)
    return req.variables.title ~= nil
  end, sent)
end

--- Stand in an item view, as "cc" would be.
--- @return forge.ItemVar
local function showing()
  local var = {
    kind = 'item',
    label = 'ISSUE',
    repo = 'a/b',
    url = 'https://github.com/a/b/issues/27',
    tag = '#27',
    title = 'a title',
    state = 'OPEN',
    state_hl = 'OkMsg',
    badges = '',
    stat = '',
    id = 'I_1',
    can_update = true,
    edit = 'a title\n\nthe body\n\nmore of it',
  }
  view.render({ owner = 'a', repo = 'b', collection = 'issues', number = 27 }, { 'x' }, var)
  return var
end

describe('editing an item', function()
  after_each(function()
    --- It is meant to refuse being abandoned while there is something unsent,
    --- so a test that leaves one behind would fail every buffer switch after
    --- it, in this file and the next.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match('/edit$') then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.cmd('silent! only')
  end)

  it('opens over the item, since nearly all of it is the same words', function()
    local var = showing()
    local win = vim.api.nvim_get_current_win()
    local item = vim.api.nvim_get_current_buf()
    edit.open(var)

    assert.equals(win, vim.api.nvim_get_current_win())
    assert.are_not.equal(item, vim.api.nvim_get_current_buf())
    assert.equals('forge://a/b/issues/27/edit', vim.api.nvim_buf_get_name(0))
    assert.equals('acwrite', vim.bo.buftype)
    assert.equals('markdown', vim.bo.filetype)
  end)

  it('is the title, a blank line, then the body', function()
    edit.open(showing())
    assert.same(
      { 'a title', '', 'the body', '', 'more of it' },
      vim.api.nvim_buf_get_lines(0, 0, -1, false)
    )
    assert.is_false(vim.bo.modified)
  end)

  it("is the item's own winbar, with the mode where the state was", function()
    edit.open(showing())
    local bar = vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str
    assert.equals('ISSUE #27 EDIT', bar)
  end)

  it('leaves the item where CTRL-O reaches it', function()
    edit.open(showing())
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-o>', true, false, true), 'x', false)
    assert.equals('forge://a/b/issues/27', vim.api.nvim_buf_get_name(0))
  end)

  it('is gone once nothing shows it, having nothing left to keep', function()
    edit.open(showing())
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd('enew')
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)

  it('refuses to be left while it holds something unsent', function()
    edit.open(showing())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a title', '', 'unsent' })
    local ok, err = pcall(vim.cmd, 'enew')
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('E37'))
  end)

  it('is not a view, so nothing that answers for one answers for it', function()
    edit.open(showing())
    assert.is_nil(require('forge.uri').parse(vim.api.nvim_buf_get_name(0)))
  end)

  it('sends what was written, the first line as the title', function()
    edit.open(showing())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a better title', '', 'a', 'b' })
    local sent, restore = watching()
    vim.cmd('write')
    restore()

    local wrote = writes(sent)
    assert.equals(1, #wrote)
    assert.equals('I_1', wrote[1].variables.id)
    assert.equals('a better title', wrote[1].variables.title)
    assert.equals('a\nb', wrote[1].variables.body)
    assert.is_false(vim.bo.modified)
  end)

  it('sends once however many times it has been opened', function()
    for _ = 1, 3 do
      edit.open(showing())
    end
    local sent, restore = watching()
    vim.cmd('write')
    restore()
    assert.equals(1, #writes(sent))
  end)

  it('keeps what you wrote when github refuses it', function()
    edit.open(showing())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a title', '', 'unsaved' })
    local _, restore = watching(true)
    vim.cmd('write')
    restore()

    assert.is_true(vim.bo.modified)
    assert.same({ 'a title', '', 'unsaved' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('refuses a title github would refuse, without asking it', function()
    edit.open(showing())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '', '', 'a body and no title' })
    local sent, restore = watching()
    vim.cmd('silent! write')
    restore()

    assert.same({}, writes(sent))
    assert.is_true(vim.bo.modified)
  end)
end)
