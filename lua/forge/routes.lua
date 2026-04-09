local M = {}

local action = require('forge.action')
local client = require('forge.client')
local context = require('forge.context')
local log = require('forge.logger')

local section_order = {
  'prs',
  'issues',
  'ci',
  'branches',
  'commits',
  'worktrees',
  'browse',
  'releases',
}

local section_search_terms = {
  prs = { 'pull', 'requests', 'reviews' },
  issues = { 'bugs', 'tickets' },
  ci = { 'checks', 'runs', 'actions' },
  branches = { 'refs' },
  commits = { 'history', 'log' },
  worktrees = { 'trees' },
  browse = { 'web' },
  releases = { 'tags' },
}

local function prompt(ctx)
  if ctx.branch ~= '' then
    return ('Forge (%s)> '):format(ctx.branch)
  end
  return 'Forge> '
end

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

local function route_handlers()
  local pickers = require('forge.pickers')

  return {
    ['prs.all'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('all', ctx.forge)
    end,
    ['prs.open'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('open', ctx.forge)
    end,
    ['prs.closed'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.pr('closed', ctx.forge)
    end,
    ['issues.all'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('all', ctx.forge)
    end,
    ['issues.open'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('open', ctx.forge)
    end,
    ['issues.closed'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.issue('closed', ctx.forge)
    end,
    ['ci.all'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.ci(ctx.forge)
    end,
    ['ci.current_branch'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local branch = opts.branch
      if branch == nil or branch == '' then
        branch = ctx.branch ~= '' and ctx.branch or nil
      end
      pickers.ci(ctx.forge, branch)
    end,
    ['branches.local'] = function(ctx)
      pickers.branches(ctx)
    end,
    ['commits.current_branch'] = function(ctx, opts)
      local branch, err = branch_for(ctx, opts)
      if not branch then
        return false, err
      end
      pickers.commits(ctx, branch)
    end,
    ['worktrees.list'] = function(ctx)
      pickers.worktrees(ctx)
    end,
    ['browse.contextual'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local branch, err = branch_for(ctx, opts)
      if not branch then
        return false, err
      end
      if ctx.has_file and ctx.loc then
        ctx.forge:browse(ctx.loc, branch)
      else
        ctx.forge:browse_branch(branch)
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
      ctx.forge:browse_branch(branch)
    end,
    ['browse.commit'] = function(ctx, opts)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      local sha = opts.sha
      if sha == nil or sha == '' then
        sha = ctx.head
      end
      if sha == '' then
        return false, 'detached HEAD'
      end
      ctx.forge:browse_commit(sha)
    end,
    ['releases.all'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('all', ctx.forge)
    end,
    ['releases.draft'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('draft', ctx.forge)
    end,
    ['releases.prerelease'] = function(ctx)
      if not ctx.forge then
        return false, 'no forge detected'
      end
      pickers.release('prerelease', ctx.forge)
    end,
  }
end

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
  if section == 'branches' then
    return 'Branches'
  end
  if section == 'commits' then
    return 'Commits'
  end
  if section == 'worktrees' then
    return 'Worktrees'
  end
  return section
end

local function section_available(section, ctx)
  if section == 'browse' then
    return ctx.forge ~= nil and ctx.branch ~= ''
  end
  if section == 'prs' or section == 'issues' or section == 'ci' or section == 'releases' then
    return ctx.forge ~= nil
  end
  return true
end

function M.current_context(name)
  return context.resolve(name)
end

function M.resolve(name)
  if not name or name == '' then
    return nil
  end
  local cfg = require('forge').config()
  local routes = rawget(cfg, 'routes') or {}
  return routes[name] or name
end

local function open_root(ctx)
  local cfg = require('forge').config()
  local sections = rawget(cfg, 'sections') or {}
  local routes = rawget(cfg, 'routes') or {}
  local client_name = rawget(cfg, 'client') or 'picker'
  local handlers = route_handlers()
  local entries = {}

  for _, section in ipairs(section_order) do
    if sections[section] ~= false then
      local route = routes[section]
      if route and handlers[route] and section_available(section, ctx) then
        local label = section_label(section, ctx)
        entries[#entries + 1] = {
          display = { { label } },
          value = route,
          ordinal = table.concat(
            vim.tbl_flatten({ label, section, section_search_terms[section] or {} }),
            ' '
          ),
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
  })
  if not default_action then
    log.error(action_err)
    return
  end

  local ok, client_err = client.open_root(client_name, {
    context = ctx,
    prompt = prompt(ctx),
    entries = entries,
    actions = { default_action },
  })
  if not ok and client_err then
    log.error(client_err)
  end
end

function M.open(name, opts)
  opts = opts or {}

  local ctx, err = M.current_context(opts.context)
  if not ctx then
    log.warn(err)
    return
  end

  if not name or name == '' then
    open_root(ctx)
    return
  end

  local route = M.resolve(name)
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
