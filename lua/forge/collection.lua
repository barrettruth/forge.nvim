local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local vcs = require('forge.vcs')
local view = require('forge.view')

local M = {}

--- One document for both collections: `type: ISSUE` searches issues and pull
--- requests alike, and which of them come back is decided by the `is:` forge
--- puts in the query. The repository is asked for alongside, since a search
--- answers for no particular one and a view still needs the name github
--- spells it with.
local SEARCH_QUERY = [[
query($owner: String!, $repo: String!, $q: String!, $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
  }
  search(query: $q, type: ISSUE, first: 100, after: $after) {
    issueCount
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on Issue { number title state stateReason }
      ... on PullRequest { number title state isDraft }
    }
  }
}
]]

--- Search reaches a thousand results and no further, however many it reports.
local REACHABLE = 1000

--- Qualifiers forge owns, because repeating one of these widens a search
--- rather than narrowing it: two `repo:` are two repositories, and `is:issue`
--- beside `is:pr` is both. The name a view carries would stop being true.
local OWNED = { org = true, repo = true, user = true }
local KINDS = { ['is:issue'] = true, ['is:pr'] = true, ['type:issue'] = true, ['type:pr'] = true }

--- What to send github for `query`, given what the user typed.
---
--- Their string is passed through byte for byte apart from the qualifiers
--- above, so quoting, negation and commas are github's to read rather than
--- ours to parse. Only the whole words forge owns are dropped, which leaves
--- the spaces inside a quoted value where they were.
--- @param spec forge.Spec
--- @param t forge.Target
--- @return string
local function searching(spec, t)
  local sorted = false
  local kept = (t.query or ''):gsub('%S+', function(word)
    local key = word:match('^%-?([%w-]+):')
    if key == 'sort' then
      sorted = true
    end
    if OWNED[key] or KINDS[word:lower()] then
      return ''
    end
    return nil
  end)
  local owner, repo = gh.slug(t)
  --- Ordered like the plain list unless they asked otherwise: `search` takes
  --- no orderBy, so the only way to say it is in the query, and its own
  --- default is relevance.
  local parts = { ('repo:%s/%s'):format(owner, repo), spec.kind }
  if not sorted then
    parts[#parts + 1] = 'sort:updated-desc'
  end
  parts[#parts + 1] = kept
  return table.concat(parts, ' ')
end

--- Something an item can be asked to do, and when it can be asked.
---
--- Data rather than a closure: every one of them is the same round trip with a
--- different document, and the reason a state can be written into the document
--- rather than passed is that github spells its enums in the query.
--- @class forge.Action
--- @field label string what the picker shows, in github's own words
--- @field said string what the progress message says of it
--- @field query string the mutation to send
--- @field when fun(var: forge.ItemVar): boolean

--- Everything that distinguishes one collection from another.
---
--- Issues and pull requests are drawn by the same two functions below; a spec
--- is the whole of the difference between them. Anything genuinely particular
--- to one — a pull request's branch line, its draft state, its diffstat — is a
--- function here rather than a branch there.
--- @class forge.Spec
--- @field one string the singular, as said to a person
--- @field many string the plural, as said to a person
--- @field item_title string what the winbar calls one
--- @field list_title string what the winbar calls the list
--- @field item_key string the response field holding one
--- @field list_key string the response field holding the connection
--- @field list_path string what github calls the list in a url
--- @field kind string the `is:` that keeps a search to this collection
--- @field item_query string
--- @field list_query string
--- @field state_hl table<string, string>
--- @field list_maps [string, string, string][]
--- @field item_maps [string, string, string][]?
--- @field state? fun(node: table): string the state to show, when not node.state
--- @field header? fun(node: table): string[] extra lines under State
--- @field badges? fun(node: table): string[] extra winbar segments
--- @field stat? fun(node: table): string[] winbar segments for the right edge
--- @field remember? fun(node: table, repo: table): table what the buffer should
--- keep of it
--- @field actions? forge.Action[] what "c" offers

--- Where the answer goes is settled before the round trip, since by the time
--- one comes back the current window is wherever you wandered to.
--- @param var forge.ItemVar
--- @param action forge.Action
local function mutate(var, action)
  local u = view.current()
  if not u then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local cwd = vcs.dir()
  gh.graphql({
    desc = ('%s %s'):format(var.tag, action.said),
    query = action.query,
    variables = { id = var.id },
    cwd = cwd,
  }, function()
    view.open(u, { keep = true, win = win, cwd = cwd })
  end)
end

--- What `spec`'s item can be asked to do, as it stands.
--- @param spec forge.Spec
--- @param var forge.ItemVar
--- @return forge.Action[]
function M.actions(spec, var)
  return vim.tbl_filter(function(action)
    return action.when(var)
  end, spec.actions or {})
end

--- Offer those, and do the one chosen. A menu rather than a key each, because
--- naming the action is the only confirmation a state flip gets.
--- @param spec forge.Spec
function M.act(spec)
  local var = vim.b.forge or {}
  local can = M.actions(spec, var)
  --- Refused and finished are different things: one is worth a warning, the
  --- other is just how a merged pull request is.
  if #can == 0 then
    if var.can_update == false then
      log.warn(('github does not let you change this %s'):format(spec.one))
    else
      log.info(('nothing to do to a %s %s'):format((var.state or '?'):lower(), spec.one))
    end
    return
  end
  vim.ui.select(can, {
    prompt = ('%s %s'):format(var.label or '', var.tag or ''),
    format_item = function(action)
      return action.label
    end,
  }, function(action)
    if action then
      mutate(var, action)
    end
  end)
end

--- Draw a page of `spec`'s list.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.list(spec, t, o)
  local page = o.page or 1
  local cursors = o.cursors or {}
  local owner, repo = gh.slug(t)
  local variables = { owner = owner, repo = repo }
  if t.query then
    variables.q = searching(spec, t)
  end
  if cursors[page] then
    variables.after = cursors[page]
  end

  local settle = view.busy(t)
  gh.graphql({
    desc = ('%s in %s'):format(spec.many, view.where(t)),
    query = t.query and SEARCH_QUERY or spec.list_query,
    variables = variables,
    cwd = o.cwd,
  }, function(data)
    settle()
    local conn = t.query and data.search or vim.tbl_get(data, 'repository', spec.list_key)
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not conn or not u then
      log.err(('no %s in %s'):format(spec.many, view.where(t)))
      return
    end

    local nodes = conn.nodes or {}
    local width = 1
    for _, node in ipairs(nodes) do
      width = math.max(width, #tostring(node.number))
    end
    local format = ('#%%-%dd %%s'):format(width)

    local lines, marks = {}, {}
    for _, node in ipairs(nodes) do
      local row = #lines
      lines[row + 1] = format:format(node.number, node.title)
      marks[#marks + 1] = {
        row = row,
        col = 0,
        end_col = 1 + #tostring(node.number),
        group = spec.state_hl[(spec.state and spec.state(node)) or node.state] or 'Tag',
      }
    end
    if #lines == 0 then
      lines = { ('No %s.'):format(spec.many) }
      marks = { { row = 0, col = 0, end_col = #lines[1], group = 'Comment' } }
    end

    local page_info = conn.pageInfo or {}
    local total = conn.totalCount or conn.issueCount or #lines
    --- A search reports every match and hands over the first thousand, so the
    --- page count is of what can be reached and the total says how much was
    --- found.
    local last =
      math.max(1, math.ceil(math.min(total, t.query and REACHABLE or total) / view.PER_PAGE))

    --- @type forge.ListVar
    local info = {
      kind = 'list',
      label = spec.list_title,
      repo = ('%s/%s'):format(u.owner, u.repo),
      url = ('%s/%s'):format(data.repository.url, spec.list_path)
        .. (t.query and ('?q=' .. vim.uri_encode(searching(spec, t))) or ''),
      query = t.query or '',
      pages = ('%d/%d'):format(page, last),
      total = tostring(total),
    }

    view.place(o)
    local buf = view.render(u, lines, info, marks, spec.list_maps, o)
    if page_info.hasNextPage and page_info.endCursor then
      cursors[page + 1] = page_info.endCursor
    end
    view.paged(buf, page, cursors, page_info.hasNextPage or false)
  end, settle)
end

--- Draw one of `spec`'s items.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.item(spec, t, o)
  local owner, repo = gh.slug(t)
  local settle = view.busy(t)
  gh.graphql({
    desc = ('%s #%d in %s'):format(spec.one, t.number, view.where(t)),
    query = spec.item_query,
    variables = { owner = owner, repo = repo, number = t.number },
    cwd = o.cwd,
  }, function(data)
    settle()
    local node = vim.tbl_get(data, 'repository', spec.item_key)
    local u = uri.of(vim.tbl_get(data, 'repository', 'nameWithOwner'), t)
    if not node or not u then
      log.err(('no %s #%d in %s'):format(spec.one, t.number, view.where(t)))
      return
    end

    local state = (spec.state and spec.state(node)) or node.state or '?'
    local labels = {}
    for _, label in ipairs(vim.tbl_get(node, 'labels', 'nodes') or {}) do
      labels[#labels + 1] = label.name
    end

    local lines = {
      ('# %s'):format(node.title),
      '',
      ('- Author: %s (%s)'):format(
        vim.tbl_get(node, 'author', 'login') or 'ghost',
        node.authorAssociation or 'NONE'
      ),
      ('- State: %s, opened %s'):format(state, text.age(node.createdAt)),
    }
    vim.list_extend(lines, (spec.header and spec.header(node)) or {})
    if #labels > 0 then
      lines[#lines + 1] = ('- Labels: %s'):format(table.concat(labels, ', '))
    end
    lines[#lines + 1] = ''
    text.append_body(lines, node.body)
    text.append_comments(lines, node.comments)

    local badges = (spec.badges and spec.badges(node)) or {}
    local stat = (spec.stat and spec.stat(node)) or {}

    --- @type forge.ItemVar
    local info = {
      kind = 'item',
      label = spec.item_title,
      repo = ('%s/%s'):format(u.owner, u.repo),
      url = node.url,
      state = state,
      state_hl = spec.state_hl[state] or 'Normal',
      tag = '#' .. node.number,
      title = node.title or '',
      badges = #badges > 0 and (' ' .. table.concat(badges, ' ')) or '',
      --- Its bar belongs to the value: a `%(…%)` group wrapped round a
      --- `%{%…%}` is dropped whole, taking the separator with it.
      stat = #stat > 0 and (' | ' .. table.concat(stat, ' ')) or '',
    }
    if spec.remember then
      info = vim.tbl_extend('force', info, spec.remember(node, data.repository))
    end

    view.place(o)
    view.render(u, lines, info, nil, spec.item_maps, o)
    view.check_truncated(node.labels, 'labels')
    view.check_truncated(node.comments, 'comments')
  end, settle)
end

return M
