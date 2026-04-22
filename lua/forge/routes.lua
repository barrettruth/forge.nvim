local M = {}

local action = require('forge.action')
local context = require('forge.context')
local log = require('forge.logger')
local surface = require('forge.surface')

---@type string[]
local section_order = surface.section_names()

---@param ctx forge.Context
---@return string
local function prompt(ctx)
  if ctx.branch ~= '' then
    return ('Forge (%s)> '):format(ctx.branch)
  end
  return 'Forge> '
end

---@param ctx forge.Context?
---@param opts? forge.RouteOpts
---@return string?
local function route_forge_name(ctx, opts)
  if type(opts) == 'table' then
    if type(opts.forge_name) == 'string' and opts.forge_name ~= '' then
      return opts.forge_name
    end
    local scope = opts.scope
    if type(scope) == 'table' and type(scope.kind) == 'string' and scope.kind ~= '' then
      return scope.kind
    end
  end
  local forge = type(ctx) == 'table' and ctx.forge or nil
  if type(forge) == 'table' and type(forge.name) == 'string' and forge.name ~= '' then
    return forge.name
  end
  return nil
end

---@param ctx forge.Context
---@param opts forge.RouteOpts
---@return string?, string?
local function branch_for(ctx, opts)
  local branch = opts.branch
  if branch == nil or branch == '' then
    branch = ctx.branch
  end
  if branch == '' then
    return nil, 'detached HEAD'
  end
  return branch
end

---@return table<string, fun(ctx: forge.Context, opts: forge.RouteOpts): boolean?, string?>
local function route_handlers()
  local pickers = require('forge.pickers')

  return {
    ['prs.all'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('all', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['prs.open'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('open', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['prs.closed'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('closed', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['issues.all'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('all', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['issues.open'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('open', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['issues.closed'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('closed', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['ci.all'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.ci(ctx.forge, nil, nil, { back = opts.back, scope = opts.scope })
    end,
    ['ci.current_branch'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local branch = opts.branch
      if branch == nil or branch == '' then
        branch = ctx.branch ~= '' and ctx.branch or nil
      end
      pickers.ci(ctx.forge, branch, nil, { back = opts.back, scope = opts.scope })
    end,
    ['browse.contextual'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      if ctx.has_file and ctx.loc then
        local branch, err = branch_for(ctx, opts)
        if not branch then
          return false, err
        end
        ctx.forge:browse(ctx.loc, branch, opts.scope)
      else
        local url = require('forge').remote_web_url(opts.scope)
        if url == '' then
          return false, 'no remote web url'
        end
        vim.ui.open(url)
      end
    end,
    ['browse.branch'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local branch, err = branch_for(ctx, opts)
      if not branch then
        return false, err
      end
      ctx.forge:browse_branch(branch, opts.scope)
    end,
    ['browse.commit'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local commit = opts.commit
      if commit == nil or commit == '' then
        commit = ctx.head
      end
      if commit == '' then
        return false, 'detached HEAD'
      end
      ctx.forge:browse_commit(commit, opts.scope)
    end,
    ['releases.all'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('all', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['releases.draft'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('draft', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
    ['releases.prerelease'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('prerelease', ctx.forge, { back = opts.back, scope = opts.scope })
    end,
  }
end

---@param section forge.SectionName
---@param ctx forge.Context
---@return string
local function section_label(section, ctx)
  if section == 'prs' then
    return ctx.forge and ctx.forge.labels.pr_full or 'PRs'
  end
  if section == 'issues' then
    return ctx.forge and ctx.forge.labels.issue or 'Issues'
  end
  if section == 'ci' then
    return ctx.forge and ctx.forge.labels.ci or 'CI'
  end
  if section == 'browse' then
    return 'Browse'
  end
  if section == 'releases' then
    return 'Releases'
  end
  return section
end

---@param section forge.SectionName
---@param ctx forge.Context
---@return boolean
local function section_available(section, ctx)
  if section == 'browse' then
    return ctx.forge ~= nil and ctx.branch ~= ''
  end
  if section == 'prs' or section == 'issues' or section == 'ci' or section == 'releases' then
    return ctx.forge ~= nil
  end
  return true
end

---@param name string?
---@return forge.Context?, string?
function M.current_context(name)
  return context.resolve(name)
end

---@param name string?
---@param opts? forge.SurfaceOpts
---@return string?
function M.resolve(name, opts)
  if not name or name == '' then
    return nil
  end
  opts = opts or {}
  local cfg = require('forge').config()
  local routes = rawget(cfg, 'routes') or {}
  local resolved_section = surface.resolve_section(name, opts.forge_name)
  local lookup = resolved_section and resolved_section.canonical or name
  local route = routes[lookup] or lookup
  local resolved_route = surface.resolve_route(route, opts.forge_name)
  return resolved_route and resolved_route.canonical or route
end

---@param ctx forge.Context
---@param opts? forge.RouteOpts
local function open_root(ctx, opts)
  opts = opts or {}
  local cfg = require('forge').config()
  local sections = rawget(cfg, 'sections') or {}
  local routes = rawget(cfg, 'routes') or {}
  local handlers = route_handlers()
  local entries = {}
  local forge_name = route_forge_name(ctx, opts)

  for _, section in ipairs(section_order) do
    if sections[section] ~= false then
      local route = routes[section]
      local resolved_route = route and M.resolve(route, { forge_name = forge_name }) or nil
      if resolved_route and handlers[resolved_route] and section_available(section, ctx) then
        local label = section_label(section, ctx)
        entries[#entries + 1] = {
          display = { { label } },
          value = route,
        }
      end
    end
  end

  if #entries == 0 then
    if not ctx.forge then
      log.warn('no forge detected')
    else
      log.warn('no sections available')
    end
    return
  end

  local default_action, action_err = action.bind('open', {
    name = 'default',
    context = ctx.id,
    back = function()
      open_root(ctx, opts)
    end,
  })
  if not default_action then
    log.error(action_err)
    return
  end

  require('forge.picker').pick({
    prompt = prompt(ctx),
    entries = entries,
    actions = { default_action },
    picker_name = '_menu',
    show_header = false,
    back = opts.back,
  })
end

---@param name string?
---@param opts? forge.RouteOpts
function M.open(name, opts)
  opts = opts or {}

  local ctx, err = M.current_context(opts.context)
  if not ctx then
    log.warn(err)
    return
  end
  local forge_name = route_forge_name(ctx, opts)

  if not name or name == '' then
    open_root(ctx, vim.tbl_extend('force', opts, { forge_name = forge_name }))
    return
  end

  local route = M.resolve(name, { forge_name = forge_name })
  local handler = route_handlers()[route]
  if not handler then
    log.warn('unknown route: ' .. name)
    return
  end

  local ok, msg = handler(ctx, opts)
  if ok == false and msg then
    log.warn(msg)
  end
end

return M
