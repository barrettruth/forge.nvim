local M = {}

---@alias forge.SurfaceAliasRegistry table<string, table<string, string[]>>

---@type forge.SurfaceAliasRegistry
local family_aliases = {
  pr = {
    gitlab = { 'mr' },
  },
  review = {},
  issue = {},
  ci = {
    gitlab = { 'pipeline' },
  },
  release = {},
  browse = {},
  clear = {},
}

---@type forge.SectionName[]
local section_order = {
  'prs',
  'issues',
  'ci',
  'browse',
  'releases',
}

---@type forge.SurfaceAliasRegistry
local section_aliases = {
  prs = {
    gitlab = { 'mrs' },
  },
  issues = {},
  ci = {
    gitlab = { 'pipelines' },
  },
  browse = {},
  releases = {},
}

---@type forge.RouteName[]
local route_order = {
  'prs.all',
  'prs.open',
  'prs.closed',
  'issues.all',
  'issues.open',
  'issues.closed',
  'ci.all',
  'ci.current_branch',
  'browse.contextual',
  'browse.branch',
  'browse.commit',
  'releases.all',
  'releases.draft',
  'releases.prerelease',
}

---@type table<string, boolean>
local route_set = {}

for _, name in ipairs(route_order) do
  route_set[name] = true
end

---@param registry forge.SurfaceAliasRegistry
---@param name string
---@param forge_name string?
---@return string[]
local function aliases_for(registry, name, forge_name)
  local entry = registry[name]
  if type(entry) ~= 'table' then
    return {}
  end
  if forge_name == nil or forge_name == '' then
    return {}
  end
  local aliases = entry[forge_name]
  if type(aliases) ~= 'table' then
    return {}
  end
  return vim.deepcopy(aliases)
end

local function all_aliases_for(registry, name)
  local entry = registry[name]
  if type(entry) ~= 'table' then
    return {}
  end
  local aliases = {}
  local seen = {}
  local forge_names = vim.tbl_keys(entry)
  table.sort(forge_names)
  for _, forge_name in ipairs(forge_names) do
    local items = entry[forge_name]
    if type(items) == 'table' then
      for _, alias in ipairs(items) do
        if seen[alias] ~= true then
          seen[alias] = true
          aliases[#aliases + 1] = alias
        end
      end
    end
  end
  return aliases
end

---@param registry forge.SurfaceAliasRegistry
---@param name string
---@param forge_name string?
---@return forge.SurfaceResolvedName?
local function resolve_name(registry, name, forge_name)
  if registry[name] ~= nil then
    return {
      canonical = name,
      invoked = name,
      alias = nil,
    }
  end
  if forge_name == nil or forge_name == '' then
    return nil
  end
  for canonical in pairs(registry) do
    for _, alias in ipairs(aliases_for(registry, canonical, forge_name)) do
      if alias == name then
        return {
          canonical = canonical,
          invoked = name,
          alias = name,
        }
      end
    end
  end
  return nil
end

---@param order string[]
---@param registry forge.SurfaceAliasRegistry
---@param opts? forge.SurfaceNamesOpts
---@return string[]
local function ordered_names(order, registry, opts)
  opts = opts or {}
  local names = {}
  for _, name in ipairs(order) do
    names[#names + 1] = name
    if opts.include_aliases then
      local aliases = opts.include_all_aliases and all_aliases_for(registry, name)
        or aliases_for(registry, name, opts.forge_name)
      for _, alias in ipairs(aliases) do
        names[#names + 1] = alias
      end
    end
  end
  return names
end

---@param name string
---@return string?, string?
local function route_parts(name)
  local section, suffix = name:match('^([^.]+)%.(.+)$')
  return section, suffix
end

---@param name forge.RouteName
---@param forge_name string?
---@return string[]
local function derived_route_aliases(name, forge_name, include_all_aliases)
  local section, suffix = route_parts(name)
  if section == nil or suffix == nil then
    return {}
  end
  local aliases = {}
  local section_names = include_all_aliases and all_aliases_for(section_aliases, section)
    or aliases_for(section_aliases, section, forge_name)
  for _, alias in ipairs(section_names) do
    aliases[#aliases + 1] = alias .. '.' .. suffix
  end
  return aliases
end

---@param name forge.CommandFamily
---@param forge_name string?
---@return string[]
function M.family_aliases(name, forge_name)
  return aliases_for(family_aliases, name, forge_name)
end

---@param name string
---@param forge_name string?
---@return forge.SurfaceResolvedName?
function M.resolve_family(name, forge_name)
  return resolve_name(family_aliases, name, forge_name)
end

---@param name forge.SectionName
---@param forge_name string?
---@return string[]
function M.section_aliases(name, forge_name)
  return aliases_for(section_aliases, name, forge_name)
end

---@param opts? forge.SurfaceNamesOpts
---@return string[]
function M.section_names(opts)
  return ordered_names(section_order, section_aliases, opts)
end

---@param name string
---@param forge_name string?
---@return forge.SurfaceResolvedName?
function M.resolve_section(name, forge_name)
  return resolve_name(section_aliases, name, forge_name)
end

---@param name forge.RouteName
---@param forge_name string?
---@return string[]
function M.route_aliases(name, forge_name)
  return derived_route_aliases(name, forge_name)
end

---@param opts? forge.SurfaceNamesOpts
---@return string[]
function M.route_names(opts)
  opts = opts or {}
  local names = {}
  for _, name in ipairs(route_order) do
    names[#names + 1] = name
    if opts.include_aliases then
      for _, alias in ipairs(derived_route_aliases(name, opts.forge_name, opts.include_all_aliases)) do
        names[#names + 1] = alias
      end
    end
  end
  return names
end

---@param name string
---@param forge_name string?
---@return forge.SurfaceResolvedName?
function M.resolve_route(name, forge_name)
  if route_set[name] then
    return {
      canonical = name,
      invoked = name,
      alias = nil,
    }
  end
  if forge_name == nil or forge_name == '' then
    return nil
  end
  local section, suffix = route_parts(name)
  if section == nil or suffix == nil then
    return nil
  end
  local resolved_section = M.resolve_section(section, forge_name)
  if not resolved_section then
    return nil
  end
  local canonical = resolved_section.canonical .. '.' .. suffix
  if not route_set[canonical] then
    return nil
  end
  return {
    canonical = canonical,
    invoked = name,
    alias = name,
  }
end

return M
