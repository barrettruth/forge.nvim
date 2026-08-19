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

--- Qualifiers whose value forge does not complete. A label or milestone
--- belongs to the repository, a date or a count belongs to you, and a person
--- belongs to the forge. "@me" would be the one name knowable without asking,
--- and offering the only one forge happens to know reads as the set.
local FREE = {
  'assignee',
  'author',
  'base',
  'closed',
  'comments',
  'commenter',
  'created',
  'head',
  'interactions',
  'involves',
  'label',
  'language',
  'mentions',
  'merged',
  'milestone',
  'project',
  'reactions',
  'review-requested',
  'reviewed-by',
  'sha',
  'team',
  'team-review-requested',
  'updated',
  'user-review-requested',
}

--- Every qualifier, spelled as it is typed.
local KEYS = {}
for key in pairs(VALUES) do
  KEYS[#KEYS + 1] = key .. ':'
end
for _, key in ipairs(FREE) do
  KEYS[#KEYS + 1] = key .. ':'
end
table.sort(KEYS)

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
  return {}
end

return M
