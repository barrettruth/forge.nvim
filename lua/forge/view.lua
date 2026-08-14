local log = require('forge.log')
local map = require('forge.map')
local uri = require('forge.uri')

local M = {}

local NS = vim.api.nvim_create_namespace('forge')

--- How many items a list asks github for at once.
M.PER_PAGE = 100

--- What a collection is called when talking to a person.
local LABEL = { issues = 'issues', prs = 'pull requests' }

--- @class forge.Mark
--- @field row integer zero-based
--- @field col integer byte column, inclusive
--- @field end_col integer byte column, exclusive
--- @field group string

--- Escape text bound for a 'winbar', where % introduces an item.
--- @param text string
--- @return string
function M.escape(text)
  return (text:gsub('%%', '%%%%'))
end

--- Wrap 'winbar' text in a highlight group. An empty group is harmless.
--- @param group string
--- @param text string
--- @return string
function M.hl(group, text)
  return ('%%#%s#%s%%*'):format(group, text)
end

--- Where a list buffer has got to.
--- @param buf integer
--- @return { page: integer, cursors: table<integer, string>, has_next: boolean }
function M.paging(buf)
  return vim.b[buf].forge or { page = 1, cursors = {}, has_next = false }
end

--- The view a buffer holds, if a buffer holds one.
--- @return forge.Uri?
function M.current()
  return uri.parse(vim.api.nvim_buf_get_name(0))
end

--- The buffer named exactly `name`.
---
--- Not |bufnr()|, which takes a pattern: a list would match an item already
--- open beneath it and render itself into that item's buffer.
--- @param name string
--- @return integer?
local function buffer_named(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

--- Whether a command was told to put its result somewhere new.
---
--- `tab` is -1 when absent rather than nil, so it is compared rather than
--- tested. See |:command-modifiers|.
--- @param smods table?
--- @return boolean
function M.wants_window(smods)
  smods = smods or {}
  return (smods.split or '') ~= ''
    or smods.vertical == true
    or smods.horizontal == true
    or (smods.tab or -1) >= 0
end

--- Honour a command's window modifiers, if it had any.
---
--- The structured modifiers say whether to make a window; the raw ones say
--- what kind, by being replayed onto a plain split. Callers do this after
--- resolving their target, so a target that cannot be resolved leaves no
--- window behind.
--- @param opts vim.api.keyset.create_user_command.command_args?
function M.split_for(opts)
  if M.wants_window(opts and opts.smods) then
    vim.cmd(((opts and opts.mods) or '') .. ' split')
  end
end

--- Show `lines` as the view named by `u`, reusing its buffer if it exists.
---
--- An item is markdown, because that is what github gave us and markdown
--- already knows how to draw it. A list is not, so it gets a filetype of its
--- own.
---
--- Mappings are set here rather than in an ftplugin: an item is markdown, and
--- an ftplugin/markdown.lua would reach every markdown file you open.
---
--- The buffer is replaced in place rather than wiped and rebuilt, so a window
--- handle held by a caller stays valid across a refresh.
--- @param u forge.Uri
--- @param lines string[]
--- @param winbar string
--- @param marks forge.Mark[]?
--- @param maps [string, string, string][]? extra mappings, as lhs/plug/desc
--- @return integer buf
function M.render(u, lines, winbar, marks, maps)
  local name = uri.tostring(u)
  local buf = buffer_named(name)
  if not buf then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, mark in ipairs(marks or {}) do
    vim.api.nvim_buf_set_extmark(buf, NS, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.group,
    })
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = u.number and 'markdown' or 'forge'

  map.buf_default(buf, 'n', 'g?', '<Plug>(forge-help)', 'what the keys in this buffer do')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the list this item is in')
  map.buf_default(buf, 'n', 'R', '<Plug>(forge-refresh)', 'fetch this view again')
  map.buf_default(buf, 'n', 'gX', '<Plug>(forge-web)', 'open this view on github.com')
  for _, m in ipairs(maps or {}) do
    map.buf_default(buf, 'n', m[1], m[2], m[3])
  end

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.b[buf].forge_winbar = winbar
  vim.wo.winbar = winbar
  return buf
end

--- Show a view, whichever collection it belongs to.
--- @param u forge.Uri
--- @param page integer?
--- @param cursors table<integer, string>?
function M.open(u, page, cursors)
  local module = u.collection == 'prs' and 'forge.pr' or 'forge.issue'
  require(module).show(u, page or 1, cursors or {})
end

--- Leave an item for the list it belongs to.
---
--- A list is the top: there is nothing above a list to go up to.
function M.up()
  local u = M.current()
  if not u or not u.number then
    return
  end
  M.open({ owner = u.owner, repo = u.repo, collection = u.collection, state = 'OPEN' })
end

--- Fetch this view again, where it stands.
---
--- Unlike |:edit|, which rebuilds a view from its name and so returns to the
--- first page, a refresh keeps the page you were on.
function M.refresh()
  local u = M.current()
  if not u then
    return
  end
  if u.number then
    M.open(u)
    return
  end
  local paging = M.paging(vim.api.nvim_get_current_buf())
  M.open(u, paging.page, paging.cursors)
end

--- Open this view on github.com.
---
--- What the buffer shows, not what the cursor is on: the buffer already knows
--- what it is, and <CR> is how you follow a line.
function M.web()
  local u = M.current()
  if not u then
    log.warn('no url for this buffer')
    return
  end
  vim.ui.open(uri.web(u))
end

--- Step `delta` pages through a list.
--- @param delta integer
function M.page(delta)
  local u = M.current()
  if not u or u.number then
    return
  end
  local paging = M.paging(vim.api.nvim_get_current_buf())
  local page = paging.page + delta
  if page < 1 then
    log.info('already on the first page')
    return
  end
  if delta > 0 and not paging.has_next then
    log.info('no more ' .. LABEL[u.collection])
    return
  end
  M.open(u, page, paging.cursors)
end

--- Swap a list between open and closed, from the first page.
function M.toggle_state()
  local u = M.current()
  if not u or u.number then
    return
  end
  u.state = u.state == 'CLOSED' and 'OPEN' or 'CLOSED'
  M.open(u)
end

--- Open the item under the cursor in a list.
--- @param split boolean? open it beside the list rather than over it
function M.open_at_cursor(split)
  local u = M.current()
  if not u or u.number then
    return
  end
  local number = vim.api.nvim_get_current_line():match('^#(%d+)')
  if not number then
    return
  end
  if split then
    vim.cmd('split')
  end
  M.open({
    owner = u.owner,
    repo = u.repo,
    collection = u.collection,
    number = tonumber(number),
  })
end

--- Warn when a connection came back truncated.
---
--- Every connection is capped. Asking for totalCount alongside the nodes is
--- what makes the cap visible instead of silently losing the tail.
--- @param connection table?
--- @param what string
function M.check_truncated(connection, what)
  if not connection then
    return
  end
  local shown = #(connection.nodes or {})
  local total = connection.totalCount or shown
  if total > shown then
    log.warn(('showing %d of %d %s'):format(shown, total, what))
  end
end

return M
