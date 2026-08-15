local collection = require('forge.collection')
local view = require('forge.view')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!, $after: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    url
    issues(first: 100, after: $after, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number title state stateReason }
    }
  }
}
]]

local ISSUE_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    issue(number: $number) {
      number title state stateReason body createdAt url
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
    }
  }
}
]]

--- How a closed issue ended. Each of these implies closed, so the winbar says
--- the reason and not both, as MERGED and DRAFT already do for a pull request.
--- REOPENED is left out: that one is open, and says so.
local REASON = {
  COMPLETED = 'COMPLETED',
  DUPLICATE = 'DUPLICATE',
  NOT_PLANNED = 'NOT PLANNED',
}

--- @type forge.Spec
local ISSUES = {
  one = 'issue',
  many = 'issues',
  item_title = 'ISSUE',
  list_title = 'ISSUES',
  item_key = 'issue',
  list_key = 'issues',
  list_path = 'issues',
  item_query = ISSUE_QUERY,
  list_query = LIST_QUERY,
  --- CLOSED is the fallback for one github gave no reason, which it backfilled
  --- COMPLETED on every issue closed before it started asking.
  state_hl = {
    OPEN = view.HL.live,
    CLOSED = view.HL.done,
    COMPLETED = view.HL.done,
    DUPLICATE = view.HL.done,
    ['NOT PLANNED'] = view.HL.inert,
  },
  state = function(node)
    return REASON[node.stateReason] or node.state
  end,
  list_maps = {
    { '<CR>', '<Plug>(forge-open)', 'open the issue under the cursor' },
    { 'o', '<Plug>(forge-open-split)', 'open the issue under the cursor in a split' },
    { ']i', '<Plug>(forge-next-page)', 'the next page of issues' },
    { '[i', '<Plug>(forge-prev-page)', 'the previous page of issues' },
  },
}

--- Draw the issue view `t` names.
--- @param t forge.Target
--- @param o forge.Open
function M.show(t, o)
  if t.number then
    collection.item(ISSUES, t, o)
  else
    collection.list(ISSUES, t, o)
  end
end

--- Open whatever `target` names, so long as it names issues.
---
--- A bare number is taken as an issue, since github numbers issues and pull
--- requests from one counter and only github can say which it is. Anything
--- that names itself is believed, and refused here if it named the other one.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'issues', opts)
end

return M
