local M = {}

local action_mod = require('forge.action')
local client_mod = require('forge.client')
local compose_mod = require('forge.compose')
local config_mod = require('forge.config')
local context_mod = require('forge.context')
local format_mod = require('forge.format')
local scope_mod = require('forge.scope')
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

local function fn_system_text(cmd)
  local text = vim.trim(vim.fn.system(cmd))
  if vim.v.shell_error ~= 0 and (text == '' or text:match('^fatal:') or text:match('^error:')) then
    return nil
  end
  if text == '' then
    return nil
  end
  return text
end

---@return string?
local function git_root()
  local cwd = vim.fn.getcwd()
  if root_cache[cwd] then
    return root_cache[cwd]
  end
  local root = fn_system_text('git rev-parse --show-toplevel')
  if not root then
    return nil
  end
  root_cache[cwd] = root
  return root
end

local function cmd_error(result, fallback)
  local msg = vim.trim(result.stderr or '')
  if msg == '' then
    msg = vim.trim(result.stdout or '')
  end
  if msg == '' then
    msg = fallback
  end
  return msg
end

local function system_text(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return ''
  end
  return vim.trim(result.stdout or '')
end

local function push_remote_name(branch)
  local remote = system_text({ 'git', 'config', 'branch.' .. branch .. '.pushRemote' })
  if remote == '' then
    remote = system_text({ 'git', 'config', 'remote.pushDefault' })
  end
  if remote == '' then
    local upstream = system_text({ 'git', 'rev-parse', '--abbrev-ref', branch .. '@{upstream}' })
    remote = upstream:match('^([^/]+)/') or ''
  end
  if remote == '' then
    local remotes = system_text({ 'git', 'remote' })
    remote = vim.split(remotes, '\n', { plain = true, trimempty = true })[1] or ''
  end
  return remote
end

local function remote_scope(forge_name, remote)
  if remote == '' then
    return nil
  end
  local url = system_text({ 'git', 'remote', 'get-url', remote })
  if url == '' then
    return nil
  end
  return scope_mod.from_url(forge_name, url)
end

local function push_target(branch, scope)
  if scope_mod.key(scope) ~= '' then
    return scope_mod.remote_name(scope) or scope_mod.git_url(scope) or ''
  end
  return push_remote_name(branch)
end

local function branch_ref(branch, current_branch)
  if branch ~= '' and branch == current_branch and current_branch ~= '' then
    return 'HEAD'
  end
  return branch
end

local function base_ref(scope, base)
  local ref = scope_mod.remote_ref(scope, base)
  if ref and ref ~= '' then
    return ref
  end
  return 'origin/' .. base
end

local function open_web_create(label, cmd, url)
  local log = require('forge.logger')
  local success_msg = ('opened %s creation in browser'):format(label)
  local fail_msg = ('failed to open %s creation in browser'):format(label)
  if cmd then
    log.info(('opening %s creation in browser...'):format(label))
    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          log.info(success_msg)
        else
          log.error(cmd_error(result, fail_msg))
        end
      end)
    end)
    return
  end
  if not url or url == '' then
    log.error(fail_msg)
    return
  end
  local _, err = vim.ui.open(url)
  if err then
    log.error(err)
    return
  end
  log.info(success_msg)
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
  local remote = fn_system_text('git remote get-url origin')
  if not remote then
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
function M.repo_info(f, scope)
  local root = git_root()
  local key = root and (root .. '|' .. scope_mod.key(scope)) or nil
  if key and repo_info_cache[key] then
    return repo_info_cache[key]
  end
  local info = f:repo_info(scope)
  if key then
    repo_info_cache[key] = info
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
function M.file_loc(range)
  local root = git_root()
  if not root then
    return vim.fn.expand('%:t')
  end
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == '' or buf_name:match('^%w[%w+.-]*://') then
    return ''
  end
  local root_prefix = vim.fs.normalize(root) .. '/'
  local path = vim.fs.normalize(buf_name)
  if path:sub(1, #root_prefix) ~= root_prefix then
    return ''
  end
  local file = path:sub(#root_prefix + 1)
  if type(range) == 'table' and range.start_line and range.end_line then
    local s = range.start_line
    local e = range.end_line
    if s > e then
      s, e = e, s
    end
    if s == e then
      return ('%s:%d'):format(file, s)
    end
    return ('%s:%d-%d'):format(file, s, e)
  end
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
  return file
end

---@return string
function M.remote_web_url(scope)
  if scope then
    return scope_mod.web_url(scope)
  end
  if not git_root() then
    return ''
  end
  local remote = fn_system_text('git remote get-url origin')
  if not remote then
    return ''
  end
  remote = remote:gsub('%.git$', '')
  remote = remote:gsub('^ssh://git@', 'https://')
  remote = remote:gsub('^git@([^:]+):', 'https://%1/')
  return remote
end

function M.scope_from_url(name, url)
  return scope_mod.from_url(name, url)
end

function M.scope_repo_arg(scope)
  return scope_mod.repo_arg(scope)
end

function M.scope_key(scope)
  return scope_mod.key(scope)
end

function M.current_scope(name)
  local url = M.remote_web_url()
  if url == '' then
    return nil
  end
  local forge_name = name
  if not forge_name then
    local f = M.detect()
    forge_name = f and f.name or nil
  end
  if not forge_name then
    return nil
  end
  return scope_mod.from_url(forge_name, url)
end

function M.remote_name(scope)
  return scope_mod.remote_name(scope)
end

function M.remote_ref(scope, branch)
  return scope_mod.remote_ref(scope, branch)
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

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  local ref = opts.base_scope or opts.scope or M.current_scope(f.name)
  local base_scope = opts.base_scope or ref

  local current_branch = vim.trim(vim.fn.system('git branch --show-current'))
  local branch = opts.head_branch or current_branch
  if branch == '' then
    log.warn('detached HEAD')
    return
  end
  local head_scope = opts.head_scope or remote_scope(f.name, push_remote_name(branch))
  local push_to = push_target(branch, head_scope)
  local head_ref = branch_ref(branch, current_branch)

  local function with_base(cb)
    if opts.base_branch and opts.base_branch ~= '' then
      cb(opts.base_branch)
      return
    end
    log.info('resolving base branch...')
    vim.system(f:default_branch_cmd(base_scope), { text = true }, function(base_result)
      local base = vim.trim(base_result.stdout or '')
      if base == '' then
        base = 'main'
      end
      vim.schedule(function()
        cb(base)
      end)
    end)
  end

  local function ensure_creatable(base, cb)
    local target_ref = base_ref(base_scope, base)
    if branch == base and scope_mod.same(head_scope, base_scope) then
      log.warn('current branch already matches base ' .. base)
      return
    end
    local has_diff = vim
      .system({ 'git', 'diff', '--quiet', target_ref .. '..' .. head_ref }, { text = true })
      :wait().code ~= 0
    if not has_diff then
      log.warn('no changes from ' .. target_ref)
      return
    end
    cb(base, target_ref)
  end

  log.info('checking for existing ' .. f.labels.pr_one .. '...')

  vim.system(f:pr_for_branch_cmd(branch, base_scope), { text = true }, function(result)
    local num = vim.trim(result.stdout or '')
    vim.schedule(function()
      if num ~= '' and num ~= 'null' then
        M.edit_pr(num, base_scope)
        return
      end

      if opts.web then
        with_base(function(base)
          ensure_creatable(base, function()
            log.info('pushing...')
            vim.system(
              { 'git', 'push', '-u', push_to ~= '' and push_to or 'origin', branch },
              { text = true },
              function(push_result)
                vim.schedule(function()
                  if push_result.code ~= 0 then
                    log.error('push failed')
                    return
                  end
                  local web_cmd = f.create_pr_web_cmd
                      and f:create_pr_web_cmd(base_scope, head_scope, branch, base)
                    or nil
                  local web_url = f.create_pr_web_url
                      and f:create_pr_web_url(base_scope, head_scope, branch, base)
                    or nil
                  open_web_create(f.labels.pr_one, web_cmd, web_url)
                end)
              end
            )
          end)
        end)
        return
      end

      with_base(function(base)
        ensure_creatable(base, function(_, target_ref)
          if opts.instant then
            local title, body = template_mod.fill_from_commits(branch, target_ref, head_ref)
            compose_mod.push_and_create(
              f,
              branch,
              title,
              body,
              base,
              opts.draft or false,
              nil,
              base_scope,
              push_to
            )
          else
            local root = git_root() or ''
            local draft = opts.draft or false
            local tmpl, templates, err = template_mod.discover(f:template_paths(), root)
            if err then
              log.error(err)
              return
            end
            compose_mod.open_pr(
              f,
              branch,
              base,
              draft,
              templates and nil or tmpl,
              base_scope,
              push_to,
              target_ref,
              head_ref
            )
          end
        end)
      end)
    end)
  end)
end

---@param num string
---@param ref? forge.Scope
function M.edit_pr(num, ref)
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  ref = ref or M.current_scope(f.name)

  local current_branch = vim.trim(vim.fn.system('git branch --show-current'))

  log.info(('fetching %s #%s...'):format(f.labels.pr_one, num))

  vim.system(f:fetch_pr_details_cmd(num, ref), { text = true }, function(result)
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
    vim.schedule(function()
      compose_mod.open_pr_edit(f, num, details, current_branch, ref)
    end)
  end)
end

function M.edit_issue(num, ref)
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  ref = ref or M.current_scope(f.name)

  log.info(('fetching issue #%s...'):format(num))

  vim.system(f:fetch_issue_details_cmd(num, ref), { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        log.error('failed to fetch issue #' .. num)
      end)
      return
    end
    local ok, json = pcall(vim.json.decode, result.stdout or '{}')
    if not ok or type(json) ~= 'table' then
      vim.schedule(function()
        log.error('failed to parse issue details')
      end)
      return
    end
    local details = f:parse_issue_details(json)
    vim.schedule(function()
      compose_mod.open_issue_edit(f, num, details, ref)
    end)
  end)
end

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  local ref = opts.scope or M.current_scope(f.name)

  if opts.web then
    local url = f.create_issue_web_url and f:create_issue_web_url(ref) or nil
    local cmd = nil
    if not url or url == '' then
      cmd = f.create_issue_web_cmd and f:create_issue_web_cmd(ref) or nil
      url = M.remote_web_url(ref)
      if url ~= '' then
        url = url .. '/issues/new'
      end
    end
    open_web_create('issue', cmd, url)
    return
  end

  if opts.blank then
    compose_mod.open_issue(f, nil, ref)
    return
  end

  local root = git_root() or ''
  if opts.template then
    local templates = template_mod.entries(f:issue_template_paths(), root)
    if templates then
      local slug = opts.template:lower()
      for _, t in ipairs(templates) do
        if t.name:gsub('%.ya?ml$', ''):gsub('%.md$', ''):lower() == slug then
          local template, load_err = template_mod.load(t)
          if load_err then
            log.error(load_err)
            return
          end
          compose_mod.open_issue(f, template, ref)
          return
        end
      end
    end
    log.warn('template not found: ' .. opts.template)
    return
  end

  local template, templates, err = template_mod.discover(f:issue_template_paths(), root)
  if err then
    log.error(err)
    return
  end
  compose_mod.open_issue(f, templates and nil or template, ref)
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
