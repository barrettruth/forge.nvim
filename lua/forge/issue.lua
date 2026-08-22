local collection = require('forge.collection')
local view = require('forge.view')

local M = {}

--- How a closed issue ended. Each implies closed. The winbar draws the reason
--- alone. REOPENED is left out. That one is open, and says so.
local REASON = {
  COMPLETED = 'COMPLETED',
  DUPLICATE = 'DUPLICATE',
  NOT_PLANNED = 'NOT PLANNED',
}

--- @type forge.Spec
local ISSUES = {
  collection = 'issues',
  -- What only an issue has. A type is github's own classification, not a
  -- label. A parent is written as the reference |gf| already follows.
  rows = function(node)
    local number = vim.tbl_get(node, 'parent', 'number')
    return {
      { key = 'Type', values = { vim.tbl_get(node, 'issueType', 'name') }, group = 'Tag' },
      {
        key = 'Parent',
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
    { '<CR>', '<Plug>(forge-open)', 'open the {one} under the cursor' },
    { 'o', '<Plug>(forge-open-split)', 'open the {one} under the cursor in a split' },
    { ']i', '<Plug>(forge-next-page)', 'the next page of {many}' },
    { '[i', '<Plug>(forge-prev-page)', 'the previous page of {many}' },
  },
  item_maps = {
    { 'cc', '<Plug>(forge-act)', 'do something to this {one}' },
    { 'cE', '<Plug>(forge-edit)', "edit this {one}'s title and body" },
    { ']i', '<Plug>(forge-next-item)', 'the next {one} in the list this came from' },
    { '[i', '<Plug>(forge-prev-item)', 'the previous {one} in the list this came from' },
  },
  remember = function(node)
    return { id = node.id, can_update = node.viewerCanUpdate }
  end,
  -- A closed issue's state is the reason it closed, never "CLOSED". OPEN is
  -- the one state to test for. Everything else is closed.
  actions = {
    {
      label = 'Edit title and body',
      key = 'edit',
      when = function(var)
        return var.can_update == true
      end,
      run = function(var)
        require('forge.edit').open(var)
      end,
    },
    {
      label = 'Close as completed',
      write = 'complete',
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Close as not planned',
      write = 'not_planned',
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    -- For a forge that keeps no reason an issue was closed. The two named
    -- closings above name writes it has none of.
    {
      label = 'Close {one}',
      write = 'close',
      when = function(var)
        return var.state == 'OPEN' and var.can_update == true
      end,
    },
    {
      label = 'Reopen {one}',
      write = 'reopen',
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

--- Do the one thing `key` names, if it is offered.
--- @param key string
function M.one(key)
  collection.one(ISSUES, key)
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

--- Open whatever `target` names, so long as it names issues. A bare number is
--- one. github numbers both collections from a single counter.
--- @param target string?
--- @param opts vim.api.keyset.create_user_command.command_args? window modifiers
function M.open(target, opts)
  view.command(target, 'issues', opts)
end

return M
