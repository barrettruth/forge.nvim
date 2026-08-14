local vcs = require('forge.vcs')

local M = {}

--- @class forge.Field
--- @field kind 'input'|'textarea'|'dropdown'|'checkboxes'
--- @field label string
--- @field description string?
--- @field required boolean
--- @field value string? text github would have prefilled
--- @field render string? a language, meaning the answer is a code block
--- @field options string[]? for a dropdown or checkboxes
--- @field required_options boolean[]? for checkboxes, per option
--- @field multiple boolean? a dropdown taking more than one answer
--- @field default integer? the option a dropdown starts on, counting from zero

--- @class forge.Template
--- @field name string what to call it when choosing
--- @field path string
--- @field title string? a title to start from
--- @field labels string[]
--- @field assignees string[]
--- @field body string? for a markdown template, the whole of it
--- @field fields forge.Field[]? for a form, what it asks
--- @field guidance table<integer, string> guidance above field n, 0 for the top

--- Where github looks, and nowhere else.
---
--- The chooser directory is honoured only under .github, though the single
--- legacy file is honoured in three places. Directory names are matched
--- case-insensitively because github matches them that way.
local ISSUE_DIR = '.github/ISSUE_TEMPLATE'
local ISSUE_LEGACY = { '.github/ISSUE_TEMPLATE.md', 'ISSUE_TEMPLATE.md', 'docs/ISSUE_TEMPLATE.md' }
local PR_DIR = '.github/PULL_REQUEST_TEMPLATE'
local PR_LEGACY = {
  '.github/pull_request_template.md',
  '.github/PULL_REQUEST_TEMPLATE.md',
  'pull_request_template.md',
  'PULL_REQUEST_TEMPLATE.md',
  'docs/pull_request_template.md',
  'docs/PULL_REQUEST_TEMPLATE.md',
}

--- What to call a template that did not name itself.
---
--- github requires `name:` on anything that appears in its own chooser, so
--- this is for the ones that never carry it: a pull request template, whose
--- filename is its identity, and any issue template missing the key. Derived
--- rather than looked up, because the filenames are whatever someone typed.
--- @param path string
--- @return string
local function label(path)
  local base = vim.fs.basename(path):gsub('%.%w+$', ''):gsub('[_-]+', ' '):lower()
  return (base:gsub('%S+', function(word)
    return word:sub(1, 1):upper() .. word:sub(2)
  end))
end

--- @param path string
--- @return string[]?
local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return nil
  end
  return lines
end

--- @param dir string
--- @param pattern string
--- @return string[]
local function entries(dir, pattern)
  local found = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return found
  end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind == 'file' and name:match(pattern) and not name:match('^config%.ya?ml$') then
      found[#found + 1] = dir .. '/' .. name
    end
  end
  table.sort(found)
  return found
end

--- Values in template front matter and form headers come as a list or as one
--- comma-separated string, and github accepts both.
--- @param value any
--- @return string[]
local function names(value)
  if type(value) == 'table' then
    return vim.tbl_map(vim.trim, value)
  end
  if type(value) ~= 'string' or vim.trim(value) == '' then
    return {}
  end
  return vim.tbl_map(vim.trim, vim.split(value, ',', { plain = true }))
end

--- Strip a leading --- block, returning its keys and the body beneath.
---
--- The opening --- must be the first line, so a --- inside a fenced block
--- further down cannot be mistaken for front matter.
--- @param lines string[]
--- @return table<string, string> keys
--- @return string body
local function front_matter(lines)
  if lines[1] ~= '---' then
    return {}, table.concat(lines, '\n')
  end
  local keys, at = {}, nil
  for i = 2, #lines do
    if lines[i] == '---' then
      at = i
      break
    end
    local key, value = lines[i]:match('^([%w_-]+):%s*(.*)$')
    if key then
      keys[key] = (value:gsub('^["\']', ''):gsub('["\']$', ''))
    elseif lines[i]:match('^%s*%-%s+') and keys.__last then
      local item = lines[i]:match('^%s*%-%s+(.*)$')
      keys[keys.__last] = keys[keys.__last] == '' and item or (keys[keys.__last] .. ',' .. item)
    end
    if key then
      keys.__last = key
    end
  end
  keys.__last = nil
  if not at then
    return {}, table.concat(lines, '\n')
  end
  return keys, table.concat(vim.list_slice(lines, at + 1), '\n')
end

--- @param path string
--- @return forge.Template?
local function markdown_template(path)
  local lines = read(path)
  if not lines then
    return nil
  end
  local keys, body = front_matter(lines)
  return {
    name = keys.name or label(path),
    path = path,
    title = keys.title,
    labels = names(keys.labels),
    assignees = names(keys.assignees),
    body = vim.trim(body),
    guidance = {},
  }
end

--- @param path string
--- @return forge.Template?
--- @return string? err
local function form_template(path)
  local lines = read(path)
  if not lines then
    return nil
  end
  local form, err = require('forge.yaml').decode(table.concat(lines, '\n'))
  if not form then
    return nil, err
  end
  if type(form.body) ~= 'table' then
    return nil
  end

  local fields, guidance = {}, {}
  for _, element in ipairs(form.body) do
    local attributes = element.attributes or {}
    if element.type == 'markdown' then
      guidance[#fields] = vim.trim(attributes.value or '')
    elseif attributes.label then
      local options, required_options = nil, nil
      if attributes.options then
        options, required_options = {}, {}
        for i, option in ipairs(attributes.options) do
          if type(option) == 'table' then
            options[i] = tostring(option.label)
            required_options[i] = option.required == true
          else
            options[i] = tostring(option)
            required_options[i] = false
          end
        end
      end
      fields[#fields + 1] = {
        kind = element.type,
        label = attributes.label,
        description = attributes.description and vim.trim(attributes.description) or nil,
        required = (element.validations or {}).required == true,
        value = attributes.value,
        render = attributes.render,
        options = options,
        required_options = required_options,
        multiple = attributes.multiple == true,
        default = type(attributes.default) == 'number' and attributes.default or nil,
      }
      if attributes.description and guidance[#fields] == nil then
        guidance[#fields] = vim.trim(attributes.description)
      end
    end
  end

  return {
    name = form.name or label(path),
    path = path,
    title = form.title,
    labels = names(form.labels),
    assignees = names(form.assignees),
    fields = fields,
    guidance = guidance,
  }
end

--- @param path string
--- @return forge.Template?
--- @return string? err
local function load(path)
  if path:match('%.ya?ml$') then
    return form_template(path)
  end
  return markdown_template(path)
end

--- Every template a repository offers for `collection`.
---
--- Read from the working copy rather than the API, because github's
--- issueTemplates only reports markdown ones and cannot see a form at all.
--- That means templates come from the checkout the request was made in, and a
--- repository you are only browsing offers none.
--- @param collection forge.Collection
--- @param dir string? the directory the request is made from
--- @return forge.Template[]
--- @return string? err why a template that exists was not read
function M.all(collection, dir)
  local root = vim.fs.root(dir or vcs.dir(), '.git')
  if not root then
    return {}
  end

  local paths = {}
  if collection == 'issues' then
    vim.list_extend(paths, entries(root .. '/' .. ISSUE_DIR, '%.ya?ml$'))
    vim.list_extend(paths, entries(root .. '/' .. ISSUE_DIR, '%.md$'))
    if #paths == 0 then
      for _, legacy in ipairs(ISSUE_LEGACY) do
        paths[#paths + 1] = root .. '/' .. legacy
      end
    end
  else
    vim.list_extend(paths, entries(root .. '/' .. PR_DIR, '%.md$'))
    for _, legacy in ipairs(PR_LEGACY) do
      paths[#paths + 1] = root .. '/' .. legacy
    end
  end

  local templates, seen, err = {}, {}, nil
  for _, path in ipairs(paths) do
    local real = vim.uv.fs_realpath(path)
    if real and not seen[real] then
      seen[real] = true
      local template, why = load(path)
      if template then
        templates[#templates + 1] = template
      else
        err = err or why
      end
    end
  end
  return templates, err
end

return M
