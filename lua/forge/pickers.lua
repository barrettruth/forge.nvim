local M = {}

local format = require('forge.format')
local layout = require('forge.layout')
local log = require('forge.logger')
local ops = require('forge.ops')
local picker = require('forge.picker')
local picker_session = require('forge.picker.session')

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

local next_ci_filter = {
  all = 'fail',
  fail = 'pass',
  pass = 'pending',
  pending = 'all',
}

local prev_ci_filter = {
  all = 'pending',
  fail = 'all',
  pass = 'fail',
  pending = 'pass',
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
---@param keep_open boolean?
---@return forge.PickerEntry
local function load_more_entry(next_limit, keep_open)
  local entry = {
    display = { { 'Load more...', 'ForgeDim' } },
    value = nil,
    ordinal = 'Load more',
    load_more = true,
    next_limit = next_limit,
  }
  if keep_open then
    entry.keep_open = true
  else
    entry.force_close = true
  end
  return entry
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

local function set_clipboard(text)
  local ok = pcall(vim.fn.setreg, '+', text)
  if not ok then
    pcall(vim.fn.setreg, '"', text)
  end
end

local function cached_rows(build)
  local cache = {}
  return function(width)
    width = width or layout.picker_width()
    local rows = cache[width]
    if rows == nil then
      rows = build(width)
      cache[width] = rows
    end
    return rows
  end
end

local function scoped_forge_ref(f, ref)
  if ref then
    return ref
  end
  local forge_mod = require('forge')
  if forge_mod.current_scope then
    return forge_mod.current_scope(f.name)
  end
  return nil
end

local function scoped_key(forge_mod, ref)
  if forge_mod.scope_key then
    return forge_mod.scope_key(ref)
  end
  return ''
end

local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

local list_states = { 'open', 'closed', 'all' }

local function clear_state_caches(forge_mod, kind, suffix)
  local scoped_suffix = suffix ~= '' and suffix or nil
  for _, state in ipairs(list_states) do
    local key = forge_mod.list_key(kind, scoped_suffix and (state .. '|' .. scoped_suffix) or state)
    forge_mod.clear_list(key)
    picker_session.invalidate(key)
  end
end

local function clear_list_cache(forge_mod, key)
  forge_mod.clear_list(key)
  picker_session.invalidate(key)
end

local function fetch_json_now(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  local ok, data = picker_session.decode_json(result)
  return ok, data, result
end

local function limit_settings(base_limit, requested_limit)
  local visible_limit = requested_limit or base_limit
  return {
    step = base_limit,
    visible = visible_limit,
    fetch = visible_limit + 1,
    use_cache = visible_limit == base_limit,
  }
end

local function expanded_limit(limit, step)
  return limit + step
end

local function maybe_prefetch_list(forge_mod, kind, state, label, cmd, suffix)
  local scoped_suffix = suffix ~= '' and suffix or nil
  local key = forge_mod.list_key(kind, scoped_suffix and (state .. '|' .. scoped_suffix) or state)
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

local function confirm_input(prompt, enabled, on_confirm, on_cancel)
  if enabled == false then
    on_confirm()
    return
  end

  vim.ui.input({
    prompt = prompt .. ' [y/N] ',
  }, function(input)
    local choice = vim.trim((input or '')):lower()
    if choice == 'y' or choice == 'yes' then
      on_confirm()
      return
    end
    if on_cancel then
      on_cancel()
    end
  end)
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

local function branch_layout(branches, width)
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
    width = width or layout.picker_width(),
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

local function commit_layout(commits, width)
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
    width = width or layout.picker_width(),
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
    marker_hl = 'ForgeBranchCurrent'
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

local function worktree_layout(worktrees, width)
  local path_limit = 35
  local label_limit = 25
  local ok, forge = pcall(require, 'forge')
  if ok and forge.config then
    local widths = forge.config().display.widths
    path_limit = widths.name or path_limit
    label_limit = widths.branch or label_limit
  end

  local paths = {}
  local full_paths = {}
  local labels = {}
  local shas = {}
  for _, item in ipairs(worktrees) do
    paths[#paths + 1] = vim.fn.pathshorten(home_path(item.path))
    full_paths[#full_paths + 1] = home_path(item.path)
    labels[#labels + 1] = worktree_label(item)
    shas[#shas + 1] = item.short_head
  end
  local path_opts = #paths <= 3 and { typical_quantile = 1, max_quantile = 1 }
    or { typical_quantile = 0.7, max_quantile = 0.85 }
  local path_pref = elastic_width(path_limit, paths, 12, path_opts)
  local path_max = math.max(path_pref, layout.max_width(full_paths))
  local label_pref = elastic_width(label_limit, labels, 8)
  local label_max = math.max(label_pref, layout.max_width(labels))
  return layout.plan({
    width = width or layout.picker_width(),
    columns = {
      { key = 'marker', fixed = 2 },
      {
        key = 'label',
        gap = '',
        min = 8,
        preferred = label_pref,
        max = label_max,
        optional = true,
        drop = 2,
        shrink = 3,
        grow = 1,
        overflow = 'tail',
        pack_on = 'compact',
        hide_if_empty = true,
      },
      {
        key = 'path',
        gap = ' ',
        min = 12,
        preferred = path_pref,
        max = path_max,
        shrink = 3,
        grow = 2,
        overflow = 'head',
        pack_on = 'compact',
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
    marker = {
      item.current and '* ' or '  ',
      item.current and 'ForgeBranchCurrent' or 'ForgeDim',
    },
    label = {
      label,
      item.current and item.branch ~= '' and 'ForgeBranchCurrent'
        or item.branch ~= '' and 'ForgeBranch'
        or 'ForgeDim',
    },
    path = {
      render = function(width)
        return { display_path(item.path, width), 'Directory' }
      end,
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
      local sha = vim.trim(fields[1])
      local short_sha = vim.trim(fields[2])
      local subject = vim.trim(fields[3])
      local author = vim.trim(fields[4])
      local timestamp = vim.trim(fields[5])
      commits[#commits + 1] = {
        sha = sha,
        short_sha = short_sha,
        subject = subject,
        author = author,
        relative = format.relative_time_from_unix(timestamp),
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
local function issue_toggle_state(f, num, is_open, on_success, ref)
  if is_open then
    ops.issue_close(
      f,
      { num = num, scope = ref },
      { on_success = on_success, on_failure = on_success }
    )
  else
    ops.issue_reopen(
      f,
      { num = num, scope = ref },
      { on_success = on_success, on_failure = on_success }
    )
  end
end

---@param f forge.Forge
---@param num string
---@param is_open boolean
local function pr_toggle_state(f, num, is_open, on_success, ref)
  if is_open then
    ops.pr_close(
      f,
      { num = num, scope = ref },
      { on_success = on_success, on_failure = on_success }
    )
  else
    ops.pr_reopen(
      f,
      { num = num, scope = ref },
      { on_success = on_success, on_failure = on_success }
    )
  end
end

---@param pr forge.PRRefLike
---@return forge.PRRef
local function normalize_pr_ref(pr)
  if type(pr) == 'table' then
    return pr
  end
  return { num = pr }
end

---@param f forge.Forge
---@param pr forge.PRRef
---@return table<string, function>
local function pr_action_fns(f, pr)
  return {
    checkout = function()
      ops.pr_checkout(f, pr)
    end,
    browse = function()
      ops.pr_browse(f, pr)
    end,
    worktree = function()
      ops.pr_worktree(f, pr)
    end,
    ci = function(opts)
      ops.pr_ci(f, pr, opts)
    end,
    edit = function()
      ops.pr_edit(pr)
    end,
  }
end

local function issue_action_fns(f, issue)
  return {
    browse = function()
      ops.issue_browse(f, issue)
    end,
    edit = function()
      ops.issue_edit(issue)
    end,
  }
end

---@param f forge.Forge
---@param pr forge.PRRef
local function pr_toggle_draft_action(f, pr, opts)
  opts = opts or {}
  local is_draft = rawget(pr, 'is_draft')
  if is_draft == nil then
    local pr_state = f:pr_state(pr.num, pr.scope)
    is_draft = pr_state.is_draft == true
  end
  ops.pr_toggle_draft(f, pr, is_draft, opts)
end

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
---@param opts? forge.PickerLimitOpts
function M.checks(f, num, filter, cached_checks, opts)
  opts = opts or {}
  filter = filter or 'all'
  local forge_mod = require('forge')
  local ref = scoped_forge_ref(f, opts.scope)
  local current_checks = cached_checks
  local request_key = forge_mod.list_key('check', scoped_id(num, scoped_key(forge_mod, ref)))
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
    local rows_for = cached_rows(function(width)
      return forge_mod.format_checks(filtered, { width = width })
    end)
    local displays = rows_for()
    local entries = {}
    for i, c in ipairs(filtered) do
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
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
        local check_ref = c.scope or ref
        if in_progress and f.live_tail_cmd then
          require('forge.term').open(f:live_tail_cmd(run_id, job_id, check_ref), { url = c.link })
        else
          log.info('fetching check logs...')
          local cmd = f:check_log_cmd(run_id, bucket == 'fail', job_id, check_ref)
          local steps_cmd = f.steps_cmd and f:steps_cmd(run_id, check_ref) or nil
          local status_cmd = f.run_status_cmd and f:run_status_cmd(run_id, check_ref) or nil
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
        M.checks(
          f,
          num,
          next_ci_filter[filter] or 'all',
          current_checks,
          { back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'filter_prev',
      label = 'prev',
      fn = function()
        M.checks(
          f,
          num,
          prev_ci_filter[filter] or 'all',
          current_checks,
          { back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'failed',
      label = 'failed',
      fn = function()
        M.checks(f, num, 'fail', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      fn = function()
        M.checks(f, num, 'pass', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      fn = function()
        M.checks(f, num, 'pending', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      fn = function()
        M.checks(f, num, 'all', current_checks, { back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      fn = function()
        log.info(('refreshing checks for %s #%s...'):format(f.labels.pr_one, num))
        M.checks(f, num, filter, nil, { back = opts.back, scope = ref })
      end,
    },
  }

  local function open_picker(checks)
    current_checks = checks
    for _, check in ipairs(checks) do
      check.scope = check.scope or ref
    end
    local entries, count = build_check_entries(checks)

    picker.pick({
      prompt = checks_prompt(count),
      entries = entries,
      actions = actions,
      picker_name = 'ci',
      back = opts.back,
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
      back = opts.back,
      cmd = function()
        return f:checks_json_cmd(num, ref)
      end,
      on_fetch = function()
        log.info(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
      end,
      on_success = function(checks)
        current_checks = checks
      end,
      build_entries = function(checks)
        current_checks = checks
        for _, check in ipairs(checks) do
          check.scope = check.scope or ref
        end
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
---@param opts? forge.PickerLimitOpts
function M.ci(f, branch, filter, opts)
  opts = opts or {}
  filter = filter or 'all'
  local forge_mod = require('forge')
  local limits = limit_settings(forge_mod.config().display.limits.runs, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local ref = scoped_forge_ref(f, opts.scope)
  local request_key =
    forge_mod.list_key('ci', scoped_id(branch or 'all', scoped_key(forge_mod, ref)))
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
  local live_load_more = picker.backend() == 'fzf-lua'
  local current_limit = visible_limit
  local current_runs

  local function ci_prompt(count)
    local filter_label = prompt_labels[filter]
    local title = filter_label and ('%s %s for %s'):format(filter_label, f.labels.ci, scope_label)
      or ('%s for %s'):format(f.labels.ci, scope_label)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_ci_entries(runs, limit)
    limit = limit or current_limit
    local normalized = {}
    for _, entry in ipairs(runs) do
      local run = f:normalize_run(entry)
      run.scope = run.scope or ref
      table.insert(normalized, run)
    end
    local has_more = #normalized > limit
    local filtered = forge_mod.filter_runs(normalized, filter)
    if #filtered > limit then
      filtered = vim.list_slice(filtered, 1, limit)
    end
    local count = #filtered
    local rows_for = cached_rows(function(width)
      return forge_mod.format_runs(filtered, { width = width })
    end)
    local displays = rows_for()

    local entries = {}
    for i, run in ipairs(filtered) do
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = run,
        ordinal = run.name .. ' ' .. run.branch,
      })
    end
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), live_load_more)
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

  local function load_more_runs(next_limit)
    local ok, runs = fetch_json_now(f:list_runs_json_cmd(branch, ref, next_limit + 1))
    if not ok then
      log.error('failed to fetch CI runs')
      return
    end
    current_runs = runs
    current_limit = next_limit
  end

  local actions = {
    {
      name = 'log',
      label = 'log',
      fn = function(entry)
        if not entry then
          return
        end
        if entry.load_more then
          if live_load_more then
            load_more_runs(entry.next_limit)
          else
            M.ci(f, branch, filter, { limit = entry.next_limit, back = opts.back, scope = ref })
          end
          return
        end
        ops.ci_log(f, entry.value)
      end,
    },
    {
      name = 'watch',
      label = 'watch',
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        ops.ci_watch(f, entry.value)
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more and entry.value.url ~= '' then
          vim.ui.open(entry.value.url)
        end
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      fn = function()
        M.ci(
          f,
          branch,
          next_ci_filter[filter] or 'all',
          { limit = current_limit, back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'filter_prev',
      label = 'prev',
      fn = function()
        M.ci(
          f,
          branch,
          prev_ci_filter[filter] or 'all',
          { limit = current_limit, back = opts.back, scope = ref }
        )
      end,
    },
    {
      name = 'failed',
      label = 'failed',
      fn = function()
        M.ci(f, branch, 'fail', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'passed',
      label = 'passed',
      fn = function()
        M.ci(f, branch, 'pass', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'running',
      label = 'running',
      fn = function()
        M.ci(f, branch, 'pending', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'all',
      label = 'all',
      fn = function()
        M.ci(f, branch, 'all', { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      fn = function()
        log.info('refreshing CI runs...')
        M.ci(f, branch, filter, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  local function open_ci_picker(runs)
    current_runs = runs
    local entries, count = build_ci_entries(runs, current_limit)

    picker.pick({
      prompt = ci_prompt(count),
      entries = entries,
      entry_source = live_load_more and function()
        if not current_runs then
          return {}
        end
        return build_ci_entries(current_runs, current_limit)
      end or nil,
      actions = actions,
      picker_name = 'ci',
      back = opts.back,
    })
  end

  if f.list_runs_json_cmd then
    picker_session.pick_json({
      key = request_key,
      loading_prompt = ci_prompt,
      actions = actions,
      picker_name = 'ci',
      back = opts.back,
      cmd = function()
        return f:list_runs_json_cmd(branch, ref, fetch_limit)
      end,
      on_fetch = function()
        log.info('fetching CI runs...')
      end,
      entry_source = live_load_more and function()
        if not current_runs then
          return {}
        end
        return build_ci_entries(current_runs, current_limit)
      end or nil,
      initial_stream_only = live_load_more,
      build_entries = function(runs)
        current_runs = runs
        return build_ci_entries(runs, current_limit)
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
---@param opts? forge.PickerLimitOpts
function M.pr(state, f, opts)
  opts = opts or {}
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local prev_state = ({ all = 'closed', open = 'all', closed = 'open' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limits = limit_settings(cfg.display.limits.pulls, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local use_cache = limits.use_cache
  local ref = scoped_forge_ref(f, opts.scope)
  local cache_key = forge_mod.list_key('pr', scoped_id(state, scoped_key(forge_mod, ref)))
  local pr_fields = f.pr_fields
  local num_field = pr_fields.number
  local show_state = state ~= 'open'
  local state_map = {}
  local live_load_more = picker.backend() == 'fzf-lua'
  local current_limit = visible_limit
  local current_prs

  local function build_pr_entries(prs, limit)
    limit = limit or current_limit
    for key in pairs(state_map) do
      state_map[key] = nil
    end

    table.sort(prs, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #prs > limit
    if has_more then
      prs = vim.list_slice(prs, 1, limit)
    end
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_prs(prs, pr_fields, show_state, { width = width })
    end)
    local displays = rows_for()
    for i, pr in ipairs(prs) do
      local num = tostring(pr[pr_fields.number] or '')
      local s = (pr[pr_fields.state] or ''):lower()
      local draft_field = rawget(pr_fields, 'is_draft')
      state_map[num] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = {
          num = num,
          scope = ref,
          state = pr[pr_fields.state],
          is_draft = draft_field and pr[draft_field] or nil,
        },
        ordinal = (pr[pr_fields.title] or '') .. ' #' .. num,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), live_load_more)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.pr)
      or ('No %s %s'):format(state, f.labels.pr)
    return with_placeholder(entries, empty_text), count
  end

  local function load_more_prs(next_limit)
    local ok, prs = fetch_json_now(f:list_pr_json_cmd(state, next_limit + 1, ref))
    if not ok then
      log.error('failed to fetch ' .. f.labels.pr)
      return
    end
    current_prs = prs
    current_limit = next_limit
  end

  local function reopen_list()
    clear_state_caches(forge_mod, 'pr', scoped_key(forge_mod, ref))
    M.pr(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local function back_to_list()
    M.pr(state, f, { limit = current_limit, back = opts.back, scope = ref })
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
      f:list_pr_json_cmd(next_state, fetch_limit, ref),
      scoped_key(forge_mod, ref)
    )
  end

  local actions = {
    {
      name = 'default',
      label = 'checkout',
      fn = function(entry)
        if entry and entry.load_more then
          if live_load_more then
            load_more_prs(entry.next_limit)
          else
            M.pr(state, f, { limit = entry.next_limit, back = opts.back, scope = ref })
          end
        elseif entry then
          pr_action_fns(f, entry.value).checkout()
        end
      end,
    },
    {
      name = 'worktree',
      label = 'worktree',
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
          pr_action_fns(f, entry.value).ci({ back = back_to_list })
        end
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          ops.pr_browse(f, entry.value)
        end
      end,
    },
    {
      name = 'edit',
      label = 'edit',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_action_fns(f, entry.value).edit()
        end
      end,
    },
    {
      name = 'approve',
      label = 'approve',
      fn = function(entry)
        if entry and not entry.load_more then
          ops.pr_approve(f, entry.value, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'merge',
      label = 'merge',
      fn = function(entry)
        if entry and not entry.load_more then
          ops.pr_merge(f, entry.value, nil, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'create',
      label = 'create',
      fn = function()
        ops.pr_create({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'close',
      label = state == 'open' and 'close' or state == 'closed' and 'reopen' or 'close/reopen',
      fn = function(entry)
        if entry and not entry.load_more then
          pr_toggle_state(
            f,
            entry.value.num,
            state_map[entry.value.num] ~= false,
            reopen_list,
            entry.value.scope
          )
        end
      end,
    },
    {
      name = 'draft',
      label = 'draft/ready',
      fn = function(entry)
        if entry and not entry.load_more and f.capabilities.draft then
          pr_toggle_draft_action(f, entry.value, {
            on_success = reopen_list,
            on_failure = reopen_list,
          })
        end
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      fn = function()
        M.pr(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter_prev',
      label = 'prev',
      fn = function()
        M.pr(prev_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      fn = function()
        clear_state_caches(forge_mod, 'pr', scoped_key(forge_mod, ref))
        M.pr(state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  local function open_pr_list(prs)
    current_prs = prs
    local entries, count = build_pr_entries(prs, current_limit)

    picker.pick({
      prompt = ('%s %s (%d)> '):format(state_label, f.labels.pr, count),
      entries = entries,
      entry_source = live_load_more and function()
        if not current_prs then
          return {}
        end
        return build_pr_entries(current_prs, current_limit)
      end or nil,
      actions = actions,
      picker_name = 'pr',
      back = opts.back,
    })
    maybe_prefetch_next()
  end

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  if cached and live_load_more then
    open_pr_list(cached)
    return
  end
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = function()
      return ('%s %s> '):format(state_label, f.labels.pr)
    end,
    actions = actions,
    picker_name = 'pr',
    back = opts.back,
    cmd = function()
      return f:list_pr_json_cmd(state, fetch_limit, ref)
    end,
    on_fetch = function()
      log.info(('fetching %s list (%s)...'):format(f.labels.pr, state))
    end,
    on_success = function(prs)
      current_prs = prs
      if use_cache then
        forge_mod.set_list(cache_key, prs)
      end
      if picker.backend() == 'fzf-lua' then
        maybe_prefetch_next()
      end
    end,
    entry_source = live_load_more and function()
      if not current_prs then
        return {}
      end
      return build_pr_entries(current_prs, current_limit)
    end or nil,
    initial_stream_only = live_load_more,
    build_entries = function(prs)
      current_prs = prs
      return build_pr_entries(prs, current_limit)
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
---@param opts? forge.PickerLimitOpts
function M.issue(state, f, opts)
  opts = opts or {}
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
  local prev_state = ({ all = 'closed', open = 'all', closed = 'open' })[state]
  local state_label = ({ all = 'All', open = 'Open', closed = 'Closed' })[state] or state
  local forge_mod = require('forge')
  local cfg = forge_mod.config()
  local limits = limit_settings(cfg.display.limits.issues, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local use_cache = limits.use_cache
  local ref = scoped_forge_ref(f, opts.scope)
  local cache_key = forge_mod.list_key('issue', scoped_id(state, scoped_key(forge_mod, ref)))
  local issue_fields = f.issue_fields
  local num_field = issue_fields.number
  local issue_show_state = state == 'all'
  local state_map = {}
  local live_load_more = picker.backend() == 'fzf-lua'
  local current_limit = visible_limit
  local current_issues

  local function build_issue_entries(issues, limit)
    limit = limit or current_limit
    for key in pairs(state_map) do
      state_map[key] = nil
    end

    table.sort(issues, function(a, b)
      return (a[num_field] or 0) > (b[num_field] or 0)
    end)
    local has_more = #issues > limit
    if has_more then
      issues = vim.list_slice(issues, 1, limit)
    end
    local state_field = issue_fields.state
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_issues(issues, issue_fields, issue_show_state, { width = width })
    end)
    local displays = rows_for()
    for i, issue in ipairs(issues) do
      local n = tostring(issue[num_field] or '')
      local s = (issue[state_field] or ''):lower()
      state_map[n] = s == 'open' or s == 'opened'
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = { num = n, scope = ref },
        ordinal = (issue[issue_fields.title] or '') .. ' #' .. n,
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), live_load_more)
    end
    local empty_text = state == 'all' and ('No %s'):format(f.labels.issue)
      or ('No %s %s'):format(state, f.labels.issue)
    return with_placeholder(entries, empty_text), count
  end

  local function load_more_issues(next_limit)
    local ok, issues = fetch_json_now(f:list_issue_json_cmd(state, next_limit + 1, ref))
    if not ok then
      log.error('failed to fetch issues')
      return
    end
    current_issues = issues
    current_limit = next_limit
  end

  local function reopen_list()
    clear_state_caches(forge_mod, 'issue', scoped_key(forge_mod, ref))
    M.issue(state, f, { limit = current_limit, back = opts.back, scope = ref })
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
      f:list_issue_json_cmd(next_state, fetch_limit, ref),
      scoped_key(forge_mod, ref)
    )
  end

  local actions = {
    {
      name = 'default',
      label = 'open',
      close = false,
      fn = function(entry)
        if entry and entry.load_more then
          if live_load_more then
            load_more_issues(entry.next_limit)
          else
            M.issue(state, f, { limit = entry.next_limit, back = opts.back, scope = ref })
          end
        elseif entry then
          issue_action_fns(f, entry.value).browse()
        end
      end,
    },
    {
      name = 'browse',
      label = 'web',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          issue_action_fns(f, entry.value).browse()
        end
      end,
    },
    {
      name = 'edit',
      label = 'edit',
      fn = function(entry)
        if entry and not entry.load_more then
          issue_action_fns(f, entry.value).edit()
        end
      end,
    },
    {
      name = 'close',
      label = state == 'open' and 'close' or state == 'closed' and 'reopen' or 'toggle',
      fn = function(entry)
        if entry and not entry.load_more then
          issue_toggle_state(
            f,
            entry.value.num,
            state_map[entry.value.num] ~= false,
            reopen_list,
            entry.value.scope
          )
        end
      end,
    },
    {
      name = 'create',
      label = 'create',
      fn = function()
        ops.issue_create({ back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      fn = function()
        M.issue(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter_prev',
      label = 'prev',
      fn = function()
        M.issue(prev_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      fn = function()
        clear_state_caches(forge_mod, 'issue', scoped_key(forge_mod, ref))
        M.issue(state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  local function open_issue_list(issues)
    current_issues = issues
    local entries, count = build_issue_entries(issues, current_limit)

    picker.pick({
      prompt = ('%s %s (%d)> '):format(state_label, f.labels.issue, count),
      entries = entries,
      entry_source = live_load_more and function()
        if not current_issues then
          return {}
        end
        return build_issue_entries(current_issues, current_limit)
      end or nil,
      actions = actions,
      picker_name = 'issue',
      back = opts.back,
    })
    maybe_prefetch_next()
  end

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  if cached and live_load_more then
    open_issue_list(cached)
    return
  end
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = function()
      return ('%s %s> '):format(state_label, f.labels.issue)
    end,
    actions = actions,
    picker_name = 'issue',
    back = opts.back,
    cmd = function()
      return f:list_issue_json_cmd(state, fetch_limit, ref)
    end,
    on_fetch = function()
      log.info('fetching issue list (' .. state .. ')...')
    end,
    on_success = function(issues)
      current_issues = issues
      if use_cache then
        forge_mod.set_list(cache_key, issues)
      end
      if picker.backend() == 'fzf-lua' then
        maybe_prefetch_next()
      end
    end,
    entry_source = live_load_more and function()
      if not current_issues then
        return {}
      end
      return build_issue_entries(current_issues, current_limit)
    end or nil,
    initial_stream_only = live_load_more,
    build_entries = function(issues)
      current_issues = issues
      return build_issue_entries(issues, current_limit)
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
---@param ref? forge.Scope
function M.issue_close(f, num, ref)
  ops.issue_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.issue_reopen(f, num, ref)
  ops.issue_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_close(f, num, ref)
  ops.pr_close(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param num string
---@param ref? forge.Scope
function M.pr_reopen(f, num, ref)
  ops.pr_reopen(f, { num = num, scope = ref })
end

---@param f forge.Forge
---@param pr forge.PRRefLike
---@return table<string, function>
function M.pr_actions(f, pr)
  return pr_action_fns(f, normalize_pr_ref(pr))
end

---@param state 'all'|'draft'|'prerelease'
---@param f forge.Forge
---@param opts? forge.PickerLimitOpts
function M.release(state, f, opts)
  opts = opts or {}
  local forge_mod = require('forge')
  local limits = limit_settings(forge_mod.config().display.limits.releases, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local fetch_limit = limits.fetch
  local ref = scoped_forge_ref(f, opts.scope)
  local cache_key = forge_mod.list_key('release', scoped_id('list', scoped_key(forge_mod, ref)))
  local rel_fields = f.release_fields
  local next_state = ({ all = 'draft', draft = 'prerelease', prerelease = 'all' })[state]
  local prev_state = ({ all = 'prerelease', draft = 'all', prerelease = 'draft' })[state]
  local title = ({ all = 'Releases', draft = 'Draft Releases', prerelease = 'Pre-releases' })[state]
    or 'Releases'
  local live_load_more = picker.backend() == 'fzf-lua'
  local current_limit = visible_limit
  local current_releases

  local function remember_release_fetch(releases, requested_limit)
    if type(releases) == 'table' then
      releases._fetch_limit = requested_limit
    end
    return releases
  end

  local function cached_releases()
    local cached = forge_mod.get_list(cache_key)
    if not cached then
      return nil
    end
    local cached_fetch_limit = rawget(cached, '_fetch_limit')
    if cached_fetch_limit == nil then
      if current_limit == limit_step then
        return cached
      end
      return nil
    end
    if cached_fetch_limit >= fetch_limit or #cached < cached_fetch_limit then
      return cached
    end
    return nil
  end

  local function release_prompt(count)
    if count ~= nil then
      return ('%s (%d)> '):format(title, count)
    end
    return title .. '> '
  end

  local function build_release_entries(releases, limit)
    limit = limit or current_limit
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

    local has_more = #releases > limit
    if #filtered > limit then
      filtered = vim.list_slice(filtered, 1, limit)
    end
    local entries = {}
    local rows_for = cached_rows(function(width)
      return forge_mod.format_releases(filtered, rel_fields, { width = width })
    end)
    local displays = rows_for()
    for i, rel in ipairs(filtered) do
      local tag = tostring(rel[rel_fields.tag] or '')
      table.insert(entries, {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = { tag = tag, rel = rel, scope = ref },
        ordinal = tag .. ' ' .. (rel[rel_fields.title] or ''),
      })
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), live_load_more)
    end
    local empty_text = state == 'all' and 'No releases'
      or state == 'draft' and 'No draft releases'
      or 'No prerelease releases'
    return with_placeholder(entries, empty_text), count
  end

  local function load_more_releases(next_visible_limit)
    local ok, releases = fetch_json_now(f:list_releases_json_cmd(ref, next_visible_limit + 1))
    if not ok then
      log.error('failed to fetch releases')
      return
    end
    current_releases = remember_release_fetch(releases, next_visible_limit + 1)
    forge_mod.set_list(cache_key, current_releases)
    current_limit = next_visible_limit
  end

  local function reopen_list()
    clear_list_cache(forge_mod, cache_key)
    M.release(state, f, { limit = current_limit, back = opts.back, scope = ref })
  end

  local actions = {
    {
      name = 'browse',
      label = 'open',
      close = false,
      fn = function(entry)
        if entry and entry.load_more then
          if live_load_more then
            load_more_releases(entry.next_limit)
          else
            M.release(state, f, { limit = entry.next_limit, back = opts.back, scope = ref })
          end
        elseif entry then
          ops.release_browse(f, entry.value)
        end
      end,
    },
    {
      name = 'yank',
      label = 'copy',
      close = false,
      fn = function(entry)
        if entry and not entry.load_more then
          local base = forge_mod.remote_web_url(entry.value.scope)
          local tag = entry.value.tag
          local url = base .. '/releases/tag/' .. tag
          set_clipboard(url)
          log.info('copied release URL')
        end
      end,
    },
    {
      name = 'delete',
      label = 'delete',
      fn = function(entry)
        if not entry or entry.load_more then
          return
        end
        ops.release_delete(f, entry.value, {
          on_success = reopen_list,
          on_failure = reopen_list,
          on_cancel = function()
            M.release(state, f, { limit = current_limit, back = opts.back, scope = ref })
          end,
        })
      end,
    },
    {
      name = 'filter',
      label = 'filter',
      fn = function()
        M.release(next_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'filter_prev',
      label = 'prev',
      fn = function()
        M.release(prev_state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
    {
      name = 'refresh',
      label = 'refresh',
      fn = function()
        clear_list_cache(forge_mod, cache_key)
        M.release(state, f, { limit = current_limit, back = opts.back, scope = ref })
      end,
    },
  }

  local function open_release_list(releases)
    current_releases = releases
    local entries, count = build_release_entries(releases, current_limit)

    picker.pick({
      prompt = release_prompt(count),
      entries = entries,
      entry_source = live_load_more and function()
        if not current_releases then
          return {}
        end
        return build_release_entries(current_releases, current_limit)
      end or nil,
      actions = actions,
      picker_name = 'release',
      back = opts.back,
    })
  end

  local cached = cached_releases()
  picker_session.pick_json({
    key = cache_key,
    cached = cached,
    loading_prompt = release_prompt,
    actions = actions,
    picker_name = 'release',
    back = opts.back,
    cmd = function()
      return f:list_releases_json_cmd(ref, fetch_limit)
    end,
    on_fetch = function()
      log.info('fetching releases...')
    end,
    on_success = function(releases)
      current_releases = remember_release_fetch(releases, fetch_limit)
      forge_mod.set_list(cache_key, current_releases)
    end,
    entry_source = live_load_more and function()
      if not current_releases then
        return {}
      end
      return build_release_entries(current_releases, current_limit)
    end or nil,
    initial_stream_only = live_load_more,
    build_entries = function(releases)
      current_releases = remember_release_fetch(releases, fetch_limit)
      local entries = build_release_entries(releases, current_limit)
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
---@param opts? { back?: fun() }
function M.branches(ctx, opts)
  opts = opts or {}
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('branch', 'local-refs-v2')

  local function open_branch_list(branches)
    local rows_for = cached_rows(function(width)
      local plan = branch_layout(branches, width)
      return vim.tbl_map(function(item)
        return branch_display(item, plan)
      end, branches)
    end)
    local displays = rows_for()
    local entries = {}
    for i, item in ipairs(branches) do
      entries[#entries + 1] = {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = item,
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
        name = 'delete',
        label = 'delete',
        fn = function(entry)
          if not entry then
            return
          end
          local item = entry.value
          local confirm = require('forge').config().confirm
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
          confirm_input('Delete branch ' .. item.name .. '?', confirm.branch_delete, function()
            run_git_cmd(
              'deleting branch ' .. item.name,
              { 'git', 'branch', '--delete', item.name },
              'deleted branch ' .. item.name,
              'delete failed',
              function()
                forge_mod.clear_list(cache_key)
                M.branches(ctx, { back = opts.back })
              end,
              function()
                M.branches(ctx, { back = opts.back })
              end
            )
          end, function()
            M.branches(ctx, { back = opts.back })
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
          set_clipboard(entry.value.name)
          log.info('copied branch name')
        end,
      },
      {
        name = 'refresh',
        label = 'refresh',
        fn = function()
          forge_mod.clear_list(cache_key)
          M.branches(ctx, { back = opts.back })
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
      back = opts.back,
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
---@param opts? { limit?: integer, back?: fun() }
function M.commits(ctx, branch, opts)
  opts = opts or {}
  local forge_mod = require('forge')
  local limits = limit_settings(require('forge.config').config().display.limits.commits, opts.limit)
  local limit_step = limits.step
  local visible_limit = limits.visible
  local use_cache = limits.use_cache
  local cache_key = forge_mod.list_key('commit', branch)
  local live_load_more = picker.backend() == 'fzf-lua'
  local current_limit = visible_limit
  local current_commits
  local active_ref = branch
  local fetch_commits

  local function build_commit_entries(commits, limit)
    limit = limit or current_limit
    local has_more = #commits > limit
    if has_more then
      commits = vim.list_slice(commits, 1, limit)
    end
    local rows_for = cached_rows(function(width)
      local plan = commit_layout(commits, width)
      return vim.tbl_map(function(item)
        return commit_display(item, plan)
      end, commits)
    end)
    local displays = rows_for()
    local entries = {}
    for i, item in ipairs(commits) do
      entries[#entries + 1] = {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = item,
        ordinal = item.sha .. ' ' .. item.subject .. ' ' .. item.author,
      }
    end
    local count = #entries
    if has_more then
      entries[#entries + 1] = load_more_entry(expanded_limit(limit, limit_step), live_load_more)
    end
    entries = with_placeholder(entries, 'No commits in ' .. branch .. ' history')
    return entries, count
  end

  local function open_commit_list(commits)
    current_commits = commits
    local entries, count = build_commit_entries(commits, current_limit)

    local actions = {
      {
        name = 'default',
        label = 'show',
        fn = function(entry)
          if not entry then
            return
          end
          if entry.load_more then
            if live_load_more then
              local result = vim
                .system({
                  'git',
                  'log',
                  '--max-count=' .. (entry.next_limit + 1),
                  '--format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e',
                  active_ref,
                }, { text = true })
                :wait()
              if result.code ~= 0 then
                log.error(cmd_error(result, 'failed to fetch commits'))
                return
              end
              current_limit = entry.next_limit
              current_commits = parse_commits(result.stdout or '')
            else
              M.commits(ctx, branch, { limit = entry.next_limit, back = opts.back })
            end
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
        name = 'yank',
        label = 'copy',
        close = false,
        fn = function(entry)
          if not entry or entry.load_more then
            return
          end
          set_clipboard(entry.value.sha)
          log.info('copied commit SHA')
        end,
      },
      {
        name = 'refresh',
        label = 'refresh',
        fn = function()
          forge_mod.clear_list(cache_key)
          M.commits(ctx, branch, { limit = current_limit, back = opts.back })
        end,
      },
    }

    if ctx.forge then
      table.insert(actions, 2, {
        name = 'browse',
        label = 'web',
        close = false,
        fn = function(entry)
          if entry and not entry.load_more then
            ctx.forge:browse_commit(entry.value.sha)
          end
        end,
      })
    end

    picker.pick({
      prompt = ('Commits on %s (%d)> '):format(branch, count),
      entries = entries,
      entry_source = live_load_more and function()
        if not current_commits then
          return {}
        end
        return build_commit_entries(current_commits, current_limit)
      end or nil,
      actions = actions,
      picker_name = 'commit',
      back = opts.back,
    })
  end

  local function unpack_cached(cached)
    if type(cached) == 'table' and cached.entries then
      return cached.entries, cached.ref or branch
    end
    return cached, branch
  end

  local cached = use_cache and forge_mod.get_list(cache_key) or nil
  if cached then
    local commits, ref_name = unpack_cached(cached)
    active_ref = ref_name
    open_commit_list(commits)
    return
  end

  fetch_commits = function(ref, fallback_ref, next_limit)
    active_ref = ref
    local request_limit = next_limit or current_limit
    log.info('fetching commits for ' .. branch .. '...')
    vim.system({
      'git',
      'log',
      '--max-count=' .. (request_limit + 1),
      '--format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e',
      ref,
    }, { text = true }, function(result)
      if result.code ~= 0 and fallback_ref and fallback_ref ~= ref then
        fetch_commits(fallback_ref, nil, request_limit)
        return
      end
      vim.schedule(function()
        if result.code ~= 0 then
          log.error(cmd_error(result, 'failed to fetch commits'))
          return
        end
        local commits = parse_commits(result.stdout or '')
        current_limit = request_limit
        current_commits = commits
        if use_cache then
          forge_mod.set_list(cache_key, {
            entries = commits,
            ref = ref,
          })
        end
        open_commit_list(commits)
      end)
    end)
  end

  vim.system({
    'git',
    'for-each-ref',
    '--format=%(upstream:short)',
    'refs/heads/' .. branch,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local upstream = vim.trim(result.stdout or '')
        if upstream ~= '' then
          fetch_commits(upstream, branch)
          return
        end
      end
      fetch_commits(branch)
    end)
  end)
end

---@param ctx { root: string }
---@param opts? { back?: fun() }
function M.worktrees(ctx, opts)
  opts = opts or {}
  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key('worktree', 'list')

  local function open_worktree_list(worktrees)
    local rows_for = cached_rows(function(width)
      local plan = worktree_layout(worktrees, width)
      return vim.tbl_map(function(item)
        return worktree_display(item, plan)
      end, worktrees)
    end)
    local displays = rows_for()
    local entries = {}
    for i, item in ipairs(worktrees) do
      entries[#entries + 1] = {
        display = displays[i],
        render_display = function(width)
          return rows_for(width)[i]
        end,
        value = item,
      }
    end
    local count = #entries
    entries = with_placeholder(entries, 'No linked worktrees')

    local function reopen()
      M.worktrees(ctx, { back = opts.back })
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
            local confirm = require('forge').config().confirm
            if item.current then
              log.warn('cannot delete current worktree ' .. item.path)
              reopen()
              return
            end
            confirm_input(
              'Delete worktree ' .. item.path .. '?',
              confirm.worktree_delete,
              function()
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
              end,
              reopen
            )
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
            set_clipboard(entry.value.path)
            log.info('copied worktree path')
          end,
        },
        {
          name = 'refresh',
          label = 'refresh',
          fn = function()
            forge_mod.clear_list(cache_key)
            M.worktrees(ctx, { back = opts.back })
          end,
        },
      },
      picker_name = 'worktree',
      back = opts.back,
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
