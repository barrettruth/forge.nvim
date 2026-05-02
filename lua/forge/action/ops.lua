local M = {}

local ci = require('forge.ci')
local detect_mod = require('forge.detect')
local log = require('forge.logger')
local repo_mod = require('forge.repo')
local system_mod = require('forge.system')

local function trim(text)
  if type(text) ~= 'string' then
    return ''
  end
  return vim.trim(text)
end

local function run_forge_cmd(kind, id, label, cmd, success_msg, fail_msg, opts)
  opts = opts or {}
  log.info(label .. ' ' .. kind .. ' #' .. id .. '...')
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log.info(('%s %s #%s'):format(success_msg, kind, id))
        if opts.on_success then
          opts.on_success()
        end
      else
        log.error(system_mod.cmd_error(result, fail_msg))
        if opts.on_failure then
          opts.on_failure()
        end
      end
    end)
  end)
end

local function normalize_pr_ref(pr)
  if type(pr) == 'table' then
    return pr
  end
  return { num = pr }
end

local function normalize_issue_ref(issue, scope)
  if type(issue) == 'table' then
    return issue
  end
  return { num = issue, scope = scope }
end

local function normalize_release_ref(release, scope)
  if type(release) == 'table' then
    return release
  end
  return { tag = release, scope = scope }
end

local function normalize_run_ref(run, scope)
  if type(run) == 'table' then
    return run
  end
  return { id = run, scope = scope }
end

local function load_details(cmd, fetch_err, parse_err, parse, open)
  vim.system(cmd, { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        log.error(system_mod.cmd_error(result, fetch_err))
      end)
      return
    end
    local ok, json = pcall(vim.json.decode, result.stdout or '{}')
    if not ok or type(json) ~= 'table' then
      vim.schedule(function()
        log.error(parse_err)
      end)
      return
    end
    local details = parse(json)
    vim.schedule(function()
      open(details)
    end)
  end)
end

---@param f forge.Forge?
---@return forge.Forge?
local function detect_or_warn(f)
  if f then
    return f
  end
  f = detect_mod.detect()
  if not f then
    detect_mod.warn_no_forge()
    return nil
  end
  return f
end

local function summary_job_at_cursor(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return require('forge.log')._summary_job_at_line(lines, vim.api.nvim_win_get_cursor(0)[1])
end

---Open a CI run as a TTY summary terminal where each line is a job and
---<cr>/`gx` open the underlying job log/url. Used by backends that set
---`capabilities.ci_terminal_view` (currently only GitHub, where `gh run
---view` and `gh run watch` provide TTY-rendered summaries that can be
---navigated by cursor line).
---@param f forge.Forge
---@param cmd string[]
---@param run forge.RunRef
---@param run_ref forge.Scope?
---@param url string?
---@param in_progress boolean
---@param status_cmd string[]?
---@param opts { watch?: boolean }?
local function open_ci_terminal_view(f, cmd, run, run_ref, url, in_progress, status_cmd, opts)
  opts = opts or {}
  local warned_job_watch = false

  local function job_log(job_id, failed)
    local job_url = url
    if f.job_web_url then
      job_url = f:job_web_url(run.id, job_id, run_ref) or job_url
    end
    return f:check_log_cmd(run.id, failed, job_id, run_ref),
      {
        forge_name = f.name,
        scope = run_ref,
        run_id = run.id,
        url = job_url,
        steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
        job_id = job_id,
        in_progress = in_progress,
        status_cmd = status_cmd,
      }
  end

  require('forge.term').open(cmd, {
    url = url,
    browse_fn = function(buf)
      local job = summary_job_at_cursor(buf)
      if job and f.job_web_url then
        return f:job_web_url(run.id, job.id, run_ref) or url
      end
      return url
    end,
    enter_fn = function(buf)
      local job = summary_job_at_cursor(buf)
      if not job then
        return
      end
      if opts.watch and in_progress and not warned_job_watch then
        warned_job_watch = true
        log.info(
          ('%s does not support per-job live watch; opening a refreshing job log instead'):format(
            (f.labels and f.labels.forge_name) or f.name
          )
        )
      end
      local log_cmd, log_opts = job_log(job.id, job.failed)
      log_opts = vim.tbl_extend('force', log_opts, {
        replace_win = vim.api.nvim_get_current_win(),
      })
      require('forge.log').open(log_cmd, log_opts)
    end,
  })
end

local function location_arg(location)
  if
    type(location) ~= 'table'
    or location.kind ~= 'location'
    or not location.path
    or location.path == ''
  then
    return nil
  end
  local range = location.range
  if not range then
    return location.path
  end
  if range.start_line == range.end_line then
    return ('%s:%d'):format(location.path, range.start_line)
  end
  return ('%s:%d-%d'):format(location.path, range.start_line, range.end_line)
end

---@param pr forge.PRRefLike
---@param f forge.Forge?
function M.pr_edit(pr, f)
  pr = normalize_pr_ref(pr)
  f = detect_or_warn(f)
  if not f then
    return
  end
  local ref = pr.scope or repo_mod.current_scope(f.name)
  local current_branch = trim(vim.fn.system('git branch --show-current'))

  log.debug(('fetching %s #%s...'):format(f.labels.pr_one, pr.num))
  load_details(
    f:fetch_pr_details_cmd(pr.num, ref),
    'failed to fetch ' .. f.labels.pr_one .. ' #' .. pr.num,
    'failed to parse ' .. f.labels.pr_one .. ' details',
    function(json)
      return f:parse_pr_details(json)
    end,
    function(details)
      require('forge.compose').open_pr_edit(f, pr.num, details, current_branch, ref)
    end
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param opts? table
function M.pr_review(f, pr, opts)
  pr = normalize_pr_ref(pr)
  require('forge.review').open(f, pr, opts)
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param opts? forge.PickerLimitOpts
function M.pr_ci(f, pr, opts)
  pr = normalize_pr_ref(pr)
  if f.capabilities.per_pr_checks then
    require('forge.pr.checks').open(f, pr, opts)
    return
  end
  log.warn(('%s does not support %s checks'):format(f.name, f.labels.pr_one))
end

---@param f forge.Forge
---@param head forge.HeadRef
---@param opts? table
function M.ci(f, head, opts)
  if not f.list_runs_json_cmd then
    log.warn('structured CI data not available for this forge')
    return
  end
  require('forge.ci.history').open(f, head, opts)
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param opts? forge.OpCallbacks
function M.pr_close(f, pr, opts)
  pr = normalize_pr_ref(pr)
  run_forge_cmd(
    f.labels.pr_one,
    pr.num,
    'closing',
    f:close_cmd(pr.num, pr.scope),
    'closed',
    'close failed',
    opts
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param opts? forge.OpCallbacks
function M.pr_reopen(f, pr, opts)
  pr = normalize_pr_ref(pr)
  run_forge_cmd(
    f.labels.pr_one,
    pr.num,
    'reopening',
    f:reopen_cmd(pr.num, pr.scope),
    'reopened',
    'reopen failed',
    opts
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param opts? forge.OpCallbacks
function M.pr_approve(f, pr, opts)
  pr = normalize_pr_ref(pr)
  run_forge_cmd(
    f.labels.pr_one,
    pr.num,
    'approving',
    f:approve_cmd(pr.num, pr.scope),
    'approved',
    'approve failed',
    opts
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param method? 'merge'|'squash'|'rebase'
---@param opts? forge.OpCallbacks
function M.pr_merge(f, pr, method, opts)
  pr = normalize_pr_ref(pr)
  run_forge_cmd(
    f.labels.pr_one,
    pr.num,
    method and ('merging (' .. method .. ')') or 'merging',
    f:merge_cmd(pr.num, method, pr.scope),
    method and ('merged (' .. method .. ')') or 'merged',
    'merge failed',
    opts
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@param is_draft boolean
---@param opts? forge.OpCallbacks
function M.pr_toggle_draft(f, pr, is_draft, opts)
  pr = normalize_pr_ref(pr)
  local cmd = f:draft_toggle_cmd(pr.num, is_draft, pr.scope)
  if not cmd then
    return
  end
  run_forge_cmd(
    f.labels.pr_one,
    pr.num,
    'toggling draft',
    cmd,
    is_draft and 'marked as ready' or 'marked as draft',
    'draft toggle failed',
    opts
  )
end

---@param f forge.Forge
---@param pr forge.PRRefLike
function M.pr_browse(f, pr)
  pr = normalize_pr_ref(pr)
  f:view_web(f.kinds.pr, pr.num, pr.scope)
end

---@param issue forge.IssueRefLike
---@param f forge.Forge?
function M.issue_edit(issue, f)
  issue = normalize_issue_ref(issue)
  f = detect_or_warn(f)
  if not f then
    return
  end
  local ref = issue.scope or repo_mod.current_scope(f.name)

  log.debug(('fetching issue #%s...'):format(issue.num))
  load_details(
    f:fetch_issue_details_cmd(issue.num, ref),
    'failed to fetch issue #' .. issue.num,
    'failed to parse issue details',
    function(json)
      return f:parse_issue_details(json)
    end,
    function(details)
      require('forge.compose').open_issue_edit(f, issue.num, details, ref)
    end
  )
end

---@param f forge.Forge
---@param issue forge.IssueRefLike
function M.issue_browse(f, issue)
  issue = normalize_issue_ref(issue)
  f:view_web(f.kinds.issue, issue.num, issue.scope)
end

---@param f forge.Forge
---@param issue forge.IssueRefLike
---@param opts? forge.OpCallbacks
function M.issue_close(f, issue, opts)
  issue = normalize_issue_ref(issue)
  run_forge_cmd(
    'issue',
    issue.num,
    'closing',
    f:close_issue_cmd(issue.num, issue.scope),
    'closed',
    'close failed',
    opts
  )
end

---@param f forge.Forge
---@param issue forge.IssueRefLike
---@param opts? forge.OpCallbacks
function M.issue_reopen(f, issue, opts)
  issue = normalize_issue_ref(issue)
  run_forge_cmd(
    'issue',
    issue.num,
    'reopening',
    f:reopen_issue_cmd(issue.num, issue.scope),
    'reopened',
    'reopen failed',
    opts
  )
end

---@param f forge.Forge
---@param run forge.RunRefLike
local function ci_log(f, run)
  run = normalize_run_ref(run)
  local run_ref = run.scope
  local status = trim(run.status):lower()
  local in_progress = ci.in_progress(status)
  local url = trim(run.url)
  if url == '' and f.run_web_url then
    url = trim(f:run_web_url(run.id, run_ref) or '')
  end
  url = url ~= '' and url or nil
  local status_cmd = f.run_status_cmd and f:run_status_cmd(run.id, run_ref) or nil
  if f.capabilities and f.capabilities.ci_terminal_view and f.view_cmd then
    open_ci_terminal_view(
      f,
      f:view_cmd(run.id, { scope = run_ref }),
      run,
      run_ref,
      url,
      in_progress,
      status_cmd
    )
    return
  end
  if f.view_cmd then
    require('forge.log').open_summary(f:view_cmd(run.id, { scope = run_ref }), {
      forge_name = f.name,
      scope = run_ref,
      run_id = run.id,
      url = url,
      in_progress = in_progress,
      status_cmd = status_cmd,
      browse_url_fn = function(job_id)
        if f.job_web_url then
          return f:job_web_url(run.id, job_id, run_ref)
        end
        return nil
      end,
      log_cmd_fn = function(job_id, failed)
        local job_url = url
        if f.job_web_url then
          job_url = f:job_web_url(run.id, job_id, run_ref) or job_url
        end
        return f:check_log_cmd(run.id, failed, job_id, run_ref),
          {
            forge_name = f.name,
            scope = run_ref,
            run_id = run.id,
            url = job_url,
            steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
            job_id = job_id,
            in_progress = in_progress,
            status_cmd = status_cmd,
          }
      end,
    })
    return
  end
  if f.summary_json_cmd then
    require('forge.log').open_summary(f:summary_json_cmd(run.id, run_ref), {
      forge_name = f.name,
      scope = run_ref,
      run_id = run.id,
      url = url,
      in_progress = in_progress,
      status_cmd = status_cmd,
      json = true,
      browse_url_fn = function(job_id)
        if f.job_web_url then
          return f:job_web_url(run.id, job_id, run_ref)
        end
        return nil
      end,
      log_cmd_fn = function(job_id, failed)
        local job_url = url
        if f.job_web_url then
          job_url = f:job_web_url(run.id, job_id, run_ref) or job_url
        end
        return f:check_log_cmd(run.id, failed, job_id, run_ref),
          {
            forge_name = f.name,
            scope = run_ref,
            run_id = run.id,
            url = job_url,
            steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
            job_id = job_id,
            in_progress = in_progress,
            status_cmd = status_cmd,
          }
      end,
    })
    return
  end
  log.debug('fetching CI/CD logs...')
  require('forge.log').open(
    f:run_log_cmd(run.id, status == 'failure' or status == 'failed', run_ref),
    {
      forge_name = f.name,
      scope = run_ref,
      run_id = run.id,
      url = url,
      steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
      in_progress = in_progress,
      status_cmd = status_cmd,
    }
  )
end

---@param f forge.Forge
---@param run forge.RunRefLike
---@return boolean
local function ci_watch(f, run)
  run = normalize_run_ref(run)
  if not f.watch_cmd then
    return false
  end
  local run_ref = run.scope
  local status = trim(run.status):lower()
  local in_progress = ci.in_progress(status)
  local url = trim(run.url)
  if url == '' and f.run_web_url then
    url = trim(f:run_web_url(run.id, run_ref) or '')
  end
  url = url ~= '' and url or nil
  local status_cmd = f.run_status_cmd and f:run_status_cmd(run.id, run_ref) or nil
  if f.capabilities and f.capabilities.ci_terminal_view then
    open_ci_terminal_view(
      f,
      f:watch_cmd(run.id, run_ref),
      run,
      run_ref,
      url,
      in_progress,
      status_cmd,
      { watch = true }
    )
    return true
  end
  require('forge.term').open(f:watch_cmd(run.id, run_ref), {
    url = url,
  })
  return true
end

---@param f forge.Forge
---@param run forge.RunRefLike
function M.ci_open(f, run)
  run = normalize_run_ref(run)
  if ci.in_progress(run.status) and ci_watch(f, run) then
    return
  end
  ci_log(f, run)
end

---@param f forge.Forge
---@param run forge.RunRefLike
function M.ci_browse(f, run)
  run = normalize_run_ref(run)
  if f.browse_run then
    return f:browse_run(run.id, run.scope)
  end
  local url = f.run_web_url and f:run_web_url(run.id, run.scope) or nil
  if not url or url == '' then
    log.warn(('%s does not support ci run pages'):format(f.name))
    return
  end
  local _, err = vim.ui.open(url)
  if err then
    log.error(err)
  end
end

---@param f forge.Forge
---@param run forge.RunRefLike
---@param opts? forge.OpCallbacks
function M.ci_cancel(f, run, opts)
  run = normalize_run_ref(run)
  opts = opts or {}
  if not f.cancel_run_cmd then
    log.warn(('%s does not support cancelling runs'):format(f.name))
    if opts.on_failure then
      opts.on_failure()
    end
    return
  end
  run_forge_cmd(
    'run',
    run.id,
    'cancelling',
    f:cancel_run_cmd(run.id, run.scope),
    'cancelled',
    'cancel failed',
    opts
  )
end

---@param f forge.Forge
---@param run forge.RunRefLike
---@param opts? forge.OpCallbacks
function M.ci_rerun(f, run, opts)
  run = normalize_run_ref(run)
  opts = opts or {}
  if not f.rerun_run_cmd then
    log.warn(('%s does not support rerunning runs'):format(f.name))
    if opts.on_failure then
      opts.on_failure()
    end
    return
  end
  run_forge_cmd(
    'run',
    run.id,
    'rerunning',
    f:rerun_run_cmd(run.id, run.scope),
    'rerun started',
    'rerun failed',
    opts
  )
end

---@param f forge.Forge
---@param run forge.RunRefLike
---@param opts? forge.OpCallbacks
function M.ci_toggle(f, run, opts)
  run = normalize_run_ref(run)
  opts = opts or {}
  local verb = ci.toggle_verb(run)
  if verb == nil then
    log.warn('nothing to toggle for skipped run')
    if opts.on_failure then
      opts.on_failure()
    end
    return
  end
  if verb == 'cancel' then
    M.ci_cancel(f, run, opts)
  else
    M.ci_rerun(f, run, opts)
  end
end

---@param f forge.Forge
---@param release forge.ReleaseRefLike
function M.release_browse(f, release)
  release = normalize_release_ref(release)
  f:browse_release(release.tag, release.scope)
end

---@param f forge.Forge
---@param release forge.ReleaseRefLike
---@param opts? forge.OpCallbacks
function M.release_delete(f, release, opts)
  release = normalize_release_ref(release)
  opts = opts or {}
  run_forge_cmd(
    'release',
    release.tag,
    'deleting',
    f:delete_release_cmd(release.tag, release.scope),
    'deleted',
    'delete failed',
    opts
  )
end

---@param f forge.Forge
---@param kind forge.WebKind
---@param opts? forge.RouteOpts
function M.list_browse(f, kind, opts)
  opts = opts or {}
  local url = f.list_web_url and f:list_web_url(kind, opts.scope) or nil
  if not url or url == '' then
    log.warn(('%s does not support %s landing pages'):format(f.name, kind))
    return
  end
  local _, err = vim.ui.open(url)
  if err then
    log.error(err)
  end
end

---@param f forge.Forge
---@param ref forge.SubjectRef
function M.browse_subject(f, ref)
  if not f.browse_subject then
    log.warn(('%s does not support browse by number'):format(f.name))
    return
  end
  f:browse_subject(ref.num, ref.scope)
end

---@param opts? forge.ScopedOpts
---@return boolean
function M.browse_repo(opts)
  local scope = type(opts) == 'table' and opts.scope or nil
  local url = repo_mod.remote_web_url(scope)
  if trim(url) == '' then
    return false
  end
  vim.ui.open(url)
  return true
end

---@param f forge.Forge
---@param location table
---@param scope? forge.Scope
---@param branch? string
---@return boolean
function M.browse_location(f, location, scope, branch)
  local loc = location_arg(location)
  if not loc then
    return false
  end
  local rev = location.rev and location.rev.rev or trim(branch)
  if rev == '' then
    return false
  end
  f:browse(loc, rev, scope)
  return true
end

---@param f forge.Forge
---@param file_loc string?
---@param branch string?
---@param scope? forge.Scope
---@return boolean
function M.browse_file(f, file_loc, branch, scope)
  file_loc = trim(file_loc)
  branch = trim(branch)
  if file_loc == '' or branch == '' then
    return false
  end
  f:browse(file_loc, branch, scope)
  return true
end

return M
