local M = {}

local format = require('forge.format')
local layout = require('forge.layout')
local log = require('forge.logger')
local picker = require('forge.picker')
local picker_session = require('forge.picker.session')

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

---@param next_limit integer
---@return forge.PickerEntry
local function load_more_entry(next_limit)
  return {
    display = { { 'Load more...', 'ForgeDim' } },
    value = nil,
    ordinal = 'Load more',
    load_more = true,
    next_limit = next_limit,
    force_close = true,
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

local list_states = { 'open', 'closed', 'all' }

local function clear_state_caches(forge_mod, kind)
  for _, state in ipairs(list_states) do
    local key = forge_mod.list_key(kind, state)
    forge_mod.clear_list(key)
    picker_session.invalidate(key)
  end
end

local function clear_list_cache(forge_mod, key)
  forge_mod.clear_list(key)
  picker_session.invalidate(key)
end

local function maybe_prefetch_list(forge_mod, kind, state, label, cmd)
  local key = forge_mod.list_key(kind, state)
  local started = picker_session.prefetch_json({
    key = key,
    cmd = cmd,
    skip_if = function()
      return forge_mod.get_list(key) ~= nil
    end,
    on_success = function(data)
      forge_mod.set_list(key, data)
    end,
  })
  if started then
    log.debug(('prefetching %s list (%s)...'):format(label, state))
  end
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

local function home_path(path)
  return vim.fn.fnamemodify(path, ':~')
end

local function elastic_width(preferred, values, min, opts)
  return layout.elastic(preferred, layout.measure(values, opts), min)
end

local function display_path(path, width)
  local rendered = home_path(path)
  if layout.display_width(rendered) > width then
    rendered = vim.fn.pathshorten(rendered)
  end
  return rendered
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

  local names = {}
  local upstreams = {}
  local subjects = {}
  for _, item in ipairs(branches) do
    names[#names + 1] = item.name
    upstreams[#upstreams + 1] = item.upstream ~= '' and ('[' .. item.upstream .. ']') or ''
    subjects[#subjects + 1] = item.subject or ''
  end
  local name_pref, name_max = elastic_width(branch_limit, names, 6)
  local upstream_pref, upstream_max =
    elastic_width(branch_limit, upstreams, 8, { max_quantile = 1 })
  local subject_pref, subject_max = elastic_width(subject_limit, subjects, 12)
  return layout.plan({
    width = layout.picker_width(),
    columns = {
      { key = 'marker', fixed = 2 },
      {
        key = 'name',
        gap = '',
        min = 6,
        preferred = name_pref,
        max = name_max,
        shrink = 3,
        grow = 1,
        overflow = 'tail',
      },
      {
        key = 'upstream',
        gap = ' ',
        min = 8,
        preferred = upstream_pref,
        max = upstream_max,
        optional = true,
        drop = 2,
        shrink = 2,
        grow = 2,
        overflow = 'tail',
        hide_if_empty = true,
      },
      {
        key = 'subject',
        gap = ' ',
        min = 12,
        preferred = subject_pref,
        max = subject_max,
        optional = true,
        drop = 1,
        shrink = 1,
        grow = 3,
        overflow = 'tail',
        pack_on = 'compact',
        hide_if_empty = true,
      },
    },
  })
end

local function commit_layout(commits)
  local title_limit = 45
  local author_limit = 15
  local ok, forge = pcall(require, 'forge')
  if ok and forge.config then
    local widths = forge.config().display.widths
    title_limit = widths.title or title_limit
    author_limit = widths.author or author_limit
  end

  local shas = {}
  local subjects = {}
  local authors = {}
  local ages = {}
  for _, item in ipairs(commits) do
    shas[#shas + 1] = item.short_sha
    subjects[#subjects + 1] = item.subject or ''
    authors[#authors + 1] = item.author or ''
    ages[#ages + 1] = item.relative or ''
  end
  local subject_pref, subject_max = elastic_width(title_limit, subjects, 12)
  local author_pref, author_max = elastic_width(author_limit, authors, 8, { max_quantile = 1 })
  return layout.plan({
    width = layout.picker_width(),
    columns = {
      { key = 'sha', fixed = math.max(7, layout.max_width(shas)) },
      {
        key = 'subject',
        gap = ' ',
        min = 12,
        preferred = subject_pref,
        max = subject_max,
        shrink = 2,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
      },
      {
        key = 'author',
        gap = ' ',
        min = 8,
        preferred = author_pref,
        max = author_max,
        optional = true,
        drop = 1,
        shrink = 1,
        grow = 2,
        overflow = 'tail',
        hide_if_empty = true,
      },
      {
        key = 'age',
        gap = ' ',
        fixed = layout.max_width(ages),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
    },
  })
end

local function branch_display(item, plan)
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
  local upstream = item.upstream ~= '' and ('[' .. item.upstream .. ']') or ''
  return layout.render(plan, {
    marker = { marker, marker_hl },
    name = { item.name, name_hl },
    upstream = { upstream, upstream ~= '' and 'Directory' or nil },
    subject = { item.subject, 'ForgeDim' },
  })
end

local function commit_display(item, plan)
  return layout.render(plan, {
    sha = { item.short_sha, 'ForgeCommitHash' },
    subject = item.subject,
    author = { item.author, 'ForgeCommitAuthor' },
    age = { item.relative, 'ForgeCommitTime' },
  })
end

local function worktree_label(item)
  if item.branch ~= '' then
    return item.branch
  end
  if item.detached then
    return 'detached'
  end
  if item.bare then
    return 'bare'
  end
  return ''
end

local function worktree_layout(worktrees)
  local path_limit = 35
  local label_limit = 25
  local ok, forge = pcall(require, 'forge')
  if ok and forge.config then
    local widths = forge.config().display.widths
    path_limit = widths.name or path_limit
    label_limit = widths.branch or label_limit
  end

  local paths = {}
  local labels = {}
  local shas = {}
  for _, item in ipairs(worktrees) do
    paths[#paths + 1] = vim.fn.pathshorten(home_path(item.path))
    labels[#labels + 1] = worktree_label(item)
    shas[#shas + 1] = item.short_head
  end
  local path_opts = #paths <= 3 and { typical_quantile = 1, max_quantile = 1 }
    or { typical_quantile = 0.7, max_quantile = 0.85 }
  local path_pref, path_max = elastic_width(path_limit, paths, 12, path_opts)
  local label_pref, label_max = elastic_width(label_limit, labels, 8)
  return layout.plan({
    width = layout.picker_width(),
    columns = {
      { key = 'marker', fixed = 2 },
      {
        key = 'path',
        gap = '',
        min = 12,
        preferred = path_pref,
        max = path_max,
        shrink = 3,
        grow = 1,
        overflow = 'head',
        pack_on = 'compact',
      },
      {
        key = 'label',
        gap = ' ',
        min = 8,
        preferred = label_pref,
        max = label_max,
        optional = true,
        drop = 2,
        shrink = 2,
        grow = 2,
        overflow = 'tail',
        pack_on = 'compact',
        hide_if_empty = true,
      },
      {
        key = 'sha',
        gap = ' ',
        fixed = layout.max_width(shas),
        optional = true,
        drop = 1,
        hide_if_empty = true,
      },
    },
  })
end

local function worktree_display(item, plan)
  local label = worktree_label(item)
  return layout.render(plan, {
    marker = { item.current and '* ' or '  ', item.current and 'ForgePass' or 'ForgeDim' },
    path = {
      render = function(width)
        return { display_path(item.path, width), 'Directory' }
      end,
    },
    label = {
      label,
      item.current and item.branch ~= '' and 'ForgeBranchCurrent'
        or item.branch ~= '' and 'ForgeBranch'
        or 'ForgeDim',
    },
    sha = { item.short_head, 'ForgeCommitHash' },
  })
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
        relative = format.relative_time_from_unix(fields[5]),
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
  local current_checks = cached_checks
  local request_key = forge_mod.list_key('check', num)
  local labels = {
    all = 'all',
    fail = 'failed',
    pass = 'passed',
    pending = 'running',
  }
  local prompt_labels = {
    fail = 'Failed',
    pass = 'Passed',
    pending = 'Running',
  }

  local function checks_prompt(count)
    local scope = ('%s #%s'):format(f.labels.pr_one, num)
    local filter_label = prompt_labels[filter]
    local title = filter_label and ('%s %s Checks'):format(scope, filter_label)
      or (scope .. ' Checks')
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_check_entries(checks)
    local filtered = forge_mod.filter_checks(checks, filter)
    local count = #filtered
    local displays = forge_mod.format_checks(filtered, { width = layout.picker_width() })
    local entries = {}
    for i, c in ipairs(filtered) do
      table.insert(entries, {
        display = displays[i],
        value = c,
        ordinal = c.name or '',
      })
    end
    local filter_label = labels[filter] or filter
    local empty_text = filter == 'all' and ('No checks for #%s'):format(num)
      or ('No %s checks for #%s'):format(filter_label, num)
    return with_placeholder(entries, empty_text), count
  end

  local actions = {
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
          log.info('no log available - job was not started')
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
        M.checks(f, num, next_ci_filter[filter] or 'all', current_checks)
      end,
    },
    {
      name = 'failed',
      fn = function()
        M.checks(f, num, 'fail', current_checks)
      end,
    },
    {
      name = 'passed',
      fn = function()
        M.checks(f, num, 'pass', current_checks)
      end,
    },
    {
      name = 'running',
      fn = function()
        M.checks(f, num, 'pending', current_checks)
      end,
    },
    {
      name = 'all',
      fn = function()
        M.checks(f, num, 'all', current_checks)
      end,
    },
    {
      name = 'refresh',
      fn = function()
        log.info(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
        M.checks(f, num, filter)
      end,
    },
  }

  local function open_picker(checks)
    current_checks = checks
    local entries, count = build_check_entries(checks)

    picker.pick({
      prompt = checks_prompt(count),
      entries = entries,
      actions = actions,
      picker_name = 'ci',
    })
  end

  if cached_checks then
    log.debug(('checks (%s #%s, cached)'):format(f.labels.pr_one, num))
    open_picker(cached_checks)
    return
  end

  if f.checks_json_cmd then
    picker_session.pick_json({
      key = request_key,
      loading_prompt = checks_prompt,
      actions = actions,
      picker_name = 'ci',
      cmd = function()
        return f:checks_json_cmd(num)
      end,
      on_fetch = function()
        log.info(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
      end,
      on_success = function(checks)
        current_checks = checks
      end,
      build_entries = function(checks)
        current_checks = checks
        local entries = build_check_entries(checks)
        return entries
      end,
      open = open_picker,
      on_failure = function()
        log.info('no checks found')
      end,
      error_entry = function()
        return placeholder_entry(('No checks for #%s'):format(num))
      end,
    })
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
  local request_key = forge_mod.list_key('ci', branch or 'all')
  local labels = {
    all = 'all',
    fail = 'failed',
    pass = 'passed',
    pending = 'running',
  }
  local prompt_labels = {
    fail = 'Failed',
    pass = 'Passed',
    pending = 'Running',
  }
  local scope_label = branch or 'all branches'

  local function ci_prompt(count)
    local filter_label = prompt_labels[filter]
    local title = filter_label and ('%s %s for %s'):format(filter_label, f.labels.ci, scope_label)
      or ('%s for %s'):format(f.labels.ci, scope_label)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_ci_entries(runs)
    local normalized = {}
    for _, entry in ipairs(runs) do
      table.insert(normalized, f:normalize_run(entry))
    end
    local filtered = forge_mod.filter_runs(normalized, filter)
    local count = #filtered
    local displays = forge_mod.format_runs(filtered, { width = layout.picker_width() })

    local entries = {}
    for i, run in ipairs(filtered) do
      table.insert(entries, {
        display = displays[i],
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
    return with_placeholder(entries, empty_text), count
  end

  local actions = {
    {
      name = 'log',
      label = 'log',
      fn = function(entry)
        if not entry then
          return
        end
        local run = entry.value
        local s = run.status:lower()
        local in_progress = s == 'in_progress' or s == 'queued' or s == 'pending' or s == 'running'
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
  }

  local function open_ci_picker(runs)
    local entries, count = build_ci_entries(runs)

    picker.pick({
      prompt = ci_prompt(count),
      entries = entries,
      actions = actions,
      picker_name = 'ci',
    })
  end

  if f.list_runs_json_cmd then
    picker_session.pick_json({
      key = request_key,
      loading_prompt = ci_prompt,
      actions = actions,
      picker_name = 'ci',
      cmd = function()
        return f:list_runs_json_cmd(branch)
      end,
      on_fetch = function()
        log.info('fetching CI runs...')
      end,
      build_entries = function(runs)
        local entries = build_ci_entries(runs)
        return entries
      end,
      open = open_ci_picker,
      on_failure = function()
        log.error('failed to fetch CI runs')
      end,
      error_entry = function()
        return placeholder_entry('Failed to fetch CI runs')
      end,
    })
  elseif f.list_runs_cmd then
    log.info('structured CI data not available for this forge')
  end
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? { limit?: integer }
function M.pr(state, f, opts)
  opts = opts or {}
  local cli_kind = f.kinds.pr
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limit_step = cfg.display.limits.pulls
  local visible_limit = opts.limit or limit_step
  local fetch_limit = visible_limit + 1
  local use_cache = visible_limit == limit_step
  local cache_key = forge_mod.list_key('pr', state)
  local pr_fields = f.pr_fields
  local num_field = pr_fields.number
  local show_state = state ~= 'open'
  local state_map = {}

  local function build_pr_entries(prs)
    for key in pairs(state_map) do
      state_map[key] = nil
    end

    table.sort(prs, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #prs > visible_limit
    if has_more then
      prs = vim.list_slice(prs, 1, visible_limit)
    end
    local entries = {}
    local displays =
      forge_mod.format_prs(prs, pr_fields, show_state, { width = layout.picker_width() })
    for i, pr in ipairs(prs) do
      local num = tostring(pr[pr_fields.number] or '')
      local s = (pr[pr_fields.state] or ''):lower()
      state_map[num] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = displays[i],
        value = num,
        ordinal = (pr[pr_fields.title] or '') .. ' #' .. num,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(visible_limit + limit_step)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.pr)
      or ('No %s %s'):format(state, f.labels.pr)
    return with_placeholder(entries, empty_text), count
  end

  local function reopen_list()
    clear_state_caches(forge_mod, 'pr')
    M.pr(state, f, { limit = visible_limit })
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_pr_json_cmd then
      return
    end
    maybe_prefetch_list(
      forge_mod,
      'pr',
      next_state,
      f.labels.pr,
      f:list_pr_json_cmd(next_state, fetch_limit)
    )
  end

  local actions = {
    {
      name = 'default',
      label = 'more',
      fn = function(entry)
        if entry and entry.load_more then
          M.pr(state, f, { limit = entry.next_limit })
        elseif entry then
          pr_manage_picker(f, entry.value, reopen_list)
        end
      end,
    },
    {
      name = 'checkout',
      label = 'checkout',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).checkout()
        end
      end,
    },
    {
      name = 'review',
      label = 'review',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).review()
        end
      end,
    },
    {
      name = 'worktree',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).worktree()
        end
      end,
    },
    {
      name = 'ci',
      label = 'checks',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).ci()
        end
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          f:view_web(cli_kind, entry.value)
        end
      end,
    },
    {
      name = 'manage',
      label = 'more',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_manage_picker(f, entry.value, reopen_list)
        end
      end,
    },
    {
      name = 'edit',
      fn = function(entry)
        if entry and not entry.load_more then
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
        if entry and not entry.load_more then
          pr_toggle_state(f, entry.value, state_map[entry.value] ~= false, reopen_list)
        end
      end,
    },
    {
      name = 'filter',
      fn = function()
        M.pr(next_state, f, { limit = visible_limit })
      end,
    },
    {
      name = 'refresh',
      fn = function()
        clear_state_caches(forge_mod, 'pr')
        M.pr(state, f, { limit = visible_limit })
      end,
    },
  }

  local function open_pr_list(prs)
    local entries, count = build_pr_entries(prs)

    picker.pick({
      prompt = ('%s %s (%d)> '):format(state_label, f.labels.pr, count),
      entries = entries,
      actions = actions,
      picker_name = 'pr',
    })
    maybe_prefetch_next()
  end

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = function()
      return ('%s %s> '):format(state_label, f.labels.pr)
    end,
    actions = actions,
    picker_name = 'pr',
    cmd = function()
      return f:list_pr_json_cmd(state, fetch_limit)
    end,
    on_fetch = function()
      log.info(('fetching %s list (%s)...'):format(f.labels.pr, state))
    end,
    on_success = function(prs)
      if use_cache then
        forge_mod.set_list(cache_key, prs)
      end
      if picker.backend() == 'fzf-lua' then
        maybe_prefetch_next()
      end
    end,
    build_entries = function(prs)
      local entries = build_pr_entries(prs)
      return entries
    end,
    open = open_pr_list,
    on_failure = function()
      log.error('failed to fetch ' .. f.labels.pr)
    end,
    error_entry = function()
      return placeholder_entry('Failed to fetch ' .. f.labels.pr)
    end,
  })
end

---@param state 'all'|'open'|'closed'
---@param f forge.Forge
---@param opts? { limit?: integer }
function M.issue(state, f, opts)
  opts = opts or {}
  local cli_kind = f.kinds.issue
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limit_step = cfg.display.limits.issues
  local visible_limit = opts.limit or limit_step
  local fetch_limit = visible_limit + 1
  local use_cache = visible_limit == limit_step
  local cache_key = forge_mod.list_key('issue', state)
  local issue_fields = f.issue_fields
  local num_field = issue_fields.number
  local issue_show_state = state == 'all'
  local state_map = {}

  local function build_issue_entries(issues)
    for key in pairs(state_map) do
      state_map[key] = nil
    end

    table.sort(issues, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #issues > visible_limit
    if has_more then
      issues = vim.list_slice(issues, 1, visible_limit)
    end
    local state_field = issue_fields.state
    local entries = {}
    local displays = forge_mod.format_issues(
      issues,
      issue_fields,
      issue_show_state,
      { width = layout.picker_width() }
    )
    for i, issue in ipairs(issues) do
      local n = tostring(issue[num_field] or '')
      local s = (issue[state_field] or ''):lower()
      state_map[n] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = displays[i],
        value = n,
        ordinal = (issue[issue_fields.title] or '') .. ' #' .. n,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(visible_limit + limit_step)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.issue)
      or ('No %s %s'):format(state, f.labels.issue)
    return with_placeholder(entries, empty_text), count
  end

  local function reopen_list()
    clear_state_caches(forge_mod, 'issue')
    M.issue(state, f, { limit = visible_limit })
  end

  local function maybe_prefetch_next()
    if not use_cache or not f.list_issue_json_cmd then
      return
    end
    maybe_prefetch_list(
      forge_mod,
      'issue',
      next_state,
      f.labels.issue,
      f:list_issue_json_cmd(next_state, fetch_limit)
    )
  end

  local actions = {
    {
      name = 'default',
      label = 'open',
      close = false,
      fn = function(entry)
        if entry and entry.load_more then
          M.issue(state, f, { limit = entry.next_limit })
        elseif entry then
          f:view_web(cli_kind, entry.value)
        end
      end,
    },
    {
      name = 'browse',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          f:view_web(cli_kind, entry.value)
        end
      end,
    },
    {
      name = 'close',
      label = state == 'open' and 'close' or state == 'closed' and 'reopen' or 'toggle',
      fn = function(entry)
        if entry and not entry.load_more then
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
        M.issue(next_state, f, { limit = visible_limit })
      end,
    },
    {
      name = 'refresh',
      fn = function()
        clear_state_caches(forge_mod, 'issue')
        M.issue(state, f, { limit = visible_limit })
      end,
    },
  }

  local function open_issue_list(issues)
    local entries, count = build_issue_entries(issues)

    picker.pick({
      prompt = ('%s %s (%d)> '):format(state_label, f.labels.issue, count),
      entries = entries,
      actions = actions,
      picker_name = 'issue',
    })
    maybe_prefetch_next()
  end

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = function()
      return ('%s %s> '):format(state_label, f.labels.issue)
    end,
    actions = actions,
    picker_name = 'issue',
    cmd = function()
      return f:list_issue_json_cmd(state, fetch_limit)
    end,
    on_fetch = function()
      log.info('fetching issue list (' .. state .. ')...')
    end,
    on_success = function(issues)
      if use_cache then
        forge_mod.set_list(cache_key, issues)
      end
      if picker.backend() == 'fzf-lua' then
        maybe_prefetch_next()
      end
    end,
    build_entries = function(issues)
      local entries = build_issue_entries(issues)
      return entries
    end,
    open = open_issue_list,
    on_failure = function()
      log.error('failed to fetch issues')
    end,
    error_entry = function()
      return placeholder_entry('Failed to fetch issues')
    end,
  })
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
  local cache_key = forge_mod.list_key('release', 'list')
  local rel_fields = f.release_fields
  local next_state = ({ all = 'draft', draft = 'prerelease', prerelease = 'all' })[state]
  local title = ({ all = 'Releases', draft = 'Draft Releases', prerelease = 'Pre-releases' })[state]
    or 'Releases'

  local function release_prompt(count)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_release_entries(releases)
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
    local displays =
      forge_mod.format_releases(filtered, rel_fields, { width = layout.picker_width() })
    for i, rel in ipairs(filtered) do
      local tag = tostring(rel[rel_fields.tag] or '')
      table.insert(entries, {
        display = displays[i],
        value = { tag = tag, rel = rel },
        ordinal = tag .. ' ' .. (rel[rel_fields.title] or ''),
      })
    end
    local count = #entries
    local empty_text = state == 'all' and 'No releases'
      or state == 'draft' and 'No draft releases'
      or 'No prerelease releases'
    return with_placeholder(entries, empty_text), count
  end

  local function reopen_list()
    clear_list_cache(forge_mod, cache_key)
    M.release(state, f)
  end

  local actions = {
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
              reopen_list,
              reopen_list
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
        clear_list_cache(forge_mod, cache_key)
        M.release(state, f)
      end,
    },
  }

  local function open_release_list(releases)
    local entries, count = build_release_entries(releases)

    picker.pick({
      prompt = release_prompt(count),
      entries = entries,
      actions = actions,
      picker_name = 'release',
    })
  end

  local cached = forge_mod.get_list(cache_key)
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = release_prompt,
    actions = actions,
    picker_name = 'release',
    cmd = function()
      return f:list_releases_json_cmd()
    end,
    on_fetch = function()
      log.info('fetching releases...')
    end,
    on_success = function(releases)
      forge_mod.set_list(cache_key, releases)
    end,
    build_entries = function(releases)
      local entries = build_release_entries(releases)
      return entries
    end,
    open = open_release_list,
    on_failure = function()
      log.error('failed to fetch releases')
    end,
    error_entry = function()
      return placeholder_entry('Failed to fetch releases')
    end,
  })
end

---@param ctx { root: string, branch: string, forge: forge.Forge? }
function M.branches(ctx)
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('branch', 'local-refs-v2')

  local function open_branch_list(branches)
    local plan = branch_layout(branches)
    local entries = {}
    for _, item in ipairs(branches) do
      entries[#entries + 1] = {
        display = branch_display(item, plan),
        value = item,
        ordinal = item.name,
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
        name = 'delete',
        label = 'delete',
        fn = function(entry)
          if not entry then
            return
          end
          local item = entry.value
          if item.current then
            log.warn('cannot delete active branch ' .. item.name)
            return
          end
          if item.worktree_path then
            log.warn(
              ('branch %s is checked out in worktree %s; use Worktrees to remove it first'):format(
                item.name,
                item.worktree_path
              )
            )
            return
          end
          vim.ui.select({ 'Yes', 'No' }, {
            prompt = 'Delete branch ' .. item.name .. '? ',
          }, function(choice)
            if choice == 'Yes' then
              run_git_cmd(
                'deleting branch ' .. item.name,
                { 'git', 'branch', '--delete', item.name },
                'deleted branch ' .. item.name,
                'delete failed',
                function()
                  forge_mod.clear_list(cache_key)
                  M.branches(ctx)
                end,
                function()
                  M.branches(ctx)
                end
              )
            else
              M.branches(ctx)
            end
          end)
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
      prompt = ('Branches (%d)> '):format(count),
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
    local plan = commit_layout(commits)
    local entries = {}
    for _, item in ipairs(commits) do
      entries[#entries + 1] = {
        display = commit_display(item, plan),
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
      prompt = ('Commits on %s (%d)> '):format(branch, count),
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
    '--format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e',
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
    local plan = worktree_layout(worktrees)
    local entries = {}
    for _, item in ipairs(worktrees) do
      local ordinal = item.branch ~= '' and item.branch or vim.fs.basename(item.path)
      if item.detached and item.short_head ~= '' then
        ordinal = ordinal .. ' ' .. item.short_head
      end
      entries[#entries + 1] = {
        display = worktree_display(item, plan),
        value = item,
        ordinal = ordinal,
      }
    end
    local count = #entries
    entries = with_placeholder(entries, 'No linked worktrees')

    local function reopen()
      M.worktrees(ctx)
    end

    picker.pick({
      prompt = ('Worktrees (%d)> '):format(count),
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
          name = 'add',
          label = 'add',
          fn = function()
            vim.ui.input({
              prompt = 'Add worktree branch: ',
            }, function(input)
              local branch = vim.trim(input or '')
              if branch == '' then
                reopen()
                return
              end
              local wt_path = vim.fs.normalize(ctx.root .. '/../' .. branch)
              vim.system(
                { 'git', 'show-ref', '--verify', '--quiet', 'refs/heads/' .. branch },
                { text = true },
                function(result)
                  local cmd = result.code == 0 and { 'git', 'worktree', 'add', wt_path, branch }
                    or { 'git', 'worktree', 'add', wt_path, '-b', branch }
                  run_git_cmd(
                    'adding worktree ' .. wt_path,
                    cmd,
                    'worktree at ' .. wt_path,
                    'worktree add failed',
                    function()
                      forge_mod.clear_list(cache_key)
                      reopen()
                    end,
                    reopen
                  )
                end
              )
            end)
          end,
        },
        {
          name = 'delete',
          label = 'delete',
          fn = function(entry)
            if not entry then
              return
            end
            local item = entry.value
            if item.current then
              log.warn('cannot delete current worktree ' .. item.path)
              reopen()
              return
            end
            vim.ui.select({ 'Yes', 'No' }, {
              prompt = 'Delete worktree ' .. item.path .. '? ',
            }, function(choice)
              if choice == 'Yes' then
                run_git_cmd(
                  'deleting worktree ' .. item.path,
                  { 'git', 'worktree', 'remove', item.path },
                  'deleted worktree ' .. item.path,
                  'worktree delete failed',
                  function()
                    forge_mod.clear_list(cache_key)
                    reopen()
                  end,
                  reopen
                )
              else
                reopen()
              end
            end)
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
