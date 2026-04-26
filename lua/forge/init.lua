local M = {}

local action_mod = require('forge.action')
local cache_mod = require('forge.cache')
local compose_mod = require('forge.compose')
local config_mod = require('forge.config')
local context_mod = require('forge.context')
local format_mod = require('forge.format')
local resolve_mod = require('forge.resolve')
local review_mod = require('forge.review')
local scope_mod = require('forge.scope')
local target_mod = require('forge.target')
local template_mod = require('forge.template')

---@type table<string, forge.Forge>
local sources = {}

---@param name string
---@param source forge.Forge
function M.register(name, source)
  sources[name] = source
end

M.register_source = M.register
M.register_context_provider = context_mod.register
M.register_action = action_mod.register
M.register_review_adapter = review_mod.register
M.run_action = action_mod.run

---@return table<string, forge.Forge>
function M.registered_sources()
  return sources
end

function M.review_adapter_names()
  return review_mod.names()
end

---@type table<string, forge.Forge>
local forge_cache = {}

---@type table<string, string>
local root_cache = {}

local repo_info_cache = cache_mod.new(30 * 60)
local pr_state_cache = cache_mod.new(60)
local list_cache = cache_mod.new(2 * 60)

---@param cmd string
---@return string?
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

---@param num string
---@param scope? forge.Scope
---@return string?
local function pr_state_key(num, scope)
  local root = git_root()
  return root and (root .. '|' .. scope_mod.key(scope) .. '|' .. num) or nil
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

local function push_target(branch, scope)
  if scope_mod.key(scope) ~= '' then
    return scope_mod.remote_name(scope) or scope_mod.git_url(scope) or ''
  end
  local repo = target_mod.push_repo_for_branch(branch)
  return type(repo) == 'table' and repo.remote or ''
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
  local ok, mod = pcall(require, 'forge.backends.' .. name)
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
---@param scope? forge.Scope
---@return forge.RepoInfo
function M.repo_info(f, scope)
  local root = git_root()
  local key = root and (root .. '|' .. scope_mod.key(scope)) or nil
  if key then
    local cached = repo_info_cache.get(key)
    if cached ~= nil then
      return cached
    end
  end
  local info = f:repo_info(scope)
  if key then
    repo_info_cache.set(key, info)
  end
  return info
end

---@param f forge.Forge
---@param num string
---@param scope? forge.Scope
---@return forge.PRState
function M.pr_state(f, num, scope)
  local key = pr_state_key(num, scope)
  if key then
    local cached = pr_state_cache.get(key)
    if cached ~= nil then
      return cached
    end
  end
  local state = f:pr_state(num, scope)
  if key then
    pr_state_cache.set(key, state)
  end
  return state
end

---@param num string
---@param state forge.PRState
---@param scope? forge.Scope
---@return forge.PRState
function M.set_pr_state(num, state, scope)
  local key = pr_state_key(num, scope)
  if key then
    pr_state_cache.set(key, state)
  end
  return state
end

---@param num? string
---@param scope? forge.Scope
function M.clear_pr_state(num, scope)
  local root = git_root()
  if not root then
    pr_state_cache.clear()
    return
  end
  if num ~= nil then
    local key = pr_state_key(num, scope)
    if key then
      pr_state_cache.clear(key)
      return
    end
    pr_state_cache.clear()
    return
  end
  if scope ~= nil then
    pr_state_cache.clear_prefix(root .. '|' .. scope_mod.key(scope) .. '|')
    return
  end
  pr_state_cache.clear()
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
  return list_cache.get(key)
end

---@param key string
---@param data table[]
function M.set_list(key, data)
  list_cache.set(key, data)
end

---@param key string?
function M.clear_list(key)
  list_cache.clear(key)
end

---@param kind string
function M.clear_list_kind(kind)
  local root = git_root() or ''
  list_cache.clear_prefix(root .. ':' .. kind .. ':')
end

function M.clear_cache()
  forge_cache = {}
  repo_info_cache.clear()
  pr_state_cache.clear()
  root_cache = {}
  list_cache.clear()
end

---@param range? { start_line: integer, end_line: integer }
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

---@param scope? forge.Scope
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

---@param name forge.ScopeKind
---@param url string
---@return forge.Scope?
function M.scope_from_url(name, url)
  return scope_mod.from_url(name, url)
end

---@param scope forge.Scope?
---@return string?
function M.scope_repo_arg(scope)
  return scope_mod.repo_arg(scope)
end

---@param scope forge.Scope?
---@return string
function M.scope_key(scope)
  return scope_mod.key(scope)
end

---@param name? forge.ScopeKind
---@return forge.Scope?
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

---@param scope forge.Scope?
---@return string?
function M.remote_name(scope)
  return scope_mod.remote_name(scope)
end

---@param scope forge.Scope?
---@param branch string
---@return string?
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

---@return forge.Forge?
local function detect_or_warn()
  local log = require('forge.logger')
  local forge = M.detect()
  if not forge then
    log.warn('no forge detected')
    return nil
  end
  return forge
end

---@param opts forge.CurrentPROpts?
---@param forge forge.Forge
---@return forge.CurrentPROpts
local function implicit_ref_opts(opts, forge)
  return vim.tbl_extend('force', { forge = forge }, opts or {})
end

---@param opts forge.PRActionOpts?
---@return string?, boolean
local function explicit_pr_num(opts)
  if type(opts) ~= 'table' then
    return nil, false
  end
  local num = opts.num
  if num == nil then
    return nil, false
  end
  ---@type string?
  local text = nil
  if type(num) == 'number' then
    text = tostring(num)
  elseif type(num) == 'string' then
    text = num
  end
  if text == nil then
    return nil, true
  end
  text = vim.trim(text)
  if text == '' then
    return nil, true
  end
  return text, true
end

---@param opts forge.PRActionOpts?
---@param forge forge.Forge?
---@return forge.PRRef?
local function resolve_explicit_pr(opts, forge)
  local log = require('forge.logger')
  local num = explicit_pr_num(opts)
  if not num then
    return nil
  end
  ---@cast opts forge.PRActionOpts

  local scope = opts.scope
  if scope == nil and opts.repo ~= nil then
    forge = forge or detect_or_warn()
    if not forge then
      return nil
    end
    local repo_scope, scope_err = resolve_mod.repo(nil, implicit_ref_opts(opts, forge))
    if scope_err then
      log.warn(scope_err.message or 'invalid repo address')
      return nil
    end
    scope = repo_scope
  end

  return {
    num = num,
    scope = scope,
  }
end

---@param opts forge.ReviewOpts?
---@return { adapter: string? }
local function review_action_opts(opts)
  return {
    adapter = type(opts) == 'table' and opts.adapter or nil,
  }
end

local resolve_action_pr

---@param opts forge.PRActionOpts?
---@param require_forge boolean?
---@return forge.Forge?, forge.PRRef?
local function resolve_pr_action_target(opts, require_forge)
  local log = require('forge.logger')
  local num, explicit = explicit_pr_num(opts)
  if explicit then
    local forge = nil
    if require_forge or (type(opts) == 'table' and opts.repo ~= nil) then
      forge = detect_or_warn()
      if not forge then
        return nil
      end
    end
    if not num then
      local f = forge or M.detect()
      local label = (f and f.labels and f.labels.pr_one) or 'PR'
      log.warn('missing ' .. label .. ' number')
      return nil
    end
    return forge, resolve_explicit_pr(opts, forge)
  end
  return resolve_action_pr(opts)
end

---@param opts forge.CurrentPROpts?
---@return forge.Forge?, forge.PRRef?
resolve_action_pr = function(opts)
  local log = require('forge.logger')
  local forge = detect_or_warn()
  if not forge then
    return nil
  end
  local pr, err = M.current_pr(implicit_ref_opts(opts, forge))
  if err then
    log.warn(err.message or 'current PR lookup failed')
    return nil
  end
  if pr then
    return forge, pr
  end
  log.warn(('no open %s found for this branch'):format(forge.labels.pr_one or 'PR'))
  return nil
end

---@param opts forge.BranchCIOpts?
---@return forge.Forge?, forge.HeadRef?
local function resolve_ci_head(opts)
  local log = require('forge.logger')
  local forge = detect_or_warn()
  if not forge then
    return nil
  end

  opts = opts or {}
  local head_input = opts.head
  if
    head_input == nil and (opts.branch ~= nil or opts.head_branch ~= nil or opts.head_scope ~= nil)
  then
    head_input = {
      branch = opts.branch or opts.head_branch,
      scope = opts.head_scope,
    }
  end

  local head, head_err = resolve_mod.head(head_input, implicit_ref_opts(opts, forge))
  if not head then
    log.warn((head_err and head_err.message) or 'invalid head')
    return nil
  end

  if opts.repo ~= nil or opts.scope ~= nil then
    local scope, scope_err = resolve_mod.repo(nil, implicit_ref_opts(opts, forge))
    if scope_err then
      log.warn(scope_err.message or 'invalid repo address')
      return nil
    end
    head.scope = scope or head.scope
  end

  return forge, head
end

---@param opts forge.PRActionOpts?
function M.pr(opts)
  local forge, pr = resolve_pr_action_target(opts)
  if not pr then
    return
  end
  require('forge.ops').pr_edit(pr, forge)
end

---@param opts forge.ReviewOpts?
function M.review(opts)
  local forge, pr = resolve_pr_action_target(opts, true)
  if not forge or not pr then
    return
  end
  require('forge.ops').pr_review(forge, pr, review_action_opts(opts))
end

---@param opts forge.PRActionOpts?
function M.pr_ci(opts)
  local forge, pr = resolve_pr_action_target(opts, true)
  if not forge or not pr then
    return
  end
  require('forge.ops').pr_ci(forge, pr)
end

---@param opts forge.BranchCIOpts?
function M.ci(opts)
  local _, head = resolve_ci_head(opts)
  if not head then
    return
  end
  require('forge.ops').ci_list(head.branch, {
    scope = head.scope,
  })
end

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
  local head_scope = opts.head_scope or target_mod.push_scope_for_branch(branch, f.name)
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
  local existing, err = resolve_mod.current_pr({
    forge = f,
    scope = base_scope,
    head_branch = branch,
    head_scope = head_scope,
  })
  if err then
    log.error(err.message)
    return
  end
  if existing then
    log.warn(
      ('%s already exists for this branch (#%s); use :Forge pr or :Forge review'):format(
        f.labels.pr_one,
        existing.num
      )
    )
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
        local tmpl, templates, discover_err = template_mod.discover(f:template_paths(), root)
        if discover_err then
          log.error(discover_err)
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
end

---@param num string
---@param ref? forge.Scope
function M.edit_issue(num, ref)
  require('forge.ops').issue_edit({
    num = num,
    scope = ref,
  })
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

---@return string[]
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
M.current_pr = resolve_mod.current_pr

local routes_mod = require('forge.routes')
M.current_context = routes_mod.current_context
M.open = routes_mod.open

return M
