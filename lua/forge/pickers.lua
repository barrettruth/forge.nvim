local M = {}

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
  require('forge').log_now(label .. ' ' .. kind .. ' #' .. num .. '...')
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify(('[forge]: %s %s #%s'):format(success_msg, kind, num))
      else
        vim.notify('[forge]: ' .. cmd_error(result, fail_msg), vim.log.levels.ERROR)
      end
      vim.cmd.redraw()
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
      local forge_mod = require('forge')
      forge_mod.log_now(('checking out %s #%s...'):format(kind, num))
      vim.system(f:checkout_cmd(num), { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 then
            vim.notify(('[forge]: checked out %s #%s'):format(kind, num))
          else
            vim.notify('[forge]: ' .. cmd_error(result, 'checkout failed'), vim.log.levels.ERROR)
          end
          vim.cmd.redraw()
        end)
      end)
    end,
    browse = function()
      f:view_web(f.kinds.pr, num)
    end,
    worktree = function()
      local forge_mod = require('forge')
      local fetch_cmd = f:fetch_pr(num)
      local branch = fetch_cmd[#fetch_cmd]:match(':(.+)$')
      if not branch then
        return
      end
      local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
      local wt_path = vim.fs.normalize(root .. '/../' .. branch)
      forge_mod.log_now(('fetching %s #%s into worktree...'):format(kind, num))
      vim.system(fetch_cmd, { text = true }, function()
        vim.system({ 'git', 'worktree', 'add', wt_path, branch }, { text = true }, function(result)
          vim.schedule(function()
            if result.code == 0 then
              vim.notify(('[forge]: worktree at %s'):format(wt_path))
            else
              vim.notify('[forge]: ' .. cmd_error(result, 'worktree failed'), vim.log.levels.ERROR)
            end
            vim.cmd.redraw()
          end)
        end)
      end)
    end,
    diff = function()
      local forge_mod = require('forge')
      local review = require('forge.review')
      local repo_root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))

      forge_mod.log_now(('reviewing %s #%s...'):format(kind, num))
      vim.system(f:checkout_cmd(num), { text = true }, function(co_result)
        if co_result.code ~= 0 then
          vim.schedule(function()
            forge_mod.log('checkout skipped, proceeding with diff')
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
            forge_mod.log(('review ready for %s #%s against %s'):format(kind, num, base))
          end)
        end)
      end)
    end,
    ci = function()
      if f.capabilities.per_pr_checks then
        M.checks(f, num)
      else
        require('forge').log(
          ('per-%s checks unavailable on %s, showing repo CI'):format(kind, f.name)
        )
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
  forge_mod.log_now('loading actions for ' .. kind .. ' #' .. num .. '...')

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
            local run_id = (c.link or ''):match('/actions/runs/(%d+)')
            if not run_id then
              return
            end
            forge_mod.log_now('fetching check logs...')
            local bucket = (c.bucket or ''):lower()
            local cmd
            if bucket == 'pending' then
              cmd = f:check_tail_cmd(run_id)
            else
              cmd = f:check_log_cmd(run_id, bucket == 'fail')
            end
            vim.cmd('noautocmd botright new')
            vim.fn.termopen(cmd)
            vim.api.nvim_feedkeys(
              vim.api.nvim_replace_termcodes('<C-\\><C-n>G', true, false, true),
              'n',
              false
            )
            if c.link then
              vim.b.forge_check_url = c.link
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
      },
      picker_name = 'ci',
    })
  end

  if cached_checks then
    forge_mod.log(('checks picker (%s #%s, cached)'):format(f.labels.pr_one, num))
    open_picker(cached_checks)
    return
  end

  if f.checks_json_cmd then
    forge_mod.log_now(('fetching checks for %s #%s...'):format(f.labels.pr_one, num))
    vim.system(f:checks_json_cmd(num), { text = true }, function(result)
      vim.schedule(function()
        local ok, checks = pcall(vim.json.decode, result.stdout or '[]')
        if ok and checks then
          open_picker(checks)
        else
          vim.notify('[forge]: no checks found', vim.log.levels.INFO)
          vim.cmd.redraw()
        end
      end)
    end)
  else
    vim.notify('[forge]: structured checks not available for this forge', vim.log.levels.INFO)
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
            forge_mod.log_now('fetching CI/CD logs...')
            local s = run.status:lower()
            local cmd
            if s == 'in_progress' or s == 'running' or s == 'pending' or s == 'queued' then
              cmd = f:run_tail_cmd(run.id)
            elseif s == 'failure' or s == 'failed' then
              cmd = f:run_log_cmd(run.id, true)
            else
              cmd = f:run_log_cmd(run.id, false)
            end
            vim.cmd('noautocmd botright new')
            vim.fn.termopen(cmd)
            vim.api.nvim_feedkeys(
              vim.api.nvim_replace_termcodes('<C-\\><C-n>G', true, false, true),
              'n',
              false
            )
            if run.url ~= '' then
              vim.b.forge_run_url = run.url
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
            M.ci(f, branch)
          end,
        },
      },
      picker_name = 'ci',
    })
  end

  if f.list_runs_json_cmd then
    forge_mod.log_now('fetching CI runs...')
    vim.system(f:list_runs_json_cmd(branch), { text = true }, function(result)
      vim.schedule(function()
        local ok, runs = pcall(vim.json.decode, result.stdout or '[]')
        if ok and runs and #runs > 0 then
          open_ci_picker(runs)
        else
          vim.notify('[forge]: no CI runs found', vim.log.levels.INFO)
          vim.cmd.redraw()
        end
      end)
    end)
  elseif f.list_runs_cmd then
    vim.notify('[forge]: structured CI data not available for this forge', vim.log.levels.INFO)
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
    forge_mod.log_now(('fetching %s list (%s)...'):format(f.labels.pr, state))
    vim.system(f:list_pr_json_cmd(state), { text = true }, function(result)
      vim.schedule(function()
        local ok, prs = pcall(vim.json.decode, result.stdout or '[]')
        if ok and prs then
          forge_mod.set_list(cache_key, prs)
          open_pr_list(prs)
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
    forge_mod.log_now('fetching issue list (' .. state .. ')...')
    vim.system(f:list_issue_json_cmd(state), { text = true }, function(result)
      vim.schedule(function()
        local ok, issues = pcall(vim.json.decode, result.stdout or '[]')
        if ok and issues then
          forge_mod.set_list(cache_key, issues)
          open_issue_list(issues)
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

function M.git()
  vim.fn.system('git rev-parse --show-toplevel')
  if vim.v.shell_error ~= 0 then
    vim.notify('[forge]: not a git repository', vim.log.levels.WARN)
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

    add('Browse Remote', function()
      f:browse_root()
    end)

    if has_file then
      add('Open File', function()
        if branch == '' then
          vim.notify('[forge]: detached HEAD', vim.log.levels.WARN)
          return
        end
        f:browse(loc, branch)
      end)

      add('Yank Commit URL', function()
        f:yank_commit(loc)
      end)

      add('Yank Branch URL', function()
        f:yank_branch(loc)
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
