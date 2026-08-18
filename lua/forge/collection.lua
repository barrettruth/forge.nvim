local backend = require('forge.backend')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- What a forge calls a collection when it says it out loud.
---
--- gitlab says "merge request", writes "!2" where github writes "#2", and puts
--- MRS in a winbar where github puts PRS. None of that is the collection's to
--- decide, so all of it belongs to whichever forge answered.
--- @class forge.Nouns
--- @field one string the singular, as said to a person
--- @field many string the plural, as said to a person
--- @field item string what the winbar calls one
--- @field list string what the winbar calls the list
--- @field sigil string what the forge writes in front of a number

--- What a fetch needs beyond the target it is for.
--- @class forge.Fetch
--- @field desc string what to say while it is in flight
--- @field cwd string? where to run the CLI, which is where it resolves the repository
--- @field after string? the cursor a page past the first is asked for with

--- One page of a list, as the renderer reads one.
--- @class forge.Page
--- @field project string the path the forge spells the repository with
--- @field nodes table[] a row each, holding at least a number, a title and a state
--- @field total integer? how many the collection holds, where the forge counts them
--- @field reach integer? how many of those can be paged to, where that is fewer
--- @field cursor string? what to ask the page after this one for
--- @field has_next boolean
--- @field url string the list's own page on the forge, narrowed as this one is

--- One item, as the renderer reads one.
--- @class forge.Item
--- @field project string the path the forge spells the repository with
--- @field node table the item itself
--- @field repo table what the forge said about the repository around it

--- @class forge.Head
--- @field project string? the path the forge spells the repository with
--- @field number integer? absent where the branch has no pull request yet

--- One change to send, in the words above the seam.
---
--- `kind` says which of the three shapes the rest is, since an action names
--- its own write and the other two are composed from what was typed.
--- @class forge.Write
--- @field kind 'act'|'edit'|'merge'
--- @field desc string what to say while it is in flight
--- @field collection forge.Collection
--- @field var forge.ItemVar the item being changed
--- @field cwd string? where to run the CLI
--- @field query string? for 'act', the write the action carried
--- @field title string? for 'edit'
--- @field body string? for 'edit' and 'merge'
--- @field headline string? for 'merge', the subject of the commit it writes
--- @field method 'SQUASH'|'MERGE'? for 'merge'
--- @field auto boolean? for 'merge', wait for the forge to allow it rather than
--- merging now

--- One forge, as everything above here sees it.
---
--- Nothing outside a backend knows which forge answered: a call site that
--- tests the host is the multiplication kernel idea 1 refuses. A capability
--- is the presence of an optional method and never a flag, so a forge that
--- cannot do something simply does not answer for it.
--- @class forge.Backend
--- @field nouns table<forge.Collection, forge.Nouns> its own words for each
--- @field writes table<forge.Collection, table<string, string>> the write behind
--- each change a menu offers, by the name |forge.Action| gives it
--- @field list fun(t: forge.Target, f: forge.Fetch, on_done: fun(page: forge.Page?), on_fail: fun()?)
--- @field item fun(t: forge.Target, f: forge.Fetch, on_done: fun(one: forge.Item?), on_fail: fun()?)
--- @field head fun(t: forge.Target, branch: string, f: forge.Fetch, on_done: fun(found: forge.Head))
--- @field write fun(w: forge.Write, on_done: fun(), on_fail: fun()?)
--- @field create fun(t: forge.Target, host: string) start something new, however
--- the forge is asked for one
--- @field pull_ref fun(number: integer): string where it publishes a pull
--- request's head, for git to fetch by

--- Something an item can be asked to do, and when it can be asked.
---
--- Data rather than a closure: every one of them is the same round trip with a
--- different write, and the reason a state can be written into that write
--- rather than passed is that a forge spells its own enums.
--- @class forge.Action
--- @field label string what the picker shows, in the forge's own words
--- @field write? string which of the backend's writes it sends
--- @field query? string that write itself, filled in when the action is offered
--- @field run? fun(var: forge.ItemVar) what to do instead of sending one
--- @field when fun(var: forge.ItemVar): boolean

--- Everything that distinguishes one collection from another.
---
--- Issues and pull requests are drawn by the same two functions below; a spec
--- is the whole of the difference between them. Anything genuinely particular
--- to one — a pull request's branch line, its draft state, its diffstat — is a
--- function here rather than a branch there. What is particular to a *forge*
--- is not here at all; see |forge.Backend|.
--- @class forge.Spec
--- @field collection forge.Collection which of the two it is
--- @field state_hl table<string, string>
--- @field list_maps [string, string, string][]
--- @field item_maps [string, string, string][]?
--- @field state? fun(node: table): string the state to show, when not node.state
--- @field about? fun(node: table): string what the winbar says after the
--- state, when something other than the title belongs there
--- @field rows? fun(node: table): forge.Row[] metadata only it has, drawn
--- among the people it belongs with
--- @field badges? fun(node: table): string[] extra winbar segments
--- @field stat? fun(node: table): string[] winbar segments for the right edge
--- @field remember? fun(node: table, repo: table): table what the buffer should
--- keep of it
--- @field actions? forge.Action[] what "c" offers

--- The forge an item came from.
---
--- The url it answered with, rather than the host its name defaults to: on an
--- enterprise install those are two different places, and only the url has
--- been anywhere.
--- @param var forge.ItemVar
--- @return forge.Backend?
local function answered(var)
  return backend.of((var.url or ''):match('^https?://([^/]+)'))
end

--- Where the answer goes is settled before the round trip, since by the time
--- one comes back the current window is wherever you wandered to.
--- @param be forge.Backend
--- @param spec forge.Spec
--- @param var forge.ItemVar
--- @param action forge.Action
local function mutate(be, spec, var, action)
  local u = view.current()
  if not u then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local cwd = vcs.dir()
  be.write({
    kind = 'act',
    desc = ('%s %s'):format(var.tag, action.label),
    collection = spec.collection,
    var = var,
    query = action.query,
    cwd = cwd,
  }, function()
    view.open(u, { keep = true, win = win, cwd = cwd })
  end)
end

--- The write comes back on the action rather than being looked up when one is
--- picked, so what a menu offers is the whole of what it would send.
--- @param be forge.Backend
--- @param spec forge.Spec
--- @param var forge.ItemVar
--- @return forge.Action[]
local function offering(be, spec, var)
  local writes = be.writes[spec.collection] or {}
  local can = {}
  for _, action in ipairs(spec.actions or {}) do
    if action.when(var) then
      can[#can + 1] = action.write
          and vim.tbl_extend('force', action, { query = writes[action.write] }) --[[@as forge.Action]]
        or action
    end
  end
  return can
end

--- What `spec`'s item can be asked to do, as it stands.
--- @param spec forge.Spec
--- @param var forge.ItemVar
--- @return forge.Action[]
function M.actions(spec, var)
  local be = answered(var)
  return be and offering(be, spec, var) or {}
end

--- Offer those, and do the one chosen. A menu rather than a key each, because
--- naming the action is the only confirmation a state flip gets.
--- @param spec forge.Spec
function M.act(spec)
  local var = vim.b.forge or {}
  local be = answered(var)
  if not be then
    return
  end
  local nouns = be.nouns[spec.collection]
  local can = offering(be, spec, var)
  --- Refused and finished are different things: one is worth a warning, the
  --- other is just how a merged pull request is.
  if #can == 0 then
    if var.can_update == false then
      --- The forge is named out of the url it answered with, which on an
      --- enterprise install is not the host its own name defaults to.
      local host = (var.url or ''):match('^https?://([^/]+)') or 'the forge'
      log.warn(('%s does not let you change this %s'):format(host, nouns.one))
    else
      log.info(('nothing to do to a %s %s'):format((var.state or '?'):lower(), nouns.one))
    end
    return
  end
  vim.ui.select(can, {
    --- The verb is "cc" itself, and what every choice below has in common:
    --- each one writes, and each is gated on the same permission. A colon
    --- because a list follows, not a question nothing here answers.
    prompt = ('Change %s %s:'):format(nouns.one, var.tag or ''),
    format_item = function(action)
      return action.label
    end,
  }, function(action)
    if not action then
      return
    end
    if action.run then
      action.run(var)
    else
      mutate(be, spec, var, action)
    end
  end)
end

--- Draw a page of `spec`'s list.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.list(spec, t, o)
  local be = backend.of(t.host)
  if not be then
    return
  end
  local page = o.page or 1
  local cursors = o.cursors or {}
  local nouns = be.nouns[t.collection]

  local settle = view.busy(t)
  be.list(t, {
    desc = ('%s in %s'):format(nouns.many, view.where(t)),
    after = cursors[page],
    cwd = o.cwd,
  }, function(answer)
    settle()
    local u = answer and uri.of(answer.project, t)
    if not answer or not u then
      log.err(('no %s in %s'):format(nouns.many, view.where(t)))
      return
    end

    local nodes = answer.nodes
    local width = 1
    for _, node in ipairs(nodes) do
      width = math.max(width, #tostring(node.number))
    end
    local format = ('%s%%-%dd %%s'):format(nouns.sigil, width)

    local lines, marks = {}, {}
    for _, node in ipairs(nodes) do
      local row = #lines
      lines[row + 1] = format:format(node.number, node.title)
      marks[#marks + 1] = {
        row = row,
        col = 0,
        end_col = #nouns.sigil + #tostring(node.number),
        group = spec.state_hl[(spec.state and spec.state(node)) or node.state] or 'Tag',
      }
    end
    if #lines == 0 then
      lines = { ('No %s.'):format(nouns.many) }
      marks = { { row = 0, col = 0, end_col = #lines[1], group = 'Comment' } }
    end

    --- The reach rather than the total: a forge that hands over only the first
    --- so many of a search still reports how many it found.
    local last = answer.reach and math.max(1, math.ceil(answer.reach / view.PER_PAGE))

    --- @type forge.ListVar
    local info = {
      kind = 'list',
      label = nouns.list,
      repo = u.project,
      url = answer.url,
      query = t.query or '',
      pages = last and ('%d/%d'):format(page, last) or ('%d/?'):format(page),
      total = answer.total and tostring(answer.total) or nil,
    }

    view.place(o)
    local buf = view.render(u, lines, info, marks, spec.list_maps, o)
    if answer.cursor then
      cursors[page + 1] = answer.cursor
    end
    view.paged(buf, page, cursors, answer.has_next)
  end, settle)
end

--- What the forge answered about one message, as the renderer reads a message.
--- @param node table anything with an author, an association and a createdAt
--- @return forge.Comment
local function said(node)
  return {
    --- github answers a deleted account with no author at all, and ghost is
    --- the name it puts on one everywhere else.
    author = vim.tbl_get(node, 'author', 'login') or 'ghost',
    association = node.authorAssociation,
    created_at = node.createdAt,
    body = node.body,
  }
end

--- A comments connection, as the conversation it holds and how long that
--- conversation is.
--- @param connection table?
--- @return forge.Comment[]
--- @return integer? total
local function conversation(connection)
  --- By type throughout: a null connection arrives as `vim.NIL`, which reads
  --- as present, and so does a count that was not answered.
  local held = type(connection) == 'table' and connection or {}
  local out = {}
  for _, node in ipairs(type(held.nodes) == 'table' and held.nodes or {}) do
    out[#out + 1] = said(node)
  end
  return out, type(held.totalCount) == 'number' and held.totalCount or nil
end

--- Draw one of `spec`'s items.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.item(spec, t, o)
  local be = backend.of(t.host)
  if not be then
    return
  end
  local nouns = be.nouns[t.collection]
  local named = ('%s %s%d in %s'):format(nouns.one, nouns.sigil, t.number, view.where(t))

  local settle = view.busy(t)
  be.item(t, { desc = named, cwd = o.cwd }, function(answer)
    settle()
    local u = answer and uri.of(answer.project, t)
    if not answer or not u then
      log.err(('no %s'):format(named))
      return
    end
    local node = answer.node

    local state = (spec.state and spec.state(node)) or node.state or '?'
    local labels = {}
    for _, label in ipairs(vim.tbl_get(node, 'labels', 'nodes') or {}) do
      labels[#labels + 1] = label.name
    end

    --- People, then what it is, in a fixed order so a fact is always in the
    --- same place.
    --- @type forge.Row[]
    local rows = {
      { key = 'Assignees', values = text.logins(node.assignees), group = text.LOGIN },
    }
    vim.list_extend(rows, (spec.rows and spec.rows(node)) or {})
    rows[#rows + 1] = { key = 'Labels', values = labels, group = 'Tag' }
    rows[#rows + 1] =
      { key = 'Milestone', values = { vim.tbl_get(node, 'milestone', 'title') }, group = 'Tag' }

    --- Not the state: the winbar has it, and always on screen.
    local lines = { ('# %s'):format(node.title), '' }
    --- @type forge.Mark[]
    local marks = {}
    text.append_author(lines, marks, said(node))
    text.append_rows(lines, marks, rows)
    lines[#lines + 1] = ''
    --- github's sentence. A comment has no description to be missing.
    text.append_body(lines, marks, node.body, 'No description provided.')
    local comments, count = conversation(node.comments)
    text.append_comments(lines, marks, comments, count)

    local badges = (spec.badges and spec.badges(node)) or {}
    local stat = (spec.stat and spec.stat(node)) or {}

    --- @type forge.ItemVar
    local info = {
      kind = 'item',
      label = nouns.item,
      repo = u.project,
      url = node.url,
      about = spec.about and spec.about(node) or (node.title or ''),
      state = state,
      state_hl = spec.state_hl[state] or 'Normal',
      tag = nouns.sigil .. node.number,
      title = node.title or '',
      --- What "cc" hands the editor: the title and body as they stand, in the
      --- shape they are written back in.
      edit = ('%s\n\n%s'):format(node.title or '', node.body or ''),
      badges = #badges > 0 and (' ' .. table.concat(badges, ' ')) or '',
      --- The bar divides the two, so with no badge there is nothing to
      --- divide and it would be marooned at the end of the gap `%=` opened.
      stat = #stat > 0 and ((#badges > 0 and ' | ' or ' ') .. table.concat(stat, ' ')) or '',
    }
    if spec.remember then
      info = vim.tbl_extend('force', info, spec.remember(node, answer.repo))
    end

    view.place(o)
    view.render(u, lines, info, marks, spec.item_maps, o)
    view.check_truncated(node.labels, 'labels')
    view.check_truncated(node.assignees, 'assignees')
    view.check_truncated(node.comments, 'comments')
  end, settle)
end

return M
