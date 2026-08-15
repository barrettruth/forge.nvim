local gh = require('forge.gh')
local log = require('forge.log')
local text = require('forge.text')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

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
--- @field item_query string
--- @field list_query string
--- @field states table<string, string|string[]> what a half of the list is to github
--- @field state_hl table<string, string>
--- @field list_maps [string, string, string][]
--- @field item_maps [string, string, string][]?
--- @field state? fun(node: table): string the state to show, when not node.state
--- @field header? fun(node: table): string[] extra lines under State
--- @field badges? fun(node: table): string[] extra winbar segments
--- @field remember? fun(node: table): table what the buffer should keep of it

--- Draw a page of `spec`'s list.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.list(spec, t, o)
  local page = o.page or 1
  local cursors = o.cursors or {}
  local state = t.state == 'CLOSED' and 'closed' or 'open'
  local owner, repo = gh.slug(t)
  local variables = { owner = owner, repo = repo, states = spec.states[t.state or 'OPEN'] }
  if cursors[view.at(page)] then
    variables.after = cursors[view.at(page)]
  end

  gh.graphql({
    desc = ('%s %s in %s'):format(state, spec.many, view.where(t)),
    query = spec.list_query,
    variables = variables,
    cwd = o.cwd,
  }, function(data)
    local conn = vim.tbl_get(data, 'repository', spec.list_key)
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
      marks[#marks + 1] =
        { row = row, col = 0, end_col = 1 + #tostring(node.number), group = 'Tag' }
    end
    if #lines == 0 then
      lines = { ('No %s %s.'):format(state, spec.many) }
      marks = { { row = 0, col = 0, end_col = #lines[1], group = 'Comment' } }
    end

    local info = conn.pageInfo or {}
    local total = conn.totalCount or #lines
    local pages = math.max(1, math.ceil(total / view.PER_PAGE))
    local winbar = table.concat({
      view.hl('Title', spec.list_title),
      view.hl('Directory', ('%s/%s'):format(view.escape(u.owner), view.escape(u.repo))),
      view.hl(spec.state_hl[u.state or 'OPEN'] or '', state),
      ('%d/%d'):format(page, pages),
      view.hl('Comment', ('(%d)'):format(total)),
    }, ' ')

    view.place(o)
    local buf = view.render(u, lines, winbar, marks, spec.list_maps)
    if info.hasNextPage and info.endCursor then
      cursors[view.at(page + 1)] = info.endCursor
    end
    vim.b[buf].forge = { page = page, cursors = cursors, has_next = info.hasNextPage or false }
  end)
end

--- Draw one of `spec`'s items.
--- @param spec forge.Spec
--- @param t forge.Target
--- @param o forge.Open
function M.item(spec, t, o)
  local owner, repo = gh.slug(t)
  gh.graphql({
    desc = ('%s #%d in %s'):format(spec.one, t.number, view.where(t)),
    query = spec.item_query,
    variables = { owner = owner, repo = repo, number = t.number },
    cwd = o.cwd,
  }, function(data)
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

    local segments = {
      view.hl('Title', spec.item_title),
      view.hl('Tag', '#' .. node.number),
      view.hl(spec.state_hl[state] or '', state),
    }
    vim.list_extend(segments, (spec.badges and spec.badges(node)) or {})

    view.place(o)
    local buf = view.render(u, lines, table.concat(segments, ' '), nil, spec.item_maps)
    if spec.remember then
      vim.b[buf].forge = vim.tbl_extend('force', vim.b[buf].forge or {}, spec.remember(node))
    end
    view.check_truncated(node.labels, 'labels')
    view.check_truncated(node.comments, 'comments')
  end)
end

return M
