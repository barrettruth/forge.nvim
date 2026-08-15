local log = require('forge.log')
local map = require('forge.map')
local ref = require('forge.ref')
local uri = require('forge.uri')

local M = {}

local NS = vim.api.nvim_create_namespace('forge')

--- What a view buffer remembers about itself, and what a reader may rely on.
---
--- Kept in `b:forge` because all of it is worth seeing: the state an item is
--- in, and the branches a pull request joins. Bookkeeping that would mean
--- nothing to a reader is not here — see `paged` below.
--- @class forge.BufVar
--- @field kind 'list'|'item' which of the two shapes a view has
--- @field label string what the winbar calls it
--- @field repo string "owner/repo"
--- @field url string the address github gave it, on whichever host answered

--- Split from the shape above rather than made optional on it: a winbar needs
--- the whole of its own half, and one class of optionals says a partial table
--- is allowed.
--- @class forge.ListVar : forge.BufVar
--- @field pages string "1/2"
--- @field total string how many the list holds in all
--- @field query string the search narrowing it, empty when it is the whole list

--- The last three are a pull request's; an issue joins no branches.
--- @class forge.ItemVar : forge.BufVar
--- @field tag string "#27"
--- @field title string
--- @field state string the state to show, as a person reads it
--- @field state_hl string the group that state is drawn in
--- @field badges string winbar segments an item adds, already highlighted
--- @field stat string what it measures, its own bar included, drawn right
--- @field id string? what a mutation names a pull request by
--- @field can_update boolean? whether github will let you change it
--- @field edit string? its title and body, as "cc" hands them to be edited
--- @field base string? the branch a pull request merges into
--- @field head string? the branch a pull request merges from
--- @field remote string? the repository "dd" and "dl" fetch a pull request from

--- Read one field of `b:forge`, for the templates below to call.
---
--- They never index `b:forge` themselves. A missing key raises E716 out of a
--- redraw, and Neovim answers an error in a 'winbar' by emptying the option,
--- so one field got wrong costs the view the only thing naming it — again on
--- every redraw. Read through here it costs a blank.
--- @param field string
--- @return string
function M.field(field)
  local var = vim.b.forge
  local value = type(var) == 'table' and var[field] or nil
  return value == nil and '' or tostring(value)
end

--- @param field string
--- @return string the expression reading it
local function call(field)
  return ('v:lua.require("forge.view").field("%s")'):format(field)
end

--- @param field string
--- @return string a plain `%{}` item, which is not re-parsed
local function at(field)
  return '%{' .. call(field) .. '}'
end

--- `%{%…%}` is re-parsed as format items, so only closed sets forge writes may
--- go through it. Every other field is user text, and uses plain `%{}`.
local STATE = "%{%'%#' .. " .. call('state_hl') .. " .. '#' .. " .. call('state') .. " .. '%*'%}"

--- A template over `b:forge`, as ci.nvim's is, rather than a rendered string:
--- `%{}` evaluates against the window being drawn, so a second window showing
--- a view cannot go stale.
--- @type table<'list'|'item', string>
local WINBAR = {
  list = '%#Title#'
    .. at('label')
    .. '%* %#Directory#'
    .. at('repo')
    .. '%*%( '
    .. at('query')
    .. '%) '
    .. at('pages')
    .. ' %#Comment#('
    .. at('total')
    .. ')%*',
  --- What it is and how it stands, the title with whatever room is left, then
  --- what only some of them have. `%<` after the first bar makes the title the
  --- one thing that can be cut, so nothing else is ever pushed off.
  item = '%#Title#'
    .. at('label')
    .. '%* %#Tag#'
    .. at('tag')
    .. '%* '
    .. STATE
    .. '%( | %<'
    .. at('title')
    .. '%)%=%{%'
    .. call('badges')
    .. '%}%{%'
    .. call('stat')
    .. '%}',
}

--- Where a view was last being read, kept for buffers no window is showing.
---
--- A visible buffer can be asked directly; one left behind by |<CR>| cannot,
--- and replacing its lines forgets the cursor it had.
--- @type table<integer, vim.fn.winsaveview.ret>
local placed = {}

--- How far through a list each buffer has got.
---
--- Lua rather than `b:`, because a buffer variable is a serialisation boundary
--- and none of this survives it usefully: the cursors are opaque tokens keyed
--- by page, page one has none, and a table with that hole comes back as a list
--- with `vim.NIL` in it — truthy, and not a cursor github accepts. Nothing
--- outside forge has any use for them either.
--- @type table<integer, { page: integer, cursors: table<integer, string>, has_next: boolean }>
local pages = {}

--- Replies do not come back in the order they were asked for: the counter says
--- which is still wanted, the table stops an overtaken one painting over it.
--- @type integer
local seq = 0

--- @type table<integer, integer>
local drawn = {}

--- Note where `buf` is being read, before something else takes the window.
--- @param buf integer
function M.remember(buf)
  if vim.api.nvim_win_get_buf(0) == buf then
    placed[buf] = vim.fn.winsaveview()
  end
end

--- Drop what was kept for a buffer that no longer exists.
--- @param buf integer
function M.forget(buf)
  placed[buf] = nil
  pages[buf] = nil
  drawn[buf] = nil
end

--- How many items a list asks github for at once.
M.PER_PAGE = 100

--- What a collection is called when talking to a person.
local LABEL = { issues = 'issues', prs = 'pull requests' }

--- What to say when a target names the collection the other command opens.
local OTHER = {
  issues = 'that names pull requests; use :PR',
  prs = 'that names issues; use :Issue',
}

--- Where a view was asked for, and where its answer should land.
---
--- A request is a round trip, so none of this can be read off the editor by
--- the time one comes back.
--- @class forge.Open
--- @field page integer?
--- @field cursors table<integer, string>?
--- @field win integer? the window the command was given in
--- @field mods string? see |:command-modifiers|
--- @field smods table?
--- @field split boolean? put the answer beside the view it was asked for in
--- @field cwd string? the directory the request is made from
--- @field keep boolean? this is the content you were already reading
--- @field seq integer? which request this is

--- The repository a target names, for saying out loud while it is in flight.
--- @param t forge.Target
--- @return string
function M.where(t)
  return t.owner and ('%s/%s'):format(t.owner, t.repo) or 'this repository'
end

--- @class forge.Mark
--- @field row integer zero-based
--- @field col integer byte column, inclusive
--- @field end_col integer byte column, exclusive
--- @field group string

--- What a state means, rather than what colour it is. Builtin groups only.
--- @enum forge.Hl
M.HL = {
  live = 'OkMsg', --- open, approved, passing
  done = 'Special', --- merged, completed
  bad = 'ErrorMsg', --- closed unmerged, conflicting, failing, changes requested
  waiting = 'WarningMsg', --- pending, expected, not yet known
  inert = 'Comment', --- draft, not planned, skipped
}

--- Wrap 'winbar' text in a highlight group. An empty group is harmless.
--- @param group string
--- @param text string
--- @return string
function M.hl(group, text)
  return ('%%#%s#%s%%*'):format(group, text)
end

--- An overtaken reply still draws into its own buffer; it may not take the
--- window, because the answer to a later question is already there.
--- @param o forge.Open?
--- @return boolean
function M.newest(o)
  return o == nil or o.seq == nil or o.seq == seq
end

--- Where a list buffer has got to.
--- @param buf integer
--- @return { page: integer, cursors: table<integer, string>, has_next: boolean }
function M.paging(buf)
  return pages[buf] or { page = 1, cursors = {}, has_next = false }
end

--- Record where a list buffer has got to.
--- @param buf integer
--- @param page integer
--- @param cursors table<integer, string>
--- @param has_next boolean
function M.paged(buf, page, cursors, has_next)
  pages[buf] = { page = page, cursors = cursors, has_next = has_next }
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
function M.buffer_named(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

--- Say a view is being fetched again, and return how to stop saying it. Only
--- one already on screen can: a buffer that does not exist yet has no 'busy'.
--- @param t forge.Target
--- @return fun()
function M.busy(t)
  local buf = t.owner and M.buffer_named(uri.tostring(t --[[@as forge.Uri]])) or nil
  if not buf then
    return function() end
  end
  vim.bo[buf].busy = vim.bo[buf].busy + 1
  return function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].busy = math.max(0, vim.bo[buf].busy - 1)
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
--- what kind, by being replayed onto a plain split.
--- @param opts { mods: string?, smods: table?, split: boolean? }?
function M.split_for(opts)
  if (opts and opts.split) or M.wants_window(opts and opts.smods) then
    vim.cmd(((opts and opts.mods) or '') .. ' split')
  end
end

--- Put the editor where a view is about to be drawn.
---
--- The window a command was given in is the one its answer belongs in, not
--- whichever happens to be current once github replies. The split is made here
--- too, after the reply, so a request that fails leaves no window behind.
--- @param o forge.Open?
function M.place(o)
  if not M.newest(o) then
    return
  end
  if o and o.win and vim.api.nvim_win_is_valid(o.win) then
    vim.api.nvim_set_current_win(o.win)
  end
  M.split_for(o)
end

--- Window options do not follow a buffer into a second window, so they are set
--- wherever a view turns up. The `vim.wo[win][0]` scope, which core's own
--- ftplugins use, is what gives them back when the window shows something else.
--- @param buf integer
--- @param win integer
function M.dress(buf, win)
  local u = uri.parse(vim.api.nvim_buf_get_name(buf))
  if not u then
    return
  end
  local item = u.number ~= nil

  if vim.b[buf].forge then
    vim.wo[win][0].winbar = WINBAR[item and 'item' or 'list']
  end
  vim.wo[win][0].list = false
  vim.wo[win][0].number = false
  vim.wo[win][0].relativenumber = false
  vim.wo[win][0].signcolumn = 'no'
  vim.wo[win][0].spell = false

  if item then
    vim.wo[win][0].wrap = true
    vim.wo[win][0].linebreak = true
    vim.wo[win][0].breakindent = true
    vim.wo[win][0].conceallevel = 2
    vim.wo[win][0].concealcursor = 'nc'
  else
    vim.wo[win][0].wrap = false
    vim.wo[win][0].cursorline = true
  end
end

--- Show `lines` as the view named by `u`, reusing its buffer if it exists.
---
--- Mappings are set here rather than in an ftplugin: an item is markdown, and
--- an ftplugin/markdown.lua would reach every markdown file you open. So is
--- 'includeexpr', last of all, so that a filetype plugin of your own cannot
--- have set it after us and left |gf| pointing at nothing.
---
--- The buffer is replaced in place rather than wiped and rebuilt, so a window
--- handle held by a caller stays valid across a refresh.
--- @param u forge.Uri
--- @param lines string[]
--- @param info forge.ListVar|forge.ItemVar
--- @param marks forge.Mark[]?
--- @param maps [string, string, string][]? extra mappings, as lhs/plug/desc
--- @param o forge.Open? whose `keep` says whether this is a redraw of what
--- was already being read, rather than different content under the same name
--- @return integer buf
function M.render(u, lines, info, marks, maps, o)
  local name = uri.tostring(u)
  local buf = M.buffer_named(name)
  local keep = buf ~= nil and o ~= nil and o.keep == true
  if not buf then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, name)
  end

  if o and o.seq and o.seq < (drawn[buf] or 0) then
    return buf
  end
  drawn[buf] = (o and o.seq) or drawn[buf]

  local looking = {}
  if keep then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      looking[#looking + 1] = { win = win, view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
    end
  end
  local hidden = keep and #looking == 0 and placed[buf] or nil

  vim.bo[buf].modeline = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false

  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, mark in ipairs(marks or {}) do
    vim.api.nvim_buf_set_extmark(buf, NS, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.group,
    })
  end

  vim.b[buf].forge = info

  map.buf_default(buf, 'n', 'g?', '<Plug>(forge-help)', 'what the keys in this buffer do')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the list this item is in')
  map.buf_default(buf, 'n', 'R', '<Plug>(forge-refresh)', 'fetch this view again')
  map.buf_default(buf, 'n', 'gX', '<Plug>(forge-web)', 'open this view on github.com')
  map.buf_default(buf, 'n', 'gy', '<Plug>(forge-yank)', "yank this view's url")
  map.buf_default(buf, 'n', 'ga', '<Plug>(forge-create)', 'start something new in this collection')
  for _, m in ipairs(maps or {}) do
    map.buf_default(buf, 'n', m[1], m[2], m[3])
  end

  if M.newest(o) then
    vim.api.nvim_win_set_buf(0, buf)
    if not keep then
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    elseif hidden then
      vim.fn.winrestview(hidden)
    end
  end
  for _, seen in ipairs(looking) do
    if vim.api.nvim_win_is_valid(seen.win) then
      vim.api.nvim_win_call(seen.win, function()
        vim.fn.winrestview(seen.view)
      end)
    end
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    M.dress(buf, win)
  end

  vim.bo[buf].filetype = u.number and 'markdown' or 'forge'
  vim.bo[buf].includeexpr = 'v:lua.require("forge.ref").include(v:fname)'

  return buf
end

--- The module answering for a collection.
--- @param collection forge.Collection
--- @return table
local function collected(collection)
  return require(collection == 'prs' and 'forge.pr' or 'forge.issue')
end

--- Show a view, whichever collection it belongs to.
--- @param t forge.Target
--- @param o forge.Open?
function M.open(t, o)
  o = o or {}
  seq = seq + 1
  o.seq = seq
  o.win = o.win or vim.api.nvim_get_current_win()
  o.cwd = o.cwd or require('forge.vcs').dir()

  collected(t.collection).show(t, o)
end

--- Do something to the item this buffer shows. Only an item has anything to do.
function M.act()
  local u = M.current()
  if u and u.number then
    collected(u.collection).act()
  end
end

--- Open whatever `target` names, so long as it names `collection`.
---
--- Both commands arrive here. The window, the directory and the cursor are
--- read now, while the user is still standing in them; everything else waits
--- for github. "." is the only target read off the editor rather than parsed,
--- so it is spent here and the grammar below never sees it.
--- @param target string?
--- @param collection forge.Collection
--- @param opts vim.api.keyset.create_user_command.command_args?
function M.command(target, collection, opts)
  if vim.trim(target or '') == '.' then
    local token, why = ref.at_cursor()
    if not token then
      log.err(why or 'nothing under the cursor')
      return
    end
    target = token
  end

  local t, err = uri.resolve(target, collection)
  if not t then
    log.err(err or 'cannot resolve target')
    return
  end
  if t.collection ~= collection then
    log.err(OTHER[collection])
    return
  end
  M.open(t, { mods = opts and opts.mods, smods = opts and opts.smods })
end

--- Leave an item for the list it belongs to.
function M.up()
  local u = M.current()
  if not u or not u.number then
    return
  end
  M.open({ owner = u.owner, repo = u.repo, collection = u.collection }, { keep = true })
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
    M.open(u, { keep = true })
    return
  end
  local paging = M.paging(vim.api.nvim_get_current_buf())
  M.open(u, { page = paging.page, cursors = paging.cursors, keep = true })
end

--- Start something new in a collection, on github.com.
---
--- github's own page is the form, so templates and required fields stay
--- theirs to enforce, and gh pushes the branch on the way there. The
--- repository is the one asked about rather than the one you are standing in,
--- so a fork can propose a branch to what it forked.
--- @param t forge.Target? what to add to, or the view being looked at
function M.create(t)
  t = t or M.current()
  if not t then
    return
  end

  local what = t.collection == 'prs' and 'pr' or 'issue'
  local said = t.collection == 'prs' and 'pull request' or 'issue'
  local slug = ('%s/%s'):format(t.owner, t.repo)
  local done = log.progress(('a new %s in %s'):format(said, slug))

  vim.system(
    { 'gh', what, 'create', '--repo', slug, '--web' },
    { cwd = require('forge.vcs').dir(), text = true },
    function(out)
      vim.schedule(function()
        if out.code ~= 0 then
          local why = vim.trim((out.stderr or ''):gsub('\n.*', ''))
          why = why ~= '' and why or ('gh %s create failed'):format(what)
          done('failed', why)
          return log.err(why)
        end
        done('success', ('a new %s in %s'):format(said, slug))
      end)
    end
  )
end

--- Open this view on github.com.
---
--- What the buffer shows, not what the cursor is on: the buffer already knows
--- what it is, and <CR> is how you follow a line.
function M.web()
  local url = M.field('url')
  if url == '' then
    log.warn('no url for this buffer')
    return
  end
  vim.ui.open(url)
end

--- Yank this view's URL.
function M.yank()
  local url = M.field('url')
  if url == '' then
    log.warn('no url for this buffer')
    return
  end
  vim.fn.setreg(vim.v.register, url, 'v')
  log.info(url)
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
  M.open(u, { page = page, cursors = paging.cursors })
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
  M.open({
    owner = u.owner,
    repo = u.repo,
    collection = u.collection,
    number = tonumber(number),
  }, { keep = true, split = split })
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
