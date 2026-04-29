local M = {}

local compose_mod = require('forge.compose')
local detect_mod = require('forge.detect')
local log = require('forge.logger')
local repo_mod = require('forge.repo')
local resolve_mod = require('forge.resolve')
local scope_mod = require('forge.scope')
local system_mod = require('forge.system')
local target_mod = require('forge.target')
local template_mod = require('forge.compose.template')

local git_root = detect_mod.git_root

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
  local success_msg = ('opened %s creation in browser'):format(label)
  local fail_msg = ('failed to open %s creation in browser'):format(label)
  if cmd then
    log.debug(('opening %s creation in browser...'):format(label))
    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          log.info(success_msg)
        else
          log.error(system_mod.cmd_error(result, fail_msg))
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

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  opts = opts or {}

  local f = detect_mod.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  local ref = opts.base_scope or opts.scope or repo_mod.current_scope(f.name)
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
    log.debug('resolving base branch...')
    vim.system(f:default_branch_cmd(base_scope), { text = true }, function(base_result)
      local base = vim.trim(base_result.stdout or '')
      if base_result.code ~= 0 or base == '' then
        vim.schedule(function()
          log.error(system_mod.cmd_error(base_result, 'failed to resolve base branch'))
        end)
        return
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

  log.debug('checking for existing ' .. f.labels.pr_one .. '...')
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
        log.debug('pushing...')
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
          push_to,
          nil,
          head_scope
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
          head_ref,
          head_scope
        )
      end
    end)
  end)
end

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  opts = opts or {}

  local f = detect_mod.detect()
  if not f then
    log.warn('no forge detected')
    return
  end
  local ref = opts.scope or repo_mod.current_scope(f.name)

  if opts.web then
    local url = f.create_issue_web_url and f:create_issue_web_url(ref) or nil
    local cmd = nil
    if not url or url == '' then
      cmd = f.create_issue_web_cmd and f:create_issue_web_cmd(ref) or nil
      url = repo_mod.remote_web_url(ref)
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
  local f = detect_mod.detect()
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

return M
