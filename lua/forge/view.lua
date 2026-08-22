local log = require('forge.log')
local map = require('forge.map')
local ref = require('forge.ref')
local uri = require('forge.uri')

local M = {}

local NS = vim.api.nvim_create_namespace('forge')

--- What a view buffer publishes about itself. Documented at |b:forge|.
--- @class forge.BufVar
--- @field kind 'list'|'item'
--- @field label string what the winbar calls it
--- @field repo string "owner/repo"
--- @field url string its address on the forge that answered

--- @class forge.ListVar : forge.BufVar
--- @field pages string "1/2", or "1/?" where the last page is not known
--- @field total string? absent where the forge will not count the list
--- @field query string the search narrowing it, empty for the whole list

--- @class forge.ItemVar : forge.BufVar
--- @field tag string "#27"
--- @field title string
--- @field state string the state to show, as a person reads it
--- @field state_hl string the group that state is drawn in
--- @field about string winbar text after the state, empty where the branches
--- fill that room instead
--- @field badges string extra winbar segments, already highlighted
--- @field stat string what it measures, drawn against the right edge
--- @field id string? what a mutation names it by
--- @field can_update boolean? whether the forge will let you change it
--- @field edit string? its title and body, as "cc" hands them to be edited
--- @field oid string? the head it was drawn from
--- @field can_squash boolean? whether the forge would take each of the three
--- @field can_merge_commit boolean? merges, weighed before the menu is drawn
--- @field can_rebase boolean?
--- @field can_bypass boolean? whether a merge would bypass a rule to happen
--- @field merge table<string, { headline: string, body: string }>? the commit
--- message the forge would write, keyed by the method that would carry it
--- @field can_auto boolean? whether a merge may be set to wait
--- @field can_unauto boolean? whether one already waiting may be called off
--- @field auto string? the method a waiting merge would use
--- @field queued boolean? whether the base branch merges through a queue
--- @field in_queue boolean? whether this one is in it
--- @field base string? the branch it merges into
--- @field head string? the branch it merges from
--- @field remote string? the repository "dd" and "dl" fetch it from
--- @field stack string? which layer of its stack it is, "3/4", counted from
--- the bottom; empty where it is in no stack
--- @field stack_kept boolean? whether the forge keeps that stack itself, and
--- so merges it as a unit rather than a layer at a time

--- Read one field of `b:forge`. The templates below never index it directly.
--- A missing key raises E716 from a redraw. Neovim empties 'winbar' on an
--- error. One wrong field would blank the bar.
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

--- `%{%…%}` is re-parsed as format items. Only closed sets forge writes may go
--- through it. Every other field is user text, and uses plain `%{}`.
local STATE = "%{%'%#' .. " .. call('state_hl') .. " .. '#' .. " .. call('state') .. " .. '%*'%}"

--- A template over `b:forge`, not a rendered string. ci.nvim's is the same.
--- `%{}` evaluates against the window being drawn. A rendered string goes
--- stale in the second window showing a view.
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
    .. '%( %#Comment#('
    .. at('total')
    .. ')%*%)',
  -- Exactly one of the branch pair and `about` is ever filled. `%(…%)` drops
  -- the other. Both are somebody else's text: plain `%{}` only. `%<` truncates
  -- here first.
  item = '%#Title#'
    .. at('label')
    .. '%* %#Tag#'
    .. at('tag')
    .. '%* '
    .. STATE
    .. '%( | %#Comment#'
    .. at('base')
    .. ' <- %*%#Directory#%<'
    .. at('head')
    .. '%*%)%( | %<'
    .. at('about')
    .. '%)%=%{%'
    .. call('badges')
    .. '%}%{%'
    .. call('stat')
    .. '%}',
}

--- Where a view was last being read, for buffers no window is showing. A
--- visible buffer can be asked directly. One left behind by |<CR>| cannot.
--- @type table<integer, vim.fn.winsaveview.ret>
local placed = {}

--- How far through a list each buffer has got, and what it is showing.
---
--- Lua rather than `b:`. The cursors are keyed by page and page one has none,
--- leaving a hole. A buffer variable brings that hole back as a list holding
--- `vim.NIL`: truthy, and not a cursor.
--- @type table<integer, { page: integer, cursors: table<integer, string>, has_next: boolean, numbers: integer[] }>
local pages = {}

--- The list each item buffer was opened from, by name. A search is a list of
--- its own, and stepping through one must not wander into the whole
--- collection. An item reached any other way has no entry and no neighbours.
--- @type table<integer, string?>
local from = {}

--- The stack each item buffer is showing, for the keys that walk one. Lua
--- rather than `b:`, as the pages above are: it is read by a mapping and never
--- drawn, and `b:forge` says the position already.
--- @type table<integer, forge.stack.Rows?>
local stacked = {}

--- The chain each item buffer last drew, so a redraw keeps showing it until
--- the next one lands rather than blanking the section and filling it again.
--- @type table<integer, forge.Stack?>
local held = {}

--- Replies do not come back in the order they were asked for. The counter says
--- which is still wanted. `drawn` stops an overtaken one painting over it.
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
  stacked[buf] = nil
  held[buf] = nil
  from[buf] = nil
end

--- How many items a list asks the forge for at once.
M.PER_PAGE = 100

--- Which command to send someone to when a target names the other collection.
local OTHER = { issues = ':PR', prs = ':Issue' }

--- What the forge that answered for `t` calls its collection.
--- @param t forge.Target
--- @return forge.Nouns
local function nouns(t)
  return require('forge.backend').of(t.host).nouns[t.collection]
end

--- Where a view was asked for, and where its answer should land. None of it
--- can be read off the editor once the round trip comes back.
--- @class forge.Open
--- @field page integer?
--- @field cursors table<integer, string>?
--- @field win integer? the window the command was given in
--- @field mods string? see |:command-modifiers|
--- @field smods table?
--- @field split boolean? put the answer beside the view it was asked for in
--- @field cwd string? the directory the request is made from
--- @field keep boolean? this is the content you were already reading
--- @field hidden boolean? draw it into its buffer without giving it a window
--- @field seq integer? which request this is
--- @field from string? the list this was opened from, for the keys that step
--- through one

--- The repository a target names, for a progress message to say.
--- @param t forge.Target
--- @return string
function M.where(t)
  return t.project or 'this repository'
end

--- @class forge.Mark
--- @field row integer zero-based
--- @field col integer? byte column, inclusive; absent on a whole-line mark
--- @field end_col integer? byte column, exclusive; absent on a whole-line mark
--- @field group string|string[]? the group its range takes
--- @field line string? a group for the whole line, instead of a range
--- @field url string? where |gx| goes from here, read off the mark by core

--- What a state means, rather than what colour it is. Builtin groups only.
--- @enum forge.Hl
M.HL = {
  live = 'OkMsg', -- open, approved, passing
  done = 'Special', -- merged, completed
  bad = 'ErrorMsg', -- closed unmerged, conflicting, failing, changes requested
  waiting = 'WarningMsg', -- pending, expected, not yet known
  inert = 'Comment', -- draft, not planned, skipped
}

--- Wrap 'winbar' text in a highlight group. An empty group is harmless.
--- @param group string
--- @param text string
--- @return string
function M.hl(group, text)
  return ('%%#%s#%s%%*'):format(group, text)
end

--- Whether `o` is still the request being waited for. An overtaken reply draws
--- into its own buffer but may not take the window.
--- @param o forge.Open?
--- @return boolean
function M.newest(o)
  return o == nil or o.seq == nil or o.seq == seq
end

--- Where a list buffer has got to.
--- @param buf integer
--- @return { page: integer, cursors: table<integer, string>, has_next: boolean, numbers: integer[] }
function M.paging(buf)
  return pages[buf] or { page = 1, cursors = {}, has_next = false, numbers = {} }
end

--- Record where a list buffer has got to, and what it drew.
--- @param buf integer
--- @param page integer
--- @param cursors table<integer, string>
--- @param has_next boolean
--- @param numbers integer[]? the items on this page, in the order drawn
function M.paged(buf, page, cursors, has_next, numbers)
  pages[buf] = { page = page, cursors = cursors, has_next = has_next, numbers = numbers or {} }
end

--- Record the stack an item buffer drew, or that it drew none.
--- @param buf integer
--- @param nav forge.stack.Rows?
--- @param chain forge.Stack?
function M.stacked(buf, nav, chain)
  stacked[buf] = nav
  held[buf] = chain
end

--- The chain the view named by `u` is already showing, if it is showing one.
--- @param u forge.Uri
--- @return forge.Stack?
function M.holding(u)
  local buf = M.buffer_named(uri.tostring(u))
  return buf and held[buf] or nil
end

--- The view a buffer holds, if a buffer holds one.
--- @return forge.Uri?
function M.current()
  return uri.parse(vim.api.nvim_buf_get_name(0))
end

--- The buffer named exactly `name`. Not |bufnr()|: it takes a pattern, and a
--- list would match an item already open beneath it.
--- @param name string
--- @return integer?
function M.buffer_named(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

--- Set 'busy' while a view is fetched again, and return how to clear it. Only
--- a view already on screen has a buffer to set it on.
--- @param t forge.Target
--- @return fun()
function M.busy(t)
  local buf = t.project and M.buffer_named(uri.tostring(t --[[@as forge.Uri]])) or nil
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
--- `tab` is -1 when absent, not nil. Compare it, do not test it.
--- See |:command-modifiers|.
--- @param smods table?
--- @return boolean
function M.wants_window(smods)
  smods = smods or {}
  return (smods.split or '') ~= ''
    or smods.vertical == true
    or smods.horizontal == true
    or (smods.tab or -1) >= 0
end

--- Honour a command's window modifiers, if it had any. The structured
--- modifiers say whether to split. The raw ones say what kind, replayed.
--- @param opts { mods: string?, smods: table?, split: boolean? }?
function M.split_for(opts)
  if (opts and opts.split) or M.wants_window(opts and opts.smods) then
    vim.cmd(((opts and opts.mods) or '') .. ' split')
  end
end

--- Put the editor where a view is about to be drawn.
---
--- The answer belongs in the window the command was given in, not whichever
--- is current once the forge replies. The split is made after the reply. A
--- request that fails leaves no window behind.
--- @param o forge.Open?
function M.place(o)
  -- `hidden` is for a view redrawn because something was written to it, while
  -- the window it lives in still shows the buffer that did the writing.
  if not M.newest(o) or (o and o.hidden) then
    return
  end
  if o and o.win and vim.api.nvim_win_is_valid(o.win) then
    vim.api.nvim_set_current_win(o.win)
  end
  M.split_for(o)
end

--- Dress `win` for the view in `buf`.
---
--- Window options do not follow a buffer into a second window. Set them
--- wherever a view turns up. The `vim.wo[win][0]` scope gives them back when
--- the window shows something else. Core's own ftplugins do this.
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
--- Mappings and 'includeexpr' are set here, not in an ftplugin. An item is
--- markdown, and an ftplugin/markdown.lua would reach every markdown file you
--- open. 'includeexpr' goes last, after 'filetype'. A filetype plugin of your
--- own would otherwise overwrite it and leave |gf| pointing at nothing.
---
--- The buffer is replaced in place, never wiped and rebuilt. A window handle
--- held by a caller stays valid across a refresh.
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
  -- One extmark per group, not the list `hl_group` also takes. A composed one
  -- silently drops `url`. Core's |gx| reads `url` off the mark.
  for _, mark in ipairs(marks or {}) do
    if mark.line then
      vim.api.nvim_buf_set_extmark(buf, NS, mark.row, 0, { line_hl_group = mark.line })
    else
      local groups = type(mark.group) == 'table' and mark.group or { mark.group }
      for i, group in
        ipairs(groups --[[@as string[] ]])
      do
        vim.api.nvim_buf_set_extmark(buf, NS, mark.row, mark.col, {
          end_col = mark.end_col,
          hl_group = group,
          url = i == 1 and mark.url or nil,
        })
      end
    end
  end

  vim.b[buf].forge = info
  -- Sticky. A redraw carries no `from`, and the list that opened this item is
  -- still the list that opened it.
  from[buf] = (o and o.from) or from[buf]

  map.buf_default(buf, 'n', 'g?', '<Plug>(forge-help)', 'what the keys in this buffer do')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the list this item is in')
  map.buf_default(buf, 'n', 'R', '<Plug>(forge-refresh)', 'fetch this view again')
  map.buf_default(buf, 'n', 'gX', '<Plug>(forge-web)', ('open this view on %s'):format(u.host))
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

--- Do the one thing `key` names, without the menu. See |forge.Action|.
--- @param key string
function M.one(key)
  local u = M.current()
  if u and u.number then
    collected(u.collection).one(key)
  end
end

--- Open whatever `target` names, so long as it names `collection`.
---
--- Both commands arrive here. "." is the one target read off the editor
--- rather than parsed, and is resolved here before the grammar sees it.
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
    log.err(('that names %s; use %s'):format(nouns(t).many, OTHER[collection]))
    return
  end
  M.open(t, { mods = opts and opts.mods, smods = opts and opts.smods })
end

--- Leave an item for the list it came from, narrowed as that list was. The
--- whole collection only for an item that reached the editor another way.
function M.up()
  local u = M.current()
  if not u or not u.number then
    return
  end
  local name = from[vim.api.nvim_get_current_buf()]
  local back = name and uri.parse(name)
  M.open(back or { host = u.host, project = u.project, collection = u.collection }, { keep = true })
end

--- Fetch this view again, keeping the page. |:edit| rebuilds from the name.
--- A name holds no page, so it returns to the first.
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

--- Start something new in the collection this view holds, in the repository
--- the view names rather than the one you are standing in.
--- @param t forge.Target? what to add to, or the view being looked at
function M.create(t)
  t = t or M.current()
  if not t then
    return
  end

  local be = require('forge.backend').of(t.host)
  if not be then
    return
  end
  -- The host comes from the url. On an enterprise install that is not the host
  -- a name defaults to. The path comes from the target: a url cannot be
  -- chopped back down to one once a project nests under groups.
  be.create(t, M.field('url'):match('^https?://([^/]+)') or t.host)
end

--- Open this view on the forge it came from. What the buffer shows, not what
--- the cursor is on. <CR> follows a line.
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
    log.info('no more ' .. nouns(u).many)
    return
  end
  M.open(u, { page = page, cursors = paging.cursors })
end

--- The item the line under the cursor names. A list is read back by its sigil,
--- an item by the rows its stack was drawn at.
--- @param u forge.Uri
--- @return integer?
local function named_here(u)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  if u.number then
    local nav = stacked[vim.api.nvim_get_current_buf()]
    return nav and nav.rows[row] or nil
  end
  local be = require('forge.backend').of(u.host)
  if not be then
    return nil
  end
  local sigil = be.nouns[u.collection].sigil
  local number = vim.api.nvim_get_current_line():match(('^%s(%%d+)'):format(vim.pesc(sigil)))
  return number and tonumber(number) or nil
end

--- The list an item opened from here would belong to: this buffer when it is
--- the list, and whatever opened this one when it is an item following a
--- stack row.
--- @param u forge.Uri
--- @return string?
local function origin(u)
  local buf = vim.api.nvim_get_current_buf()
  return u.number and from[buf] or vim.api.nvim_buf_get_name(buf)
end

--- Open the item the line under the cursor names.
--- @param split boolean? open it beside the view it was asked for in
function M.open_at_cursor(split)
  local u = M.current()
  if not u then
    return
  end
  local number = named_here(u)
  if not number then
    return
  end
  M.open({
    host = u.host,
    project = u.project,
    collection = u.collection,
    number = number,
  }, { keep = true, split = split, from = origin(u) })
end

--- Step `delta` layers through the stack, up the buffer for a negative one.
--- Both ends wrap: a key that refuses reads as a key that broke.
--- @param delta integer
function M.walk_stack(delta)
  local u = M.current()
  local nav = stacked[vim.api.nvim_get_current_buf()]
  if not u or not u.number or not nav then
    return
  end
  local to = (nav.at - 1 + delta) % #nav.order + 1
  M.open({
    host = u.host,
    project = u.project,
    collection = u.collection,
    number = nav.order[to],
  }, { keep = true, from = origin(u) })
end

--- Step `delta` items through the list this one was opened from.
---
--- List-relative, as |:cnext| is quickfix-relative: an item reached by number,
--- by |gf| or from a stack has no list behind it and no neighbours. Neither
--- end wraps. A page holds a hundred, which is too many to come round.
--- @param delta integer
function M.step(delta)
  local u = M.current()
  if not u or not u.number then
    return
  end
  local said = nouns(u)
  local name = from[vim.api.nvim_get_current_buf()]
  local list = name and M.buffer_named(name) or nil
  if not list then
    log.info(('this %s was not opened from a list'):format(said.one))
    return
  end

  local numbers = M.paging(list).numbers
  local found
  for i, number in ipairs(numbers) do
    if number == u.number then
      found = i
      break
    end
  end
  -- The list is a page, and it may have turned since. Nothing to step from.
  if not found then
    log.info(('%s%d is not on the page that list is showing'):format(said.sigil, u.number))
    return
  end

  local to = found + delta
  if to < 1 then
    log.info(('already at the first of these %s'):format(said.many))
    return
  end
  if to > #numbers then
    log.info(('no more %s on this page'):format(said.many))
    return
  end
  M.open({
    host = u.host,
    project = u.project,
    collection = u.collection,
    number = numbers[to],
  }, { keep = true, from = name })
end

--- Warn when a connection came back truncated.
---
--- Every connection is capped. Every query asks for totalCount alongside the
--- nodes. A forge that will not count a large one leaves nothing to measure
--- the cap against, and the tail goes unreported.
--- @param connection table?
--- @param what string
function M.check_truncated(connection, what)
  -- By type. A null connection arrives as `vim.NIL`, which reads as present.
  -- So does an unanswered count.
  if type(connection) ~= 'table' then
    return
  end
  local shown = #(connection.nodes or {})
  local total = connection.totalCount
  if type(total) == 'number' and total > shown then
    log.warn(('showing %d of %d %s'):format(shown, total, what))
  end
end

return M
