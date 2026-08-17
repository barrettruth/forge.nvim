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
      id number title state stateReason body createdAt url
      viewerCanUpdate
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      assignees(first: 10) { totalCount nodes { login } }
      milestone { title }
      issueType { name }
      parent { number }
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

--- The reason is written into the document rather than passed, because two
--- named closings read better in a menu than one closing and a second question.
--- DUPLICATE is left out: it takes the id of the issue duplicated, which is
--- another prompt, and github asks for it the same way.
local COMPLETED = [[
mutation($id: ID!) {
  closeIssue(input: {issueId: $id, stateReason: COMPLETED}) { clientMutationId }
}
]]

local NOT_PLANNED = [[
mutation($id: ID!) {
  closeIssue(input: {issueId: $id, stateReason: NOT_PLANNED}) { clientMutationId }
}
]]

local REOPEN = [[
mutation($id: ID!) {
  reopenIssue(input: {issueId: $id}) { clientMutationId }
}
]]

--- @type forge.Spec
local ISSUES = {
  one = 'issue',
  many = 'issues',
  item_title = 'ISSUE',
  list_title = 'ISSUES',
  item_key = 'issue',
  list_key = 'issues',
  list_path = 'issues',
  kind = 'is:issue',
  item_query = ISSUE_QUERY,
  list_query = LIST_QUERY,
  --- CLOSED is the fallback for one github gave no reason, which it backfilled
  --- COMPLETED on every issue closed before it started asking.
  --- What only an issue has. A type is github's own classification and not a
  --- label, however alike they look on its page, and a parent is a reference
  --- rather than a name: "#32280" is what |gf| already follows, and the title
  --- it stands for is one keystroke away.
  rows = function(node)
    local number = vim.tbl_get(node, 'parent', 'number')
    return {
      { key = 'Type', values = { vim.tbl_get(node, 'issueType', 'name') }, group = 'Tag' },
      {
        key = 'Parent',
        --- Through |vim.tbl_get| like the rest: github answers null for an
        --- issue with no parent, and a decoder that left that as `vim.NIL`
        --- would make it read as present and then index nothing.
        values = { number and ('#%d'):format(number) },
        group = 'Tag',
      },
    }
  end,
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
  item_maps = {
    { 'cc', '<Plug>(forge-act)', 'do something to this issue' },
  },
  remember = function(node)
    return { id = node.id, can_update = node.viewerCanUpdate }
  end,
  --- A closed issue's state is the reason it closed, never "CLOSED", so open is
  --- the one state to test for and everything else is closed.
  actions = {
    {
      label = 'Edit title and body',
      when = function(var)
        return var.can_update == true
      end,
      run = function(var)
        require('forge.edit').open(var)
      end,
    },
    {
      label = 'Close as completed',
      query = COMPLETED,
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Close as not planned',
      query = NOT_PLANNED,
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Reopen issue',
      query = REOPEN,
      when = function(var)
        return var.state ~= 'OPEN' and var.can_update == true
      end,
    },
  },
}

--- What this issue can be asked to do, as it stands.
--- @param var forge.ItemVar
--- @return forge.Action[]
function M.actions(var)
  return collection.actions(ISSUES, var)
end

--- Offer those, and do the one chosen.
function M.act()
  collection.act(ISSUES)
end

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
--- A bare number is taken as an issue: github numbers both from one counter,
--- so only github can say which it is.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'issues', opts)
end

return M
