--- Completing a github search, without asking github.
---
--- Everything here is a literal: nothing is fetched, nothing is remembered
--- between keystrokes, and the answer to any given <Tab> is the same as it was
--- yesterday. A qualifier's real values — which labels a repository has, who
--- its people are — cannot be known without a request, so they are not offered
--- at all rather than offered slowly or from a copy that has gone stale.

local M = {}

--- The values a qualifier takes, where github's set is closed.
--- @type table<string, string[]>
local VALUES = {
  archived = { 'true', 'false' },
  draft = { 'true', 'false' },
  ['in'] = { 'title', 'body', 'comments' },
  is = {
    'open',
    'closed',
    'merged',
    'unmerged',
    'draft',
    'locked',
    'unlocked',
    'public',
    'private',
    'archived',
    'queued',
  },
  linked = { 'pr', 'issue' },
  no = { 'label', 'assignee', 'milestone', 'project' },
  reason = { 'completed', '"not planned"' },
  review = { 'none', 'required', 'approved', 'changes_requested' },
  state = { 'open', 'closed' },
  status = { 'pending', 'success', 'failure' },
}

for _, field in ipairs({
  'created',
  'updated',
  'comments',
  'interactions',
  'reactions',
  'reactions-+1',
  'reactions--1',
  'reactions-heart',
  'reactions-smile',
  'reactions-tada',
  'reactions-thinking_face',
}) do
  VALUES.sort = VALUES.sort or {}
  table.insert(VALUES.sort, field .. '-asc')
  table.insert(VALUES.sort, field .. '-desc')
end

--- Qualifiers naming a person. "@me" is the only one of those knowable here,
--- and between `author:@me` and `review-requested:@me` it is most of why you
--- would search at all.
local USERS = {
  'assignee',
  'author',
  'commenter',
  'involves',
  'mentions',
  'review-requested',
  'reviewed-by',
  'user-review-requested',
}

--- Qualifiers whose value forge cannot know: a label or milestone belongs to
--- the repository, a date or a count to you.
local FREE = {
  'base',
  'closed',
  'comments',
  'created',
  'head',
  'interactions',
  'label',
  'language',
  'merged',
  'milestone',
  'project',
  'reactions',
  'sha',
  'team',
  'team-review-requested',
  'updated',
}

--- Every qualifier, spelled as it is typed.
local KEYS = {}
for key in pairs(VALUES) do
  KEYS[#KEYS + 1] = key .. ':'
end
for _, list in ipairs({ USERS, FREE }) do
  for _, key in ipairs(list) do
    KEYS[#KEYS + 1] = key .. ':'
  end
end
table.sort(KEYS)

local function knows_user(key)
  return vim.tbl_contains(USERS, key)
end

--- What could follow what has been typed so far.
---
--- Only the word under the cursor is read, which is what Neovim gives us: it
--- splits on whitespace and does not know about quotes, so `label:"good fir`
--- arrives as `fir`. That matches no qualifier and no value, and the empty
--- answer is the right one — there is nothing forge could offer inside a
--- value anyway.
--- @param lead string the word being completed
--- @return string[]
function M.complete(lead)
  --- Negation reads the same, so it is peeled off and put back.
  local not_, rest = lead:match('^(%-?)(.*)$')
  local key, typed = rest:match('^([%w-]+):(.*)$')

  --- @param candidates string[]
  --- @param prefix string what to put in front of each, to replace the word
  --- @param partial string
  local function matching(candidates, prefix, partial)
    local out = {}
    for _, candidate in ipairs(candidates) do
      if vim.startswith(candidate, partial) then
        out[#out + 1] = not_ .. prefix .. candidate
      end
    end
    return out
  end

  if not key then
    return matching(KEYS, '', rest)
  end
  if VALUES[key] then
    return matching(VALUES[key], key .. ':', typed)
  end
  if knows_user(key) then
    return matching({ '@me' }, key .. ':', typed)
  end
  return {}
end

return M
