--- Completing a github search, without asking github.
---
--- Everything here is a literal. A qualifier's real values, such as which
--- labels a repository has, cannot be known without a request. A request
--- behind <Tab> is either slow or stale. Those are not offered at all.

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

--- Qualifiers naming a person. "@me" is the only value knowable here, and it
--- covers `author:@me` and `review-requested:@me`.
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

--- Qualifiers whose value forge cannot know. A label or milestone belongs to
--- the repository. A date or a count belongs to you.
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
--- Neovim hands over the word under the cursor, split on whitespace and with
--- no notion of quotes. `label:"good fir` arrives as `fir`. That matches
--- nothing and completes to nothing, which is the right answer.
--- @param lead string the word being completed
--- @return string[]
function M.complete(lead)
  -- Negation reads the same. Peel it off and put it back.
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
