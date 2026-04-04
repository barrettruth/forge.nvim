local M = {}

local log = require('forge.logger')
local picker = require('forge.picker')

---@param result { code: integer, stdout: string?, stderr: string? }
---@param fallback string
---@return string
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

---@param kind string
---@param num string
---@param label string
---@param cmd string[]
---@param success_msg string
---@param fail_msg string
local function run_forge_cmd(kind, num, label, cmd, success_msg, fail_msg)
  log.info(label .. ' ' .. kind .. ' #' .. num .. '...')
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log.info(('%s %s #%s'):format(success_msg, kind, num))
      else
        log.error(cmd_error(result, fail_msg))
      end
    end)
  end)
end

---@param f forge.Forge
---@param num string
---@param is_open boolean
local function issue_toggle_state(f, num, is_open)
  if is_open then
    run_forge_cmd('issue', num, 'closing', f:close_issue_cmd(num), 'closed', 'close failed')
  else
    run_forge_cmd('issue', num, 'reopening', f:reopen_issue_cmd(num), 'reopened', 'reopen failed')
  end
end

---@param f forge.Forge
---@param num string
---@return table<string, function>
local function pr_action_fns(f, num)
  local kind = f.labels.pr_one
  return {
    checkout = function()
      log.info(('checking out %s #%s...'):format(kind, num))
      vim.system(f:checkout_cmd(num), { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 then
            log.info(('checked out %s #%s'):format(kind, num))
          else
            log.error(cmd_error(result, 'checkout failed'))
          end
        end)
      end)
    end,
    browse = function()
      f:view_web(f.kinds.pr, num)
    end,
    worktree = function()
      local fetch_cmd = f:fetch_pr(num)
      local branch = fetch_cmd[#fetch_cmd]:match(':(.+)$')
      if not branch then
        return
      end
      local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
      local wt_path = vim.fs.normalize(root .. '/../' .. branch)
      log.info(('fetching %s #%s into worktree...'):format(kind, num))
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
    end,
    diff = function()
      local review = require('forge.review')
      local repo_root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))

      log.info(('reviewing %s #%s...'):format(kind, num))
      vim.system(f:checkout_cmd(num), { text = true }, function(co_result)
        if co_result.code ~= 0 then
          vim.schedule(function()
            log.debug('checkout skipped, proceeding with diff')
          end)
        end

        vim.system(f:pr_base_cmd(num), { text = true }, function(base_result)
          vim.schedule(function()
            local base = vim.trim(base_result.stdout or '')
            if base == '' or base_result.code ~= 0 then
              base = 'main'
            end
            local range = 'origin/' .. base
            review.start(range)
            local ok, commands = pcall(require, 'diffs.commands')
            if ok then
              commands.greview(range, { repo_root = repo_root })
            end
            log.debug(('review ready for %s #%s against %s'):format(kind, num, base))
          end)
        end)
      end)
    end,
    ci = function()
      if f.capabilities.per_pr_checks then
        M.checks(f, num)
      else
        log.debug(('per-%s checks unavailable on %s, showing repo CI'):format(kind, f.name))
        M.ci(f)
      end
    end,
    manage = function()
      M.pr_manage(f, num)
    end,
  }
end

---@param f forge.Forge
---@param num string
local function pr_manage_picker(f, num)
  local forge_mod = require('forge')
  local kind = f.labels.pr_one
  log.info('loading actions for ' .. kind .. ' #' .. num .. '...')

  local info = forge_mod.repo_info(f)
  local can_write = info.permission == 'ADMIN'
    or info.permission == 'MAINTAIN'
    or info.permission == 'WRITE'
  local pr_state = f:pr_state(num)
  local is_open = pr_state.state == 'OPEN' or pr_state.state == 'OPENED'

  local entries = {}
  local action_map = {}

  local function add(label, fn)
    table.insert(entries, {
      display = { { label } },
      value = label,
    })
    action_map[label] = fn
  end

  if can_write and is_open then
    add('Approve', function()
      run_forge_cmd(kind, num, 'approving', f:approve_cmd(num), 'approved', 'approve failed')
    end)
  end

  if can_write and is_open then
    for _, method in ipairs(info.merge_methods) do
      add('Merge (' .. method .. ')', function()
        run_forge_cmd(
          kind,
          num,
          'merging (' .. method .. ')',
          f:merge_cmd(num, method),
          'merged (' .. method .. ')',
          'merge failed'
        )
      end)
    end
  end

  if is_open then
    add('Close', function()
      run_forge_cmd(kind, num, 'closing', f:close_cmd(num), 'closed', 'close failed')
    end)
  else
    add('Reopen', function()
      run_forge_cmd(kind, num, 'reopening', f:reopen_cmd(num), 'reopened', 'reopen failed')
    end)
  end

  local draft_cmd = f:draft_toggle_cmd(num, pr_state.is_draft)
  if draft_cmd then
    local draft_label = pr_state.is_draft and 'Mark as ready' or 'Mark as draft'
    local draft_done = pr_state.is_draft and 'marked as ready' or 'marked as draft'
    add(draft_label, function()
      run_forge_cmd(kind, num, 'toggling draft', draft_cmd, draft_done, 'draft toggle failed')
    end)
  end

  picker.pick({
    prompt = ('%s #%s Actions> '):format(kind, num),
    entries = entries,
    actions = {
      {
        name = 'default',
        fn = function(entry)
          if entry and action_map[entry.value] then
            action_map[entry.value]()
          end
        end,
      },
    },
    picker_name = '_menu',
  })
end

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
function M.checks(f, num, filter, cached_checks)
  filter = filter or 'all'
  local forge_mod = require('forge')

  local function open_picker(checks)
    local filtered = forge_mod.filter_checks(checks, filter)
    local entries = {}
    for _, c in ipairs(filtered) do
      table.insert(entries, {
        display = forge_mod.format_check(c),
        value = c,
        ordinal = c.name or '',
      })
    end

    local labels = {
      all = 'all',
      fail = 'failed',
      pass = 'passed',
      pending = 'running',
    }

    picker.pick({
      prompt = ('Checks (#%s, %s)> '):format(num, labels[filter] or filter),
      entries = entries,
      actions = {
        {
          name = 'log',
          fn = function(entry)
            if not entry then
              return
            end
            local c = entry.value
            local run_id = c.run_id or (c.link or ''):match('/actions/runs/(%d+)')
            if not run_id then
              log.info('logs not available, use browse to view')
              return
            end
            local job_id = c.job_id or (c.link or ''):match('/job/(%d+)')
            local bucket = (c.bucket or ''):lower()
            if bucket == 'skipping' then
              log.info('no log available — job was not started')
              return
            end
            local in_progress = bucket == 'pending'
            if in_progress and f.live_tail_cmd then
              require('forge.term').open(f:live_tail_cmd(run_id, job_id), { url = c.link })
            else
              log.info('fetching check logs...')
              local cmd = f:check_log_cmd(run_id, bucket == 'fail', job_id)
              local steps_cmd = f.steps_cmd and f:steps_cmd(run_id) or nil
              local status_cmd = f.run_status_cmd and f:run_status_cmd(run_id) or nil
              require('forge.log').open(cmd, {
                forge_name = f.name,
                url = c.link,
                title = c.name or run_id,
                steps_cmd = steps_cmd,
                job_id = job_id,
                in_progress = in_progress,
                status_cmd = status_cmd,
              })
            end
          end,
        },
        {
          name = 'browse',
          fn = function(entry)
            if entry and entry.value.link then
              vim.ui.open(entry.value.link)
            end
          end,
        },
        {
          name = 'failed',
          fn = function()
            M.checks(f, num, 'fail', checks)
          end,
        },
        {
          name = 'passed',
          fn = function()
            M.checks(f, num, 'pass', checks)
          end,
        },
        {
          name = 'running',
          fn = function()
            M.checks(f, num, 'pending', checks)
          end,
        },
        {
          name = 'all',
          fn = function()
            M.checks(f, num, 'all', checks)
          end,
        },
        {
          name = 'refresh',
          fn = function()
            log.info(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
            M.checks(f, num, filter)
          end,
        },
      },
      picker_name = 'ci',
    })
  end

  if cached_checks then
    log.debug(('checks (%s #%s, cached)'):format(f.labels.pr_one, num))
    open_picker(cached_checks)
    return
  end

  if f.checks_json_cmd then
    log.info(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
    vim.system(f:checks_json_cmd(num), { text = true }, function(result)
      vim.schedule(function()
        local ok, checks = pcall(vim.json.decode, result.stdout or '[]')
        if ok and checks then
          open_picker(checks)
        else
          log.info('no checks found')
        end
      end)
    end)
  else
    log.info('structured checks not available for this forge')
  end
end

---@param f forge.Forge
---@param branch string?
function M.ci(f, branch)
  local forge_mod = require('forge')

  local function open_ci_picker(runs)
    local normalized = {}
    for _, entry in ipairs(runs) do
      table.insert(normalized, f:normalize_run(entry))
    end

    local entries = {}
    for _, run in ipairs(normalized) do
      table.insert(entries, {
        display = forge_mod.format_run(run),
        value = run,
        ordinal = run.name .. ' ' .. run.branch,
      })
    end

    picker.pick({
      prompt = ('%s (%s)> '):format(f.labels.ci, branch or 'all'),
      entries = entries,
      actions = {
        {
          name = 'log',
          fn = function(entry)
            if not entry then
              return
            end
            local run = entry.value
            local s = run.status:lower()
            local in_progress = s == 'in_progress'
              or s == 'queued'
              or s == 'pending'
              or s == 'running'
            local url = run.url ~= '' and run.url or nil
            local status_cmd = f.run_status_cmd and f:run_status_cmd(run.id) or nil
            if f.view_cmd then
              require('forge.log').open_summary(f:view_cmd(run.id), {
                forge_name = f.name,
                run_id = run.id,
                url = url,
                title = run.name or run.id,
                in_progress = in_progress,
                status_cmd = status_cmd,
                log_cmd_fn = function(job_id, failed)
                  return f:check_log_cmd(run.id, failed, job_id),
                    {
                      forge_name = f.name,
                      url = url,
                      title = (run.name or run.id) .. ' / ' .. (job_id or ''),
                      steps_cmd = f.steps_cmd and f:steps_cmd(run.id) or nil,
                      job_id = job_id,
                      in_progress = in_progress,
                      status_cmd = status_cmd,
                    }
                end,
              })
            else
              log.info('fetching CI/CD logs...')
              local failed = s == 'failure' or s == 'failed'
              local cmd = f:run_log_cmd(run.id, failed)
              local steps_cmd = f.steps_cmd and f:steps_cmd(run.id) or nil
              require('forge.log').open(cmd, {
                forge_name = f.name,
                url = url,
                title = run.name or run.id,
                steps_cmd = steps_cmd,
                in_progress = in_progress,
                status_cmd = status_cmd,
              })
            end
          end,
        },
        {
          name = 'watch',
          fn = function(entry)
            if not entry then
              return
            end
            if f.watch_cmd then
              local run = entry.value
              require('forge.term').open(f:watch_cmd(run.id), {
                url = run.url ~= '' and run.url or nil,
              })
            end
          end,
        },
        {
          name = 'browse',
          fn = function(entry)
            if entry and entry.value.url ~= '' then
              vim.ui.open(entry.value.url)
            end
          end,
        },
        {
          name = 'refresh',
          fn = function()
            log.info('refreshing CI runs...')
            M.ci(f, branch)
          end,
        },
      },
      picker_name = 'ci',
    })
  end

  if f.list_runs_json_cmd then
    log.info('fetching CI runs...')
    vim.system(f:list_runs_json_cmd(branch), { text = true }, function(result)
      vim.schedule(function()
        local ok, runs = pcall(vim.json.decode, result.stdout or '[]')
        if ok and runs and #runs > 0 then
          open_ci_picker(runs)
        else
          log.info('no CI runs found')
        end
      end)
    end)
  elseif f.list_runs_cmd then
    log.info('structured CI data not available for this forge')
  end
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
function M.pr(state, f)
  local cli_kind = f.kinds.pr
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('pr', state)
  local pr_fields = f:pr_json_fields()
  local show_state = state ~= 'open'

  local function open_pr_list(prs)
    local entries = {}
    for _, pr in ipairs(prs) do
      local num = tostring(pr[pr_fields.number] or '')
      table.insert(entries, {
        display = forge_mod.format_pr(pr, pr_fields, show_state),
        value = num,
        ordinal = (pr[pr_fields.title] or '') .. ' #' .. num,
      })
    end

    picker.pick({
      prompt = ('%s (%s)> '):format(f.labels.pr, state),
      entries = entries,
      actions = {
        {
          name = 'checkout',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).checkout()
            end
          end,
        },
        {
          name = 'diff',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).diff()
            end
          end,
        },
        {
          name = 'worktree',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).worktree()
            end
          end,
        },
        {
          name = 'ci',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).ci()
            end
          end,
        },
        {
          name = 'browse',
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'manage',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).manage()
            end
          end,
        },
        {
          name = 'create',
          fn = function()
            forge_mod.create_pr()
          end,
        },
        {
          name = 'filter',
          fn = function()
            M.pr(next_state, f)
          end,
        },
        {
          name = 'refresh',
          fn = function()
            forge_mod.clear_list(cache_key)
            M.pr(state, f)
          end,
        },
      },
      picker_name = 'pr',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_pr_list(cached)
  else
    log.info(('fetching %s list (%s)...'):format(f.labels.pr, state))
    vim.system(f:list_pr_json_cmd(state), { text = true }, function(result)
      vim.schedule(function()
        local ok, prs = pcall(vim.json.decode, result.stdout or '[]')
        if ok and prs then
          forge_mod.set_list(cache_key, prs)
          open_pr_list(prs)
        else
          log.error('failed to fetch ' .. f.labels.pr)
        end
      end)
    end)
  end
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
function M.issue(state, f)
  local cli_kind = f.kinds.issue
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('issue', state)
  local issue_fields = f:issue_json_fields()
  local num_field = issue_fields.number
  local issue_show_state = state == 'all'

  local function open_issue_list(issues)
    table.sort(issues, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local state_field = issue_fields.state
    local state_map = {}
    local entries = {}
    for _, issue in ipairs(issues) do
      local n = tostring(issue[num_field] or '')
      local s = (issue[state_field] or ''):lower()
      state_map[n] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = forge_mod.format_issue(issue, issue_fields, issue_show_state),
        value = n,
        ordinal = (issue[issue_fields.title] or '') .. ' #' .. n,
      })
    end

    picker.pick({
      prompt = ('%s (%s)> '):format(f.labels.issue, state),
      entries = entries,
      actions = {
        {
          name = 'default',
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'browse',
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'close',
          fn = function(entry)
            if entry then
              issue_toggle_state(f, entry.value, state_map[entry.value] ~= false)
            end
          end,
        },
        {
          name = 'create',
          fn = function()
            forge_mod.create_issue()
          end,
        },
        {
          name = 'filter',
          fn = function()
            M.issue(next_state, f)
          end,
        },
        {
          name = 'refresh',
          fn = function()
            forge_mod.clear_list(cache_key)
            M.issue(state, f)
          end,
        },
      },
      picker_name = 'issue',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_issue_list(cached)
  else
    log.info('fetching issue list (' .. state .. ')...')
    vim.system(f:list_issue_json_cmd(state), { text = true }, function(result)
      vim.schedule(function()
        local ok, issues = pcall(vim.json.decode, result.stdout or '[]')
        if ok and issues then
          forge_mod.set_list(cache_key, issues)
          open_issue_list(issues)
        else
          log.error('failed to fetch issues')
        end
      end)
    end)
  end
end

---@param f forge.Forge
---@param num string
function M.pr_manage(f, num)
  pr_manage_picker(f, num)
end

---@param f forge.Forge
---@param num string
function M.issue_close(f, num)
  run_forge_cmd('issue', num, 'closing', f:close_issue_cmd(num), 'closed', 'close failed')
end

---@param f forge.Forge
---@param num string
function M.issue_reopen(f, num)
  run_forge_cmd('issue', num, 'reopening', f:reopen_issue_cmd(num), 'reopened', 'reopen failed')
end

---@param f forge.Forge
---@param num string
---@return table<string, function>
function M.pr_actions(f, num)
  return pr_action_fns(f, num)
end

---@param state 'all'|'draft'|'prerelease'
---@param f forge.Forge
function M.release(state, f)
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('release', state)
  local rel_fields = f:release_json_fields()
  local next_state = ({ all = 'draft', draft = 'prerelease', prerelease = 'all' })[state]

  local function open_release_list(releases)
    local filtered = releases
    if state == 'draft' and rel_fields.is_draft then
      filtered = vim.tbl_filter(function(r)
        return r[rel_fields.is_draft] == true
      end, releases)
    elseif state == 'prerelease' and rel_fields.is_prerelease then
      filtered = vim.tbl_filter(function(r)
        return r[rel_fields.is_prerelease] == true
      end, releases)
    end

    local entries = {}
    for _, rel in ipairs(filtered) do
      local tag = tostring(rel[rel_fields.tag] or '')
      table.insert(entries, {
        display = forge_mod.format_release(rel, rel_fields),
        value = { tag = tag, rel = rel },
        ordinal = tag .. ' ' .. (rel[rel_fields.title] or ''),
      })
    end

    picker.pick({
      prompt = ('Releases (%s)> '):format(state),
      entries = entries,
      actions = {
        {
          name = 'browse',
          fn = function(entry)
            if entry then
              f:browse_release(entry.value.tag)
            end
          end,
        },
        {
          name = 'yank',
          fn = function(entry)
            if entry then
              local base = forge_mod.remote_web_url()
              local tag = entry.value.tag
              local url = base .. '/releases/tag/' .. tag
              vim.fn.setreg('+', url)
              log.info('copied release URL')
            end
          end,
        },
        {
          name = 'delete',
          fn = function(entry)
            if not entry then
              return
            end
            local tag = entry.value.tag
            vim.ui.select({ 'Yes', 'No' }, {
              prompt = 'Delete release ' .. tag .. '? ',
            }, function(choice)
              if choice == 'Yes' then
                run_forge_cmd(
                  'release',
                  tag,
                  'deleting',
                  f:delete_release_cmd(tag),
                  'deleted',
                  'delete failed'
                )
                forge_mod.clear_list(cache_key)
              end
            end)
          end,
        },
        {
          name = 'filter',
          fn = function()
            M.release(next_state, f)
          end,
        },
        {
          name = 'refresh',
          fn = function()
            forge_mod.clear_list(cache_key)
            M.release(state, f)
          end,
        },
      },
      picker_name = 'release',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_release_list(cached)
  else
    log.info('fetching releases...')
    vim.system(f:list_releases_json_cmd(), { text = true }, function(result)
      vim.schedule(function()
        local ok, releases = pcall(vim.json.decode, result.stdout or '[]')
        if ok and releases and #releases > 0 then
          forge_mod.set_list(cache_key, releases)
          open_release_list(releases)
        else
          log.info('no releases found')
        end
      end)
    end)
  end
end

function M.git()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    log.warn('not a git repository')
    return
  end

  local forge_mod = require('forge')
  local f = forge_mod.detect()

  local loc = forge_mod.file_loc()
  local buf_name = vim.api.nvim_buf_get_name(0)
  local has_file = buf_name ~= ''
    and not buf_name:match('^fugitive://')
    and not buf_name:match('^term://')
    and not buf_name:match('^diffs://')
  local branch = vim.trim(vim.fn.system('git branch --show-current'))

  local items = {}
  local action_map = {}

  local function add(label, action)
    table.insert(items, {
      display = { { label } },
      value = label,
    })
    action_map[label] = action
  end

  if f then
    local pr_label = f.labels.pr_full
    local ci_label = f.labels.ci

    add(pr_label, function()
      M.pr('open', f)
    end)

    add('Issues', function()
      M.issue('all', f)
    end)

    add(ci_label, function()
      M.ci(f, branch ~= '' and branch or nil)
    end)

    add('Releases', function()
      M.release('all', f)
    end)

    if has_file then
      add('Open File', function()
        if branch == '' then
          log.warn('detached HEAD')
          return
        end
        f:browse(loc, branch)
      end)
    end
  end

  local prompt = f and (f.name:sub(1, 1):upper() .. f.name:sub(2)) .. '> ' or 'Git> '

  picker.pick({
    prompt = prompt,
    entries = items,
    actions = {
      {
        name = 'default',
        fn = function(entry)
          if entry and action_map[entry.value] then
            action_map[entry.value]()
          end
        end,
      },
    },
    picker_name = '_menu',
  })
end

return M
