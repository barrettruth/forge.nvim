local M = {}

local log = require('forge.logger')

local function trim(text)
  if type(text) ~= 'string' then
    return ''
  end
  return vim.trim(text)
end

local function cmd_error(result, fallback)
  local msg = result.stderr or ''
  if vim.trim(msg) == '' then
    msg = result.stdout or ''
  end
  msg = vim.trim(msg)
  if msg == '' then
    msg = fallback
  end
  return msg
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
        log.error(cmd_error(result, fail_msg))
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

local function summary_job_at_cursor(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = require('forge.log')._parse_summary(lines)
  return parsed.jobs[vim.api.nvim_win_get_cursor(0)[1]]
end

local function github_ci_log_term(f, run, run_ref, url, in_progress, status_cmd)
  local function job_log(job_id, failed)
    return f:check_log_cmd(run.id, failed, job_id, run_ref),
      {
        forge_name = f.name,
        url = url,
        title = (run.name or run.id) .. ' / ' .. (job_id or ''),
        steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
        job_id = job_id,
        in_progress = in_progress,
        status_cmd = status_cmd,
      }
  end

  require('forge.term').open(f:view_cmd(run.id, { scope = run_ref }), {
    url = url,
    startinsert = false,
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
      local cmd, opts = job_log(job.id, job.failed)
      require('forge.log').open(cmd, opts)
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

function M.pr_list(state, opts)
  require('forge').open(state and ('prs.' .. state) or 'prs', opts)
end

function M.pr_create(opts)
  require('forge').create_pr(opts)
end

function M.pr_edit(pr)
  pr = normalize_pr_ref(pr)
  require('forge').edit_pr(pr.num, pr.scope)
end

function M.pr_checkout(f, pr)
  pr = normalize_pr_ref(pr)
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
end

function M.pr_browse(f, pr)
  pr = normalize_pr_ref(pr)
  f:view_web(f.kinds.pr, pr.num, pr.scope)
end

function M.pr_worktree(f, pr)
  pr = normalize_pr_ref(pr)
  local kind = f.labels.pr_one
  local fetch_cmd = f:fetch_pr(pr.num, pr.scope)
  local branch = fetch_cmd[#fetch_cmd]:match(':(.+)$')
  if not branch then
    return
  end
  local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
  local wt_path = vim.fs.normalize(root .. '/../' .. branch)
  log.info(('fetching %s #%s into worktree...'):format(kind, pr.num))
  vim.system(fetch_cmd, { text = true }, function()
    vim.system({ 'git', 'worktree', 'add', wt_path, branch }, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          log.info(('worktree at %s'):format(wt_path))
        else
          log.error(cmd_error(result, 'worktree failed'))
        end
      end)
    end)
  end)
end

function M.pr_ci(f, pr, opts)
  pr = normalize_pr_ref(pr)
  opts = vim.tbl_extend('force', opts or {}, { scope = pr.scope })
  local pickers = require('forge.pickers')
  if f.capabilities.per_pr_checks then
    pickers.checks(f, pr.num, nil, nil, opts)
  else
    log.debug(('per-%s checks unavailable on %s, showing repo CI'):format(f.labels.pr_one, f.name))
    pickers.ci(f, nil, nil, opts)
  end
end

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

function M.issue_list(state, opts)
  require('forge').open(state and ('issues.' .. state) or 'issues', opts)
end

function M.issue_create(opts)
  require('forge').create_issue(opts)
end

function M.issue_edit(issue)
  issue = normalize_issue_ref(issue)
  require('forge').edit_issue(issue.num, issue.scope)
end

function M.issue_browse(f, issue)
  issue = normalize_issue_ref(issue)
  f:view_web(f.kinds.issue, issue.num, issue.scope)
end

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

function M.ci_list(branch, opts)
  opts = vim.tbl_extend('force', opts or {}, { branch = branch })
  require('forge').open(branch == nil and 'ci.all' or 'ci.current_branch', opts)
end

function M.ci_log(f, run)
  run = normalize_run_ref(run)
  local run_ref = run.scope
  local status = trim(run.status):lower()
  local in_progress = status == 'in_progress'
    or status == 'queued'
    or status == 'pending'
    or status == 'running'
  local url = trim(run.url)
  if url == '' and f.run_web_url then
    url = trim(f:run_web_url(run.id, run_ref) or '')
  end
  url = url ~= '' and url or nil
  local status_cmd = f.run_status_cmd and f:run_status_cmd(run.id, run_ref) or nil
  if f.name == 'github' and f.view_cmd then
    github_ci_log_term(f, run, run_ref, url, in_progress, status_cmd)
    return
  end
  if f.view_cmd then
    require('forge.log').open_summary(f:view_cmd(run.id, { scope = run_ref }), {
      forge_name = f.name,
      run_id = run.id,
      url = url,
      title = run.name or run.id,
      in_progress = in_progress,
      status_cmd = status_cmd,
      browse_url_fn = function(job_id)
        if f.job_web_url then
          return f:job_web_url(run.id, job_id, run_ref)
        end
        return nil
      end,
      log_cmd_fn = function(job_id, failed)
        return f:check_log_cmd(run.id, failed, job_id, run_ref),
          {
            forge_name = f.name,
            url = url,
            title = (run.name or run.id) .. ' / ' .. (job_id or ''),
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
      run_id = run.id,
      url = url,
      title = run.name or run.id,
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
        return f:check_log_cmd(run.id, failed, job_id, run_ref),
          {
            forge_name = f.name,
            url = url,
            title = (run.name or run.id) .. ' / ' .. (job_id or ''),
            steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
            job_id = job_id,
            in_progress = in_progress,
            status_cmd = status_cmd,
          }
      end,
    })
    return
  end
  log.info('fetching CI/CD logs...')
  require('forge.log').open(
    f:run_log_cmd(run.id, status == 'failure' or status == 'failed', run_ref),
    {
      forge_name = f.name,
      url = url,
      title = run.name or run.id,
      steps_cmd = f.steps_cmd and f:steps_cmd(run.id, run_ref) or nil,
      in_progress = in_progress,
      status_cmd = status_cmd,
    }
  )
end

function M.ci_watch(f, run)
  run = normalize_run_ref(run)
  if not f.watch_cmd then
    return false
  end
  local url = trim(run.url)
  if url == '' and f.run_web_url then
    url = trim(f:run_web_url(run.id, run.scope) or '')
  end
  require('forge.term').open(f:watch_cmd(run.id, run.scope), {
    url = url ~= '' and url or nil,
  })
  return true
end

function M.release_list(state, opts)
  require('forge').open(state and ('releases.' .. state) or 'releases', opts)
end

function M.release_browse(f, release)
  release = normalize_release_ref(release)
  f:browse_release(release.tag, release.scope)
end

function M.release_delete(f, release, opts)
  release = normalize_release_ref(release)
  opts = opts or {}
  local function do_delete()
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
  if opts.confirm == false then
    do_delete()
    return
  end
  vim.ui.select({ 'Yes', 'No' }, {
    prompt = 'Delete release ' .. release.tag .. '? ',
  }, function(choice)
    if choice == 'Yes' then
      do_delete()
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end)
end

function M.browse_commit(opts)
  require('forge').open('browse.commit', opts)
end

function M.browse_repo(opts)
  local scope = type(opts) == 'table' and opts.scope or nil
  local url = require('forge').remote_web_url(scope)
  if trim(url) == '' then
    return false
  end
  vim.ui.open(url)
  return true
end

function M.browse_branch(branch, opts)
  require('forge').open('browse.branch', vim.tbl_extend('force', opts or {}, { branch = branch }))
end

function M.browse_contextual(opts)
  require('forge').open('browse.contextual', opts)
end

function M.browse_location(f, location, scope)
  local loc = location_arg(location)
  if not loc then
    return false
  end
  f:browse(loc, location.rev.rev, scope)
  return true
end

function M.browse_file(f, file_loc, branch, scope)
  if trim(file_loc) == '' or trim(branch) == '' then
    return false
  end
  f:browse(file_loc, branch, scope)
  return true
end

return M
