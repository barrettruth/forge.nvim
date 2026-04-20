local M = {}

local log = require('forge.logger')

---@type table<string, forge.ReviewAdapter>
local adapters = {}

local function sanitize_ref_path(text)
  if type(text) ~= 'string' then
    return ''
  end
  local sanitized = text:gsub('[^%w%._/-]', '-')
  sanitized = sanitized:gsub('/+', '/')
  sanitized = sanitized:gsub('^/+', '')
  sanitized = sanitized:gsub('/+$', '')
  return sanitized
end

local function diffview_available()
  return vim.fn.exists(':DiffviewOpen') == 2
end

local function codediff_available()
  return vim.fn.exists(':CodeDiff') == 2
end

local function diffs_available()
  return vim.fn.exists(':Greview') == 2
end

local function trim(text)
  if type(text) ~= 'string' then
    return ''
  end
  return vim.trim(text)
end

local function cmd_error(result, fallback)
  local msg = trim(result.stderr or '')
  if msg == '' then
    msg = trim(result.stdout or '')
  end
  if msg == '' then
    msg = fallback
  end
  return msg
end

local function normalize_pr_ref(pr)
  if type(pr) == 'table' then
    return pr
  end
  return { num = pr }
end

local function review_head_ref(pr)
  local scope = pr.scope or {}
  local parts = {
    'refs/forge/review',
    sanitize_ref_path(scope.kind or 'repo'),
    sanitize_ref_path(scope.host or 'local'),
    sanitize_ref_path(scope.slug or 'current'),
    'pr',
    sanitize_ref_path(pr.num),
  }
  return table.concat(parts, '/')
end

local function fetch_head_cmd(f, pr, target)
  if type(f.fetch_pr) ~= 'function' then
    return nil, 'review fetch unavailable'
  end
  local cmd = vim.deepcopy(f:fetch_pr(pr.num, pr.scope))
  local refspec = type(cmd) == 'table' and cmd[#cmd] or nil
  local source = type(refspec) == 'string' and refspec:match('^([^:]+):[^:]+$') or nil
  if not source then
    return nil, 'review fetch unavailable'
  end
  cmd[#cmd] = '+' .. source .. ':' .. target
  return cmd
end

local function base_ref(ctx, details)
  local forge = require('forge')
  local branch = trim(details.base_branch)
  if branch == '' then
    return nil
  end
  local scope = ctx.pr.scope
  local ref = forge.remote_ref(scope, branch)
  if ref and ref ~= '' then
    return ref
  end
  return 'origin/' .. branch
end

local function open_diffview(range)
  return pcall(vim.api.nvim_cmd, {
    cmd = 'DiffviewOpen',
    args = { range },
  }, {})
end

local function open_codediff(range)
  return pcall(vim.api.nvim_cmd, {
    cmd = 'CodeDiff',
    args = { range },
  }, {})
end

local function open_diffs(range)
  return pcall(vim.api.nvim_cmd, {
    cmd = 'Greview',
    args = { range },
  }, {})
end

local function adapter_name(opts)
  opts = opts or {}
  local explicit = trim(opts.adapter)
  if explicit ~= '' then
    return explicit
  end
  local cfg = require('forge').config()
  local configured = trim((cfg.review or {}).adapter)
  if configured ~= '' then
    return configured
  end
  return 'checkout'
end

local function builtins()
  return {
    checkout = {
      label = 'checkout',
      open = function(ctx)
        local f = ctx.forge
        local pr = ctx.pr
        local kind = f.labels.pr_one
        log.info(('checking out %s #%s...'):format(kind, pr.num))
        vim.system(f:checkout_cmd(pr.num, pr.scope), { text = true }, function(result)
          vim.schedule(function()
            if result.code == 0 then
              log.info(('checked out %s #%s'):format(kind, pr.num))
            else
              log.error(cmd_error(result, 'checkout failed'))
            end
          end)
        end)
      end,
    },
    worktree = {
      label = 'worktree',
      open = function(ctx)
        local f = ctx.forge
        local pr = ctx.pr
        local kind = f.labels.pr_one
        local fetch_cmd = f:fetch_pr(pr.num, pr.scope)
        local branch = fetch_cmd[#fetch_cmd]:match(':(.+)$')
        if not branch then
          return
        end
        local root = trim(vim.fn.system('git rev-parse --show-toplevel'))
        local wt_path = vim.fs.normalize(root .. '/../' .. branch)
        log.info(('fetching %s #%s into worktree...'):format(kind, pr.num))
        vim.system(fetch_cmd, { text = true }, function()
          vim.system(
            { 'git', 'worktree', 'add', wt_path, branch },
            { text = true },
            function(result)
              vim.schedule(function()
                if result.code == 0 then
                  log.info(('worktree at %s'):format(wt_path))
                else
                  log.error(cmd_error(result, 'worktree failed'))
                end
              end)
            end
          )
        end)
      end,
    },
    browse = {
      label = 'web',
      open = function(ctx)
        local f = ctx.forge
        local pr = ctx.pr
        f:view_web(f.kinds.pr, pr.num, pr.scope)
      end,
    },
    diffview = {
      label = 'diffview',
      open = function(ctx)
        if not diffview_available() then
          log.error('diffview.nvim not found')
          return
        end
        local details, err = ctx.details()
        if not details then
          log.error(err or 'failed to load review details')
          return
        end
        local base = base_ref(ctx, details)
        if not base then
          log.error('review base unavailable')
          return
        end
        local head = review_head_ref(ctx.pr)
        local fetch_cmd, fetch_err = fetch_head_cmd(ctx.forge, ctx.pr, head)
        if not fetch_cmd then
          log.error(fetch_err or 'review fetch unavailable')
          return
        end
        local kind = ctx.forge.labels.pr_one
        log.info(('opening %s #%s in diffview...'):format(kind, ctx.pr.num))
        vim.system(fetch_cmd, { text = true }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              log.error(cmd_error(result, 'review fetch failed'))
              return
            end
            local ok, open_err = open_diffview(base .. '...' .. head)
            if not ok then
              log.error(open_err)
            end
          end)
        end)
      end,
    },
    codediff = {
      label = 'codediff',
      open = function(ctx)
        if not codediff_available() then
          log.error('codediff.nvim not found')
          return
        end
        local details, err = ctx.details()
        if not details then
          log.error(err or 'failed to load review details')
          return
        end
        local base = base_ref(ctx, details)
        if not base then
          log.error('review base unavailable')
          return
        end
        local head = review_head_ref(ctx.pr)
        local fetch_cmd, fetch_err = fetch_head_cmd(ctx.forge, ctx.pr, head)
        if not fetch_cmd then
          log.error(fetch_err or 'review fetch unavailable')
          return
        end
        local kind = ctx.forge.labels.pr_one
        log.info(('opening %s #%s in codediff...'):format(kind, ctx.pr.num))
        vim.system(fetch_cmd, { text = true }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              log.error(cmd_error(result, 'review fetch failed'))
              return
            end
            local ok, open_err = open_codediff(base .. '...' .. head)
            if not ok then
              log.error(open_err)
            end
          end)
        end)
      end,
    },
    diffs = {
      label = 'diffs',
      open = function(ctx)
        if not diffs_available() then
          log.error('diffs.nvim not found')
          return
        end
        local details, err = ctx.details()
        if not details then
          log.error(err or 'failed to load review details')
          return
        end
        local base = base_ref(ctx, details)
        if not base then
          log.error('review base unavailable')
          return
        end
        local head = review_head_ref(ctx.pr)
        local fetch_cmd, fetch_err = fetch_head_cmd(ctx.forge, ctx.pr, head)
        if not fetch_cmd then
          log.error(fetch_err or 'review fetch unavailable')
          return
        end
        local kind = ctx.forge.labels.pr_one
        log.info(('opening %s #%s in diffs...'):format(kind, ctx.pr.num))
        vim.system(fetch_cmd, { text = true }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              log.error(cmd_error(result, 'review fetch failed'))
              return
            end
            local ok, open_err = open_diffs(base .. '...' .. head)
            if not ok then
              log.error(open_err)
            end
          end)
        end)
      end,
    },
  }
end

function M.register(name, adapter)
  adapters[name] = adapter
end

function M.get(name)
  local adapter = adapters[name]
  if adapter then
    return adapter
  end
  return builtins()[name]
end

function M.names()
  local names = {}
  local seen = {}
  for name in pairs(builtins()) do
    seen[name] = true
    names[#names + 1] = name
  end
  for name in pairs(adapters) do
    if not seen[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function M.current_name(opts)
  return adapter_name(opts)
end

function M.label(opts)
  local name = adapter_name(opts)
  local adapter = M.get(name)
  if not adapter then
    return name
  end
  local label = adapter.label
  if type(label) == 'string' and label ~= '' then
    return label
  end
  return name
end

function M.context(f, pr, opts)
  pr = normalize_pr_ref(pr)
  opts = opts or {}
  local ctx = {
    forge = f,
    pr = pr,
    adapter = adapter_name(opts),
    opts = opts,
  }
  local loaded = false
  local details
  local err
  ctx.details = function()
    if loaded then
      return details, err
    end
    loaded = true
    if type(f.fetch_pr_details_cmd) ~= 'function' or type(f.parse_pr_details) ~= 'function' then
      err = 'review details unavailable'
      return nil, err
    end
    local result = vim.system(f:fetch_pr_details_cmd(pr.num, pr.scope), { text = true }):wait()
    if result.code ~= 0 then
      err = cmd_error(result, 'failed to load review details')
      return nil, err
    end
    local ok, json = pcall(vim.json.decode, result.stdout or '{}')
    if not ok or type(json) ~= 'table' then
      err = 'failed to parse review details'
      return nil, err
    end
    details = f:parse_pr_details(json)
    if type(details) ~= 'table' then
      details = {}
    end
    if details.url == nil and type(json.url) == 'string' then
      details.url = json.url
    end
    return details
  end
  return ctx
end

function M.open(f, pr, opts)
  local ctx = M.context(f, pr, opts)
  local adapter = M.get(ctx.adapter)
  if not adapter then
    log.error('unknown review adapter: ' .. ctx.adapter)
    return false, 'unknown review adapter'
  end
  adapter.open(ctx)
  return true
end

return M
