local M = {}

local ordered_fields = {
  issue = { 'labels', 'assignees', 'milestone' },
  pr = { 'draft', 'reviewers', 'labels', 'assignees', 'milestone' },
}

local function trim(value)
  return vim.trim(value or '')
end

local function normalize_list(values)
  local items = {}
  local seen = {}
  for _, value in ipairs(values or {}) do
    local item = trim(value)
    if item ~= '' and not seen[item] then
      seen[item] = true
      table.insert(items, item)
    end
  end
  return items
end

function M.supports(forge, kind, operation, field)
  local ops = (((forge or {}).submission or {})[kind] or {})[operation] or {}
  if ops[field] ~= nil then
    return ops[field]
  end
  if field == 'draft' then
    return (forge.capabilities or {}).draft == true
  end
  if field == 'reviewers' then
    return (forge.capabilities or {}).reviewers == true
  end
  return true
end

function M.filter(forge, kind, operation, metadata)
  metadata = metadata or {}
  return {
    labels = M.supports(forge, kind, operation, 'labels') and normalize_list(metadata.labels) or {},
    assignees = M.supports(forge, kind, operation, 'assignees') and normalize_list(metadata.assignees)
      or {},
    milestone = M.supports(forge, kind, operation, 'milestone') and trim(metadata.milestone) or '',
    draft = M.supports(forge, kind, operation, 'draft') and metadata.draft == true or false,
    reviewers = M.supports(forge, kind, operation, 'reviewers') and normalize_list(metadata.reviewers)
      or {},
  }
end

function M.fields(forge, kind, operation)
  local fields = {}
  for _, field in ipairs(ordered_fields[kind] or {}) do
    if M.supports(forge, kind, operation, field) then
      table.insert(fields, field)
    end
  end
  return fields
end

function M.issue_metadata(details)
  details = details or {}
  return {
    labels = normalize_list(details.labels),
    assignees = normalize_list(details.assignees),
    milestone = trim(details.milestone),
    draft = false,
    reviewers = {},
  }
end

function M.pr_metadata(details)
  details = details or {}
  return {
    labels = normalize_list(details.labels),
    assignees = normalize_list(details.assignees),
    milestone = trim(details.milestone),
    draft = details.draft == true,
    reviewers = normalize_list(details.reviewers),
  }
end

function M.diff(previous, current)
  local before = normalize_list(previous)
  local after = normalize_list(current)
  local before_set = {}
  local after_set = {}
  local added = {}
  local removed = {}

  for _, item in ipairs(before) do
    before_set[item] = true
  end
  for _, item in ipairs(after) do
    after_set[item] = true
    if not before_set[item] then
      table.insert(added, item)
    end
  end
  for _, item in ipairs(before) do
    if not after_set[item] then
      table.insert(removed, item)
    end
  end

  return added, removed
end

return M
