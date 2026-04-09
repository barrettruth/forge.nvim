local M = {}

local action_mod = require('forge.action')
local client_mod = require('forge.client')
local compose_mod = require('forge.compose')
local config_mod = require('forge.config')
local context_mod = require('forge.context')
local format_mod = require('forge.format')
local template_mod = require('forge.template')

---@type table<string, forge.Forge>
local sources = {}

---@param name string
---@param source forge.Forge
function M.register(name, source)
  sources[name] = source
end

M.register_source = M.register
M.register_client = client_mod.register
M.register_context_provider = context_mod.register
M.register_action = action_mod.register
M.run_action = action_mod.run

---@return table<string, forge.Forge>
function M.registered_sources()
  return sources
end

---@type table<string, forge.Forge>
local forge_cache = {}

---@type table<string, forge.RepoInfo>
local repo_info_cache = {}

---@type table<string, string>
local root_cache = {}

---@type table<string, table[]>
local list_cache = {}

---@return string?
local function git_root()
  local cwd = vim.fn.getcwd()
  if root_cache[cwd] then
    return root_cache[cwd]
  end
  local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  root_cache[cwd] = root
  return root
end

local builtin_hosts = {
  github = { 'github' },
  gitlab = { 'gitlab' },
  codeberg = { 'codeberg', 'gitea', 'forgejo' },
}

local function resolve_source(name)
  if sources[name] then
    return sources[name]
  end
  local ok, mod = pcall(require, 'forge.' .. name)
  if ok then
    sources[name] = mod
    return mod
  end
  return nil
end

---@param remote string
---@return string? forge_name
local function detect_from_remote(remote)
  local cfg = M.config().sources

  for name, opts in pairs(cfg) do
    for _, host in ipairs(opts.hosts or {}) do
      if remote:find(host, 1, true) then
        return name
      end
    end
  end

  for name, patterns in pairs(builtin_hosts) do
    for _, pattern in ipairs(patterns) do
      if remote:find(pattern, 1, true) then
        return name
      end
    end
  end

  return nil
end

---@return forge.Forge?
function M.detect()
  local log = require('forge.logger')
  local root = git_root()
  if not root then
    log.debug('detect: not a git repository')
    return nil
  end
  if forge_cache[root] then
    return forge_cache[root]
  end
  local remote = vim.trim(vim.fn.system('git remote get-url origin'))
  if vim.v.shell_error ~= 0 then
    log.debug('detect: no origin remote')
    return nil
  end
  local name = detect_from_remote(remote)
  if not name then
    log.debug('detect: no forge matched remote ' .. remote)
    return nil
  end
  local source = resolve_source(name)
  if not source then
    log.debug('detect: failed to load source module ' .. name)
    return nil
  end
  if vim.fn.executable(source.cli) ~= 1 then
    log.debug('detect: CLI ' .. source.cli .. ' not found')
    return nil
  end
  forge_cache[root] = source
  return source
end

---@param f forge.Forge
---@return forge.RepoInfo
function M.repo_info(f)
  local root = git_root()
  if root and repo_info_cache[root] then
    return repo_info_cache[root]
  end
  local info = f:repo_info()
  if root then
    repo_info_cache[root] = info
  end
  return info
end

---@param kind string
---@param state string
---@return string
function M.list_key(kind, state)
  local root = git_root() or ''
  return root .. ':' .. kind .. ':' .. state
end

---@param key string
---@return table[]?
function M.get_list(key)
  return list_cache[key]
end

---@param key string
---@param data table[]
function M.set_list(key, data)
  list_cache[key] = data
end

---@param key string?
function M.clear_list(key)
  if key then
    list_cache[key] = nil
  else
    list_cache = {}
  end
end

function M.clear_cache()
  forge_cache = {}
  repo_info_cache = {}
  root_cache = {}
  list_cache = {}
end

---@return string
function M.file_loc()
  local root = git_root()
  if not root then
    return vim.fn.expand('%:t')
  end
  local file = vim.api.nvim_buf_get_name(0):sub(#root + 2)
  local mode = vim.fn.mode()
  if mode:match('[vV]') or mode == '\22' then
    local s = vim.fn.line('v')
    local e = vim.fn.line('.')
    if s > e then
      s, e = e, s
    end
    if s == e then
      return ('%s:%d'):format(file, s)
    end
    return ('%s:%d-%d'):format(file, s, e)
  end
  return ('%s:%d'):format(file, vim.fn.line('.'))
end

---@return string
function M.remote_web_url()
  local root = git_root()
  if not root then
    return ''
  end
  local remote = vim.trim(vim.fn.system('git remote get-url origin'))
  remote = remote:gsub('%.git$', '')
  remote = remote:gsub('^ssh://git@', 'https://')
  remote = remote:gsub('^git@([^:]+):', 'https://%1/')
  return remote
end

M.config = config_mod.config

M.format_pr = format_mod.format_pr
M.format_prs = format_mod.format_prs
M.format_issue = format_mod.format_issue
M.format_issues = format_mod.format_issues
M.format_check = format_mod.format_check
M.format_checks = format_mod.format_checks
M.format_run = format_mod.format_run
M.format_runs = format_mod.format_runs
M.format_release = format_mod.format_release
M.format_releases = format_mod.format_releases
M.filter_checks = format_mod.filter_checks
M.filter_runs = format_mod.filter_runs

---@class forge.CreatePROpts
---@field draft boolean?
---@field instant boolean?
---@field web boolean?

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end

  local branch = vim.trim(vim.fn.system('git branch --show-current'))
  if branch == '' then
    log.warn('detached HEAD')
    return
  end

  log.info('checking for existing ' .. f.labels.pr_one .. '...')

  vim.system(f:pr_for_branch_cmd(branch), { text = true }, function(result)
    local num = vim.trim(result.stdout or '')
    vim.schedule(function()
      if num ~= '' and num ~= 'null' then
        M.edit_pr(num)
        return
      end

      if opts.web then
        log.info('pushing...')
        vim.system({ 'git', 'push', '-u', 'origin', branch }, { text = true }, function(push_result)
          vim.schedule(function()
            if push_result.code ~= 0 then
              log.error('push failed')
              return
            end
            local web_cmd = f:create_pr_web_cmd()
            if web_cmd then
              vim.system(web_cmd)
            end
          end)
        end)
        return
      end

      log.info('resolving base branch...')
      vim.system(f:default_branch_cmd(), { text = true }, function(base_result)
        local base = vim.trim(base_result.stdout or '')
        if base == '' then
          base = 'main'
        end
        vim.schedule(function()
          local has_diff = vim
            .system({ 'git', 'diff', '--quiet', 'origin/' .. base .. '..HEAD' }, { text = true })
            :wait().code ~= 0
          if not has_diff then
            log.warn('no changes from origin/' .. base)
            return
          end
          if opts.instant then
            local title, body = template_mod.fill_from_commits(branch, base)
            compose_mod.push_and_create(f, branch, title, body, base, opts.draft or false)
          else
            local root = git_root() or ''
            local draft = opts.draft or false
            local tmpl, templates, err = template_mod.discover(f:template_paths(), root)
            if err then
              log.error(err)
              return
            end
            if tmpl or not templates then
              compose_mod.open_pr(f, branch, base, draft, tmpl)
            else
              local picker = require('forge.picker')
              local entries = {}
              for _, t in ipairs(templates) do
                table.insert(entries, {
                  display = { { t.display } },
                  value = t,
                  ordinal = t.display,
                })
              end
              picker.pick({
                prompt = f.labels.pr_one .. ' Template> ',
                entries = entries,
                actions = {
                  {
                    name = 'default',
                    label = 'use',
                    fn = function(entry)
                      if entry then
                        local template, load_err = template_mod.load(entry.value)
                        if load_err then
                          log.error(load_err)
                          return
                        end
                        compose_mod.open_pr(f, branch, base, draft, template)
                      end
                    end,
                  },
                },
                picker_name = '_menu',
              })
            end
          end
        end)
      end)
    end)
  end)
end

---@param num string
function M.edit_pr(num)
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end

  local branch = vim.trim(vim.fn.system('git branch --show-current'))
  if branch == '' then
    log.warn('detached HEAD')
    return
  end

  log.info(('fetching %s #%s...'):format(f.labels.pr_one, num))

  vim.system(f:fetch_pr_details_cmd(num), { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        log.error('failed to fetch ' .. f.labels.pr_one .. ' #' .. num)
      end)
      return
    end
    local ok, json = pcall(vim.json.decode, result.stdout or '{}')
    if not ok or type(json) ~= 'table' then
      vim.schedule(function()
        log.error('failed to parse ' .. f.labels.pr_one .. ' details')
      end)
      return
    end
    local details = f:parse_pr_details(json)
    vim.system(f:pr_base_cmd(num), { text = true }, function(base_result)
      local base = vim.trim(base_result.stdout or '')
      if base == '' then
        base = 'main'
      end
      vim.schedule(function()
        compose_mod.open_pr_edit(f, num, details, branch, base)
      end)
    end)
  end)
end

---@class forge.CreateIssueOpts
---@field web boolean?
---@field blank boolean?
---@field template string?

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end

  if opts.web then
    if f.create_issue_web_cmd then
      local cmd = f:create_issue_web_cmd()
      if cmd then
        vim.system(cmd)
      end
    else
      local url = M.remote_web_url() .. '/issues/new'
      vim.ui.open(url)
    end
    return
  end

  if opts.blank then
    compose_mod.open_issue(f, nil)
    return
  end

  local root = git_root() or ''
  local result, templates, err = template_mod.discover(f:issue_template_paths(), root)
  if err then
    log.error(err)
    return
  end

  if opts.template and templates then
    local slug = opts.template:lower()
    for _, t in ipairs(templates) do
      if t.name:gsub('%.ya?ml$', ''):gsub('%.md$', ''):lower() == slug then
        local template, load_err = template_mod.load(t)
        if load_err then
          log.error(load_err)
          return
        end
        compose_mod.open_issue(f, template)
        return
      end
    end
    log.warn('template not found: ' .. opts.template)
    return
  end

  if result or not templates then
    compose_mod.open_issue(f, result)
    return
  end

  local picker = require('forge.picker')
  local entries = {}
  for _, t in ipairs(templates) do
    table.insert(entries, {
      display = { { t.display } },
      value = t,
      ordinal = t.display,
    })
  end
  picker.pick({
    prompt = 'Issue Template> ',
    entries = entries,
    actions = {
      {
        name = 'default',
        label = 'use',
        fn = function(entry)
          if entry then
            local template, load_err = template_mod.load(entry.value)
            if load_err then
              log.error(load_err)
              return
            end
            compose_mod.open_issue(f, template)
          end
        end,
      },
    },
    picker_name = '_menu',
  })
end

function M.template_slugs()
  local f = M.detect()
  if not f then
    return {}
  end
  local root = git_root() or ''
  local _, templates = template_mod.discover(f:issue_template_paths(), root)
  if not templates then
    return {}
  end
  local slugs = {}
  for _, t in ipairs(templates) do
    local slug = t.name:gsub('%.ya?ml$', ''):gsub('%.md$', '')
    slugs[#slugs + 1] = slug
  end
  return slugs
end

M._discover_templates = template_mod.discover
M._load_template = template_mod.load
M._normalize_body = template_mod.normalize_body

local routes_mod = require('forge.routes')
M.current_context = routes_mod.current_context
M.open = routes_mod.open

return M
