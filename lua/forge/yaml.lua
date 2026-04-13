local M = {}

---@param node any
---@param source string
---@return any
local function convert(node, source)
  local t = node:type()

  if t == 'stream' then
    for j = 0, node:named_child_count() - 1 do
      local child = node:named_child(j)
      if child:type() == 'document' then
        return convert(child, source)
      end
    end
    return {}
  end

  if t == 'document' then
    local child = node:named_child(0)
    return child and convert(child, source) or {}
  end

  if t == 'block_node' or t == 'flow_node' then
    local child = node:named_child(0)
    return child and convert(child, source) or ''
  end

  if t == 'block_mapping' or t == 'flow_mapping' then
    local map = {}
    local pair_type = t == 'block_mapping' and 'block_mapping_pair' or 'flow_pair'
    for j = 0, node:named_child_count() - 1 do
      local child = node:named_child(j)
      if child:type() == pair_type then
        local key_node = child:field('key')[1]
        local val_node = child:field('value')[1]
        if key_node then
          local key = tostring(convert(key_node, source))
          map[key] = val_node and convert(val_node, source) or ''
        end
      end
    end
    return map
  end

  if t == 'block_sequence' then
    local seq = {}
    for j = 0, node:named_child_count() - 1 do
      local child = node:named_child(j)
      if child:type() == 'block_sequence_item' then
        local item = child:named_child(0)
        table.insert(seq, item and convert(item, source) or '')
      end
    end
    return seq
  end

  if t == 'flow_sequence' then
    local seq = {}
    for j = 0, node:named_child_count() - 1 do
      table.insert(seq, convert(node:named_child(j), source))
    end
    return seq
  end

  if t == 'block_scalar' then
    local text = vim.treesitter.get_node_text(node, source)
    local indicator = text:sub(1, 1)
    local lines = vim.split(text, '\n', { plain = true })
    table.remove(lines, 1)
    local base = math.huge
    for _, line in ipairs(lines) do
      if vim.trim(line) ~= '' then
        base = math.min(base, #(line:match('^(%s*)') or ''))
      end
    end
    if base == math.huge then
      base = 0
    end
    local parts = {}
    for _, line in ipairs(lines) do
      table.insert(parts, vim.trim(line) == '' and '' or line:sub(base + 1))
    end
    while #parts > 0 and parts[#parts] == '' do
      table.remove(parts)
    end
    return table.concat(parts, indicator == '|' and '\n' or ' ')
  end

  if t == 'plain_scalar' then
    local text
    local child = node:named_child(0)
    if child then
      text = vim.treesitter.get_node_text(child, source)
    else
      text = vim.treesitter.get_node_text(node, source)
    end
    return text:gsub('%s*\n%s*', ' ')
  end

  if t == 'single_quote_scalar' then
    local text = vim.treesitter.get_node_text(node, source)
    return text:sub(2, -2)
  end

  if t == 'double_quote_scalar' then
    local text = vim.treesitter.get_node_text(node, source)
    return text:sub(2, -2)
  end

  return vim.treesitter.get_node_text(node, source)
end

---@param text string
---@return table
function M.parse(text)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, 'yaml')
  if not ok then
    require('forge.logger').warn(
      'tree-sitter yaml parser not found; install it to use YAML issue form templates'
    )
    return {}
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return {}
  end
  local result = convert(trees[1]:root(), text)
  return type(result) == 'table' and result or {}
end

---@param field table
---@param parts string[]
local function render_field(field, parts)
  local typ = field.type
  local attrs = field.attributes or {}

  if typ == 'markdown' then
    if attrs.value then
      table.insert(parts, vim.trim(attrs.value))
    end
    return
  end

  local label = attrs.label or ''
  if type(label) == 'table' then
    label = table.concat(label, ' ')
  end
  label = vim.trim(label)
  if label ~= '' then
    table.insert(parts, '### ' .. label)
  end

  if attrs.description and attrs.description ~= '' then
    table.insert(parts, '<!-- ' .. vim.trim(attrs.description) .. ' -->')
  end

  if typ == 'textarea' then
    if attrs.value and attrs.value ~= '' then
      table.insert(parts, vim.trim(attrs.value))
    else
      table.insert(parts, '')
    end
  elseif typ == 'input' then
    if attrs.value and attrs.value ~= '' then
      table.insert(parts, vim.trim(attrs.value))
    elseif attrs.placeholder and attrs.placeholder ~= '' then
      table.insert(parts, '<!-- ' .. vim.trim(attrs.placeholder) .. ' -->')
    else
      table.insert(parts, '')
    end
  elseif typ == 'dropdown' then
    local options = attrs.options or {}
    for _, opt in ipairs(options) do
      local ol = type(opt) == 'table' and (opt.label or '') or tostring(opt)
      table.insert(parts, '- [ ] ' .. vim.trim(ol))
    end
  elseif typ == 'checkboxes' then
    local options = attrs.options or {}
    for _, opt in ipairs(options) do
      local ol = type(opt) == 'table' and (opt.label or '') or tostring(opt)
      if type(ol) == 'table' then
        ol = table.concat(ol, ' ')
      end
      table.insert(parts, '- [ ] ' .. vim.trim(ol))
    end
  end
end

---@class forge.TemplateResult
---@field body string
---@field title string?
---@field labels string[]?
---@field assignees string[]?

---@param doc table
---@return forge.TemplateResult
function M.render(doc)
  local parts = {}
  local body = doc.body or {}
  if type(body) ~= 'table' then
    body = {}
  end
  for _, field in ipairs(body) do
    render_field(field, parts)
    table.insert(parts, '')
  end
  while #parts > 0 and parts[#parts] == '' do
    table.remove(parts)
  end
  local labels = doc.labels
  if type(labels) == 'string' then
    labels = { labels }
  end
  local assignees = doc.assignees
  if type(assignees) == 'string' then
    assignees = { assignees }
  end
  return {
    body = table.concat(parts, '\n'),
    title = doc.title or nil,
    labels = labels,
    assignees = assignees,
  }
end

return M
