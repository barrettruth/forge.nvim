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
local function run_forge_cmd(kind, num, label, cmd, success_msg, fail_msg, on_success, on_failure)
  log.info(label .. ' ' .. kind .. ' #' .. num .. '...')
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log.info(('%s %s #%s'):format(success_msg, kind, num))
        if on_success then
          on_success()
        end
      else
        log.error(cmd_error(result, fail_msg))
        if on_failure then
          on_failure()
        end
      end
    end)
  end)
end

local next_ci_filter = {
  all = 'fail',
  fail = 'pass',
  pass = 'pending',
  pending = 'all',
}

---@param text string
---@return forge.PickerEntry
local function placeholder_entry(text)
  return {
    display = { { text, 'ForgeDim' } },
    value = nil,
    ordinal = text,
    placeholder = true,
  }
end

---@param entries forge.PickerEntry[]
---@param text string
---@return forge.PickerEntry[]
local function with_placeholder(entries, text)
  if #entries > 0 then
    return entries
  end
  return { placeholder_entry(text) }
end

local field_sep = string.char(31)
local record_sep = string.char(30)

local function run_git_cmd(label, cmd, success_msg, fail_msg, on_success, on_failure)
  log.info(label .. '...')
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        log.info(success_msg)
        if on_success then
          on_success()
        end
      else
        log.error(cmd_error(result, fail_msg))
        if on_failure then
          on_failure()
        end
      end
    end)
  end)
end

local function change_directory(path)
  require('forge').clear_cache()
  vim.cmd('cd ' .. vim.fn.fnameescape(path))
  log.info('changed directory to ' .. path)
end

local function split_records(text)
  return vim.tbl_map(function(record)
    return vim.split(record, field_sep, { plain = true })
  end, vim.split(text or '', record_sep, { plain = true, trimempty = true }))
end

local function pad_or_truncate(s, width)
  if width <= 0 then
    return ''
  end
  if #s > width then
    return s:sub(1, width - 1) .. '…'
  end
  return s .. string.rep(' ', width - #s)
end

local function truncate(s, width)
  if width <= 0 or #s <= width then
    return s
  end
  return s:sub(1, width - 1) .. '…'
end

local function branch_layout(branches)
  local branch_limit = 25
  local subject_limit = 45
  local ok, forge = pcall(require, 'forge')
  if ok and forge.config then
    local widths = forge.config().display.widths
    branch_limit = widths.branch or branch_limit
    subject_limit = widths.title or subject_limit
  end

  local name_width = 1
  local upstream_width = 0
  for _, item in ipairs(branches) do
    name_width = math.max(name_width, #item.name)
    if item.upstream ~= '' then
      upstream_width = math.max(upstream_width, #item.upstream + 2)
    end
  end

  return {
    name = math.min(name_width, branch_limit),
    upstream = math.min(upstream_width, branch_limit),
    subject = subject_limit,
  }
end

local function branch_display(item, layout)
  local marker = '  '
  local marker_hl = 'ForgeDim'
  local name_hl = nil
  if item.current then
    marker = '* '
    marker_hl = 'ForgePass'
    name_hl = 'ForgeBranchCurrent'
  elseif item.worktree_path then
    marker = '+ '
    marker_hl = 'ForgeBranch'
    name_hl = 'ForgeBranch'
  end

  local display = {
    { marker, marker_hl },
    { pad_or_truncate(item.name, layout.name), name_hl },
  }
  if layout.upstream > 0 then
    local upstream = item.upstream ~= '' and ('[' .. item.upstream .. ']') or ''
    display[#display + 1] = {
      ' ' .. pad_or_truncate(upstream, layout.upstream),
      upstream ~= '' and 'Directory' or nil,
    }
  end
  if item.subject ~= '' then
    display[#display + 1] = { ' ' .. truncate(item.subject, layout.subject), 'ForgeDim' }
  end
  return display
end

local function commit_display(item)
  local display = {
    { item.short_sha, 'Identifier' },
  }
  if item.subject ~= '' then
    display[#display + 1] = { ' ' .. item.subject }
  end
  local meta = {}
  if item.author ~= '' then
    meta[#meta + 1] = item.author
  end
  if item.relative ~= '' then
    meta[#meta + 1] = item.relative
  end
  if #meta > 0 then
    display[#display + 1] = { ' · ' .. table.concat(meta, ' · '), 'ForgeDim' }
  end
  return display
end

local function worktree_label(item)
  if item.branch ~= '' then
    return item.branch
  end
  if item.detached then
    return 'detached ' .. item.short_head
  end
  if item.bare then
    return 'bare'
  end
  return item.short_head
end

local function worktree_display(item)
  local display = {
    { item.current and '* ' or '  ', item.current and 'Identifier' or 'ForgeDim' },
    { worktree_label(item), item.branch ~= '' and 'ForgeBranch' or nil },
  }
  local meta = {}
  if item.current then
    meta[#meta + 1] = 'current'
  end
  if item.detached then
    meta[#meta + 1] = 'detached'
  end
  if item.bare then
    meta[#meta + 1] = 'bare'
  end
  if item.short_head ~= '' and not item.detached then
    meta[#meta + 1] = item.short_head
  end
  if #meta > 0 then
    display[#display + 1] = { ' · ' .. table.concat(meta, ' · '), 'ForgeDim' }
  end
  display[#display + 1] = { ' ' .. item.path, 'ForgeDim' }
  return display
end

local function parse_branches(output)
  local branches = {}
  for _, line in ipairs(vim.split(output or '', '\n', { plain = true, trimempty = true })) do
    local fields = vim.split(line, '\t', { plain = true })
    if #fields >= 5 then
      branches[#branches + 1] = {
        current = vim.trim(fields[1]) == '*',
        name = fields[2],
        upstream = fields[3],
        sha = fields[4],
        subject = table.concat(vim.list_slice(fields, 5), '\t'),
      }
    end
  end
  return branches
end

local function parse_commits(output)
  local commits = {}
  for _, fields in ipairs(split_records(output)) do
    if #fields >= 5 then
      commits[#commits + 1] = {
        sha = fields[1],
        short_sha = fields[2],
        subject = fields[3],
        author = fields[4],
        relative = fields[5],
      }
    end
  end
  return commits
end

local function parse_worktrees(output, current_root)
  local worktrees = {}
  local item
  for _, line in ipairs(vim.split(output or '', '\n', { plain = true })) do
    if line == '' then
      if item then
        item.current = item.path == current_root
        item.short_head = item.head:sub(1, 7)
        worktrees[#worktrees + 1] = item
        item = nil
      end
    else
      local key, value = line:match('^(%S+)%s*(.*)$')
      if key == 'worktree' then
        item = {
          path = value,
          head = '',
          branch = '',
          detached = false,
          bare = false,
        }
      elseif item and key == 'HEAD' then
        item.head = value
      elseif item and key == 'branch' then
        item.branch = value:gsub('^refs/heads/', '')
      elseif item and key == 'detached' then
        item.detached = true
      elseif item and key == 'bare' then
        item.bare = true
      end
    end
  end
  if item then
    item.current = item.path == current_root
    item.short_head = item.head:sub(1, 7)
    worktrees[#worktrees + 1] = item
  end
  return worktrees
end

local function annotate_branches_with_worktrees(ctx, branches, on_done)
  vim.system({ 'git', 'worktree', 'list', '--porcelain' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(branches)
        return
      end
      local worktrees = parse_worktrees(result.stdout or '', ctx.root)
      local worktree_paths = {}
      for _, item in ipairs(worktrees) do
        if item.branch ~= '' and not item.current then
          worktree_paths[item.branch] = item.path
        end
      end
      for _, item in ipairs(branches) do
        item.worktree_path = worktree_paths[item.name]
      end
      on_done(branches)
    end)
  end)
end

---@param f forge.Forge
---@param num string
---@param is_open boolean
local function issue_toggle_state(f, num, is_open, on_success)
  if is_open then
    run_forge_cmd(
      'issue',
      num,
      'closing',
      f:close_issue_cmd(num),
      'closed',
      'close failed',
      on_success,
      on_success
    )
  else
    run_forge_cmd(
      'issue',
      num,
      'reopening',
      f:reopen_issue_cmd(num),
      'reopened',
      'reopen failed',
      on_success,
      on_success
    )
  end
end

---@param f forge.Forge
---@param num string
---@param is_open boolean
local function pr_toggle_state(f, num, is_open, on_success)
  local kind = f.labels.pr_one
  if is_open then
    run_forge_cmd(
      kind,
      num,
      'closing',
      f:close_cmd(num),
      'closed',
      'close failed',
      on_success,
      on_success
    )
  else
    run_forge_cmd(
      kind,
      num,
      'reopening',
      f:reopen_cmd(num),
      'reopened',
      'reopen failed',
      on_success,
      on_success
    )
  end
end

---@param f forge.Forge
---@param num string
---@return table<string, function>
local function pr_action_fns(f, num)
  local kind = f.labels.pr_one
  local function review_pr()
    local review = require('forge.review')
    local repo_root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))

    log.info(('reviewing %s #%s...'):format(kind, num))
    vim.system(f:checkout_cmd(num), { text = true }, function(co_result)
      if co_result.code ~= 0 then
        vim.schedule(function()
          log.debug('checkout skipped, proceeding with review')
        end)
      end

      vim.system(f:pr_base_cmd(num), { text = true }, function(base_result)
        vim.schedule(function()
          local base = vim.trim(base_result.stdout or '')
          if base == '' or base_result.code ~= 0 then
            base = 'main'
          end
          local range = 'origin/' .. base
          local head = vim.trim(vim.fn.system('git branch --show-current'))
          review.start_session({
            subject = {
              kind = 'pr',
              id = num,
              label = ('%s #%s'):format(kind, num),
              base_ref = range,
              head_ref = head,
            },
            mode = 'patch',
            files = {},
            current_file = nil,
            materialization = co_result.code == 0 and 'checkout' or 'current',
            repo_root = repo_root,
          })
          review.open_index()
          log.debug(('review ready for %s #%s against %s'):format(kind, num, base))
        end)
      end)
    end)
  end
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
    review = review_pr,
    diff = review_pr,
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
    edit = function()
      require('forge').edit_pr(num)
    end,
  }
end

---@param f forge.Forge
---@param num string
local function pr_manage_picker(f, num, parent_refresh)
  local forge_mod = require('forge')
  local kind = f.labels.pr_one
  log.info('loading more for ' .. kind .. ' #' .. num .. '...')

  local info = forge_mod.repo_info(f)
  local can_write = info.permission == 'ADMIN'
    or info.permission == 'MAINTAIN'
    or info.permission == 'WRITE'
  local pr_state = f:pr_state(num)
  local is_open = pr_state.state == 'OPEN' or pr_state.state == 'OPENED'

  local entries = {}
  local action_map = {}
  local function reopen_self()
    pr_manage_picker(f, num, parent_refresh)
  end

  local function add(label, fn)
    table.insert(entries, {
      display = { { label } },
      value = label,
    })
    action_map[label] = fn
  end

  add('Edit', function()
    require('forge').edit_pr(num)
  end)

  if can_write and is_open then
    add('Approve', function()
      run_forge_cmd(
        kind,
        num,
        'approving',
        f:approve_cmd(num),
        'approved',
        'approve failed',
        reopen_self,
        reopen_self
      )
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
          'merge failed',
          parent_refresh or reopen_self,
          reopen_self
        )
      end)
    end
  end

  if is_open then
    add('Close', function()
      run_forge_cmd(
        kind,
        num,
        'closing',
        f:close_cmd(num),
        'closed',
        'close failed',
        parent_refresh or reopen_self,
        reopen_self
      )
    end)
  else
    add('Reopen', function()
      run_forge_cmd(
        kind,
        num,
        'reopening',
        f:reopen_cmd(num),
        'reopened',
        'reopen failed',
        parent_refresh or reopen_self,
        reopen_self
      )
    end)
  end

  local draft_cmd = f:draft_toggle_cmd(num, pr_state.is_draft)
  if draft_cmd then
    local draft_label = pr_state.is_draft and 'Mark as ready' or 'Mark as draft'
    local draft_done = pr_state.is_draft and 'marked as ready' or 'marked as draft'
    add(draft_label, function()
      run_forge_cmd(
        kind,
        num,
        'toggling draft',
        draft_cmd,
        draft_done,
        'draft toggle failed',
        reopen_self,
        reopen_self
      )
    end)
  end

  picker.pick({
    prompt = ('%s #%s More> '):format(kind, num),
    entries = entries,
    actions = {
      {
        name = 'default',
        label = 'run',
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
    local count = #filtered
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
    local filter_label = labels[filter] or filter
    local empty_text = filter == 'all' and ('No checks for #%s'):format(num)
      or ('No %s checks for #%s'):format(filter_label, num)
    entries = with_placeholder(entries, empty_text)

    picker.pick({
      prompt = ('Checks (#%s, %s · %d)> '):format(num, filter_label, count),
      entries = entries,
      actions = {
        {
          name = 'log',
          label = 'log',
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
          label = 'web',
          close = false,
          fn = function(entry)
            if entry and entry.value.link then
              vim.ui.open(entry.value.link)
            end
          end,
        },
        {
          name = 'filter',
          label = 'filter',
          fn = function()
            M.checks(f, num, next_ci_filter[filter] or 'all', checks)
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
---@param filter string?
function M.ci(f, branch, filter)
  filter = filter or 'all'
  local forge_mod = require('forge')

  local function open_ci_picker(runs)
    local normalized = {}
    for _, entry in ipairs(runs) do
      table.insert(normalized, f:normalize_run(entry))
    end
    local filtered = forge_mod.filter_runs(normalized, filter)
    local count = #filtered

    local labels = {
      all = 'all',
      fail = 'failed',
      pass = 'passed',
      pending = 'running',
    }

    local entries = {}
    for _, run in ipairs(filtered) do
      table.insert(entries, {
        display = forge_mod.format_run(run),
        value = run,
        ordinal = run.name .. ' ' .. run.branch,
      })
    end
    local filter_label = labels[filter] or filter
    local empty_text
    if branch and filter ~= 'all' then
      empty_text = ('No %s %s runs for %s'):format(filter_label, f.labels.ci, branch)
    elseif branch then
      empty_text = ('No %s runs for %s'):format(f.labels.ci, branch)
    elseif filter ~= 'all' then
      empty_text = ('No %s %s runs'):format(filter_label, f.labels.ci)
    else
      empty_text = ('No %s runs'):format(f.labels.ci)
    end
    entries = with_placeholder(entries, empty_text)

    picker.pick({
      prompt = ('%s (%s, %s · %d)> '):format(f.labels.ci, branch or 'all', filter_label, count),
      entries = entries,
      actions = {
        {
          name = 'log',
          label = 'log',
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
            if f.summary_json_cmd then
              require('forge.log').open_summary(f:summary_json_cmd(run.id), {
                forge_name = f.name,
                run_id = run.id,
                url = url,
                title = run.name or run.id,
                in_progress = in_progress,
                status_cmd = status_cmd,
                json = true,
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
            elseif f.view_cmd then
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
          label = 'watch',
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
          label = 'web',
          close = false,
          fn = function(entry)
            if entry and entry.value.url ~= '' then
              vim.ui.open(entry.value.url)
            end
          end,
        },
        {
          name = 'filter',
          label = 'filter',
          fn = function()
            M.ci(f, branch, next_ci_filter[filter] or 'all')
          end,
        },
        {
          name = 'failed',
          fn = function()
            M.ci(f, branch, 'fail')
          end,
        },
        {
          name = 'passed',
          fn = function()
            M.ci(f, branch, 'pass')
          end,
        },
        {
          name = 'running',
          fn = function()
            M.ci(f, branch, 'pending')
          end,
        },
        {
          name = 'all',
          fn = function()
            M.ci(f, branch, 'all')
          end,
        },
        {
          name = 'refresh',
          fn = function()
            log.info('refreshing CI runs...')
            M.ci(f, branch, filter)
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
        if ok and runs then
          open_ci_picker(runs)
        else
          log.error('failed to fetch CI runs')
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
  local pr_fields = f.pr_fields
  local show_state = state ~= 'open'

  local function open_pr_list(prs)
    local state_field = pr_fields.state
    local state_map = {}
    local entries = {}
    local function reopen_list()
      forge_mod.clear_list(cache_key)
      M.pr(state, f)
    end
    for _, pr in ipairs(prs) do
      local num = tostring(pr[pr_fields.number] or '')
      local s = (pr[state_field] or ''):lower()
      state_map[num] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = forge_mod.format_pr(pr, pr_fields, show_state),
        value = num,
        ordinal = (pr[pr_fields.title] or '') .. ' #' .. num,
      })
    end
    local count = #entries
    local empty_text = state == 'all' and ('No %s'):format(f.labels.pr)
      or ('No %s %s'):format(state, f.labels.pr)
    entries = with_placeholder(entries, empty_text)

    picker.pick({
      prompt = ('%s (%s · %d)> '):format(f.labels.pr, state, count),
      entries = entries,
      actions = {
        {
          name = 'default',
          label = 'more',
          fn = function(entry)
            if entry then
              pr_manage_picker(f, entry.value, reopen_list)
            end
          end,
        },
        {
          name = 'checkout',
          label = 'checkout',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).checkout()
            end
          end,
        },
        {
          name = 'review',
          label = 'review',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).review()
            end
          end,
        },
        {
          name = 'worktree',
          close = false,
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).worktree()
            end
          end,
        },
        {
          name = 'ci',
          label = 'checks',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).ci()
            end
          end,
        },
        {
          name = 'browse',
          label = 'web',
          close = false,
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'manage',
          label = 'more',
          fn = function(entry)
            if entry then
              pr_manage_picker(f, entry.value, reopen_list)
            end
          end,
        },
        {
          name = 'edit',
          fn = function(entry)
            if entry then
              pr_action_fns(f, entry.value).edit()
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
          name = 'close',
          fn = function(entry)
            if entry then
              pr_toggle_state(f, entry.value, state_map[entry.value] ~= false, reopen_list)
            end
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
  local issue_fields = f.issue_fields
  local num_field = issue_fields.number
  local issue_show_state = state == 'all'

  local function open_issue_list(issues)
    table.sort(issues, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local state_field = issue_fields.state
    local state_map = {}
    local entries = {}
    local function reopen_list()
      forge_mod.clear_list(cache_key)
      M.issue(state, f)
    end
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
    local count = #entries
    local empty_text = state == 'all' and ('No %s'):format(f.labels.issue)
      or ('No %s %s'):format(state, f.labels.issue)
    entries = with_placeholder(entries, empty_text)

    picker.pick({
      prompt = ('%s (%s · %d)> '):format(f.labels.issue, state, count),
      entries = entries,
      actions = {
        {
          name = 'default',
          label = 'open',
          close = false,
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'browse',
          close = false,
          fn = function(entry)
            if entry then
              f:view_web(cli_kind, entry.value)
            end
          end,
        },
        {
          name = 'close',
          label = state == 'open' and 'close' or state == 'closed' and 'reopen' or 'toggle',
          fn = function(entry)
            if entry then
              issue_toggle_state(f, entry.value, state_map[entry.value] ~= false, reopen_list)
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
function M.pr_close(f, num)
  local kind = f.labels.pr_one
  run_forge_cmd(kind, num, 'closing', f:close_cmd(num), 'closed', 'close failed')
end

---@param f forge.Forge
---@param num string
function M.pr_reopen(f, num)
  local kind = f.labels.pr_one
  run_forge_cmd(kind, num, 'reopening', f:reopen_cmd(num), 'reopened', 'reopen failed')
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
  local rel_fields = f.release_fields
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
    local count = #entries
    local empty_text = state == 'all' and 'No releases'
      or state == 'draft' and 'No draft releases'
      or 'No prerelease releases'
    entries = with_placeholder(entries, empty_text)

    picker.pick({
      prompt = ('Releases (%s · %d)> '):format(state, count),
      entries = entries,
      actions = {
        {
          name = 'browse',
          label = 'open',
          close = false,
          fn = function(entry)
            if entry then
              f:browse_release(entry.value.tag)
            end
          end,
        },
        {
          name = 'yank',
          label = 'copy',
          close = false,
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
                  'delete failed',
                  function()
                    forge_mod.clear_list(cache_key)
                    M.release(state, f)
                  end,
                  function()
                    M.release(state, f)
                  end
                )
              else
                M.release(state, f)
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
        if ok and releases then
          forge_mod.set_list(cache_key, releases)
          open_release_list(releases)
        else
          log.error('failed to fetch releases')
        end
      end)
    end)
  end
end

---@param ctx { root: string, branch: string, forge: forge.Forge? }
function M.branches(ctx)
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('branch', 'local-refs-v2')

  local function open_branch_list(branches)
    local layout = branch_layout(branches)
    local entries = {}
    for _, item in ipairs(branches) do
      entries[#entries + 1] = {
        display = branch_display(item, layout),
        value = item,
        ordinal = table.concat({
          item.name,
          item.upstream,
          item.subject,
          item.worktree_path or '',
        }, ' '),
      }
    end
    local count = #entries
    entries = with_placeholder(entries, 'No local branches in repo')

    local actions = {
      {
        name = 'default',
        label = 'switch',
        fn = function(entry)
          if not entry then
            return
          end
          local item = entry.value
          if item.current then
            log.info('already on branch ' .. item.name)
            return
          end
          if item.worktree_path then
            change_directory(item.worktree_path)
            return
          end
          run_git_cmd(
            'switching to branch ' .. item.name,
            { 'git', 'switch', item.name },
            'switched to branch ' .. item.name,
            'switch failed'
          )
        end,
      },
      {
        name = 'review',
        label = 'review',
        fn = function(entry)
          if entry then
            require('forge.review').start_branch(ctx, entry.value.name)
          end
        end,
      },
      {
        name = 'yank',
        label = 'copy',
        close = false,
        fn = function(entry)
          if not entry then
            return
          end
          vim.fn.setreg('+', entry.value.name)
          log.info('copied branch name')
        end,
      },
      {
        name = 'refresh',
        fn = function()
          forge_mod.clear_list(cache_key)
          M.branches(ctx)
        end,
      },
    }

    if ctx.forge then
      table.insert(actions, 2, {
        name = 'browse',
        label = 'web',
        close = false,
        fn = function(entry)
          if entry then
            ctx.forge:browse_branch(entry.value.name)
          end
        end,
      })
    end

    picker.pick({
      prompt = ('Branches (local refs · switch/review · %d)> '):format(count),
      entries = entries,
      actions = actions,
      picker_name = 'branch',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_branch_list(cached)
    return
  end

  log.info('fetching local branches...')
  vim.system({
    'git',
    'for-each-ref',
    '--format=%(HEAD)\t%(refname:short)\t%(upstream:short)\t%(objectname:short)\t%(subject)',
    'refs/heads',
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        log.error(cmd_error(result, 'failed to fetch branches'))
        return
      end
      local branches = parse_branches(result.stdout or '')
      annotate_branches_with_worktrees(ctx, branches, function(items)
        forge_mod.set_list(cache_key, items)
        open_branch_list(items)
      end)
    end)
  end)
end

---@param ctx { forge: forge.Forge?, branch: string }
---@param branch string
function M.commits(ctx, branch)
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('commit', branch)

  local function open_commit_list(commits)
    local entries = {}
    for _, item in ipairs(commits) do
      entries[#entries + 1] = {
        display = commit_display(item),
        value = item,
        ordinal = item.sha .. ' ' .. item.subject .. ' ' .. item.author,
      }
    end
    local count = #entries
    entries = with_placeholder(entries, 'No commits in ' .. branch .. ' history')

    local actions = {
      {
        name = 'default',
        label = 'show',
        fn = function(entry)
          if not entry then
            return
          end
          require('forge.term').open({
            'git',
            'show',
            '--stat',
            '--patch',
            '--decorate=short',
            entry.value.sha,
          })
        end,
      },
      {
        name = 'review',
        label = 'review',
        fn = function(entry)
          if entry then
            require('forge.review').start_commit(ctx, entry.value.sha)
          end
        end,
      },
      {
        name = 'yank',
        label = 'copy',
        close = false,
        fn = function(entry)
          if not entry then
            return
          end
          vim.fn.setreg('+', entry.value.sha)
          log.info('copied commit SHA')
        end,
      },
      {
        name = 'refresh',
        fn = function()
          forge_mod.clear_list(cache_key)
          M.commits(ctx, branch)
        end,
      },
    }

    if ctx.forge then
      table.insert(actions, 2, {
        name = 'browse',
        label = 'web',
        close = false,
        fn = function(entry)
          if entry then
            ctx.forge:browse_commit(entry.value.sha)
          end
        end,
      })
    end

    picker.pick({
      prompt = ('Commits (%s history · git show/review · %d)> '):format(branch, count),
      entries = entries,
      actions = actions,
      picker_name = 'commit',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_commit_list(cached)
    return
  end

  log.info('fetching commits for ' .. branch .. '...')
  vim.system({
    'git',
    'log',
    '--max-count=100',
    '--format=%H%x1f%h%x1f%s%x1f%an%x1f%cr%x1e',
    branch,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        log.error(cmd_error(result, 'failed to fetch commits'))
        return
      end
      local commits = parse_commits(result.stdout or '')
      forge_mod.set_list(cache_key, commits)
      open_commit_list(commits)
    end)
  end)
end

---@param ctx { root: string }
function M.worktrees(ctx)
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('worktree', 'list')

  local function open_worktree_list(worktrees)
    local entries = {}
    for _, item in ipairs(worktrees) do
      entries[#entries + 1] = {
        display = worktree_display(item),
        value = item,
        ordinal = item.path .. ' ' .. worktree_label(item),
      }
    end
    local count = #entries
    entries = with_placeholder(entries, 'No linked worktrees')

    picker.pick({
      prompt = ('Worktrees (repo worktrees · switch cwd · %d)> '):format(count),
      entries = entries,
      actions = {
        {
          name = 'default',
          label = 'switch cwd',
          fn = function(entry)
            if not entry then
              return
            end
            local item = entry.value
            if item.current then
              log.info('already in worktree ' .. item.path)
              return
            end
            change_directory(item.path)
          end,
        },
        {
          name = 'yank',
          label = 'copy',
          close = false,
          fn = function(entry)
            if not entry then
              return
            end
            vim.fn.setreg('+', entry.value.path)
            log.info('copied worktree path')
          end,
        },
        {
          name = 'refresh',
          fn = function()
            forge_mod.clear_list(cache_key)
            M.worktrees(ctx)
          end,
        },
      },
      picker_name = 'worktree',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  if cached then
    open_worktree_list(cached)
    return
  end

  log.info('fetching worktrees...')
  vim.system({ 'git', 'worktree', 'list', '--porcelain' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        log.error(cmd_error(result, 'failed to fetch worktrees'))
        return
      end
      local worktrees = parse_worktrees(result.stdout or '', ctx.root)
      forge_mod.set_list(cache_key, worktrees)
      open_worktree_list(worktrees)
    end)
  end)
end

function M.git()
  require('forge').open()
end

return M
