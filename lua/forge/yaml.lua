local M = {}

--- Enough YAML to read a github issue form, and no more.
---
--- Neovim ships a treesitter parser for YAML, so the grammar is not ours to
--- reimplement. What is ours is the walk from a parse tree to a Lua table:
--- mappings, sequences, plain and quoted scalars, and block scalars. Anchors,
--- aliases, tags and flow collections do not appear in issue forms, and are
--- not handled.

--- @param node TSNode
--- @param source string
--- @return string
local function text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

--- @param raw string
--- @return string|boolean|number
local function scalar(raw)
  local trimmed = vim.trim(raw)
  if trimmed == 'true' then
    return true
  elseif trimmed == 'false' then
    return false
  elseif trimmed:match('^-?%d+$') then
    return tonumber(trimmed) --[[@as number]]
  end
  local quote = trimmed:match('^(["\'])')
  if quote then
    trimmed = trimmed:sub(2, -2)
    if quote == '"' then
      trimmed = trimmed:gsub('\\n', '\n'):gsub('\\"', '"')
    end
  end
  return trimmed
end

--- Undo a block scalar's indentation, keeping the shape of what is inside.
--- @param raw string
--- @return string
local function block(raw)
  local lines = vim.split(raw, '\n', { plain = true })
  table.remove(lines, 1)
  local indent = math.huge
  for _, line in ipairs(lines) do
    if vim.trim(line) ~= '' then
      indent = math.min(indent, #line:match('^%s*'))
    end
  end
  if indent == math.huge then
    return ''
  end
  for i, line in ipairs(lines) do
    lines[i] = line:sub(indent + 1)
  end
  return vim.trim(table.concat(lines, '\n'))
end

local convert

--- @param node TSNode
--- @param source string
--- @return any
local function value_of(node, source)
  local child = node:named_child(0)
  return child and convert(child, source) or ''
end

--- @param node TSNode
--- @param source string
--- @return any
function convert(node, source)
  local kind = node:type()

  if kind == 'stream' or kind == 'document' then
    for child in node:iter_children() do
      if child:named() and child:type() ~= 'comment' then
        local converted = convert(child, source)
        if converted ~= nil then
          return converted
        end
      end
    end
    return nil
  end

  if kind == 'block_node' or kind == 'flow_node' then
    return value_of(node, source)
  end

  if kind == 'block_mapping' or kind == 'flow_mapping' then
    local mapping = {}
    for child in node:iter_children() do
      if child:type() == 'block_mapping_pair' or child:type() == 'flow_pair' then
        local key = child:field('key')[1]
        local value = child:field('value')[1]
        if key then
          mapping[tostring(scalar(text(key, source)))] = value and convert(value, source) or ''
        end
      end
    end
    return mapping
  end

  if kind == 'block_sequence' or kind == 'flow_sequence' then
    local sequence = {}
    for child in node:iter_children() do
      if child:type() == 'block_sequence_item' or child:type() == 'flow_node' then
        local inner = child:named_child(0)
        sequence[#sequence + 1] = inner and convert(inner, source) or ''
      end
    end
    return sequence
  end

  if kind == 'block_scalar' then
    return block(text(node, source))
  end

  return scalar(text(node, source))
end

--- @param source string
--- @return table?
function M.decode(source)
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, 'yaml')
  if not ok then
    return nil
  end
  local tree = parser:parse()[1]
  if not tree then
    return nil
  end
  local decoded = convert(tree:root(), source)
  return type(decoded) == 'table' and decoded or nil
end

return M
