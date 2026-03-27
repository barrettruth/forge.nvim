---@param result vim.SystemCompleted
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

local fzf_args = (vim.env.FZF_DEFAULT_OPTS or '')
  :gsub('%-%-bind=[^%s]+', '')
  :gsub('%-%-color=[^%s]+', '')

local function make_header(bindings)
  local utils = require('fzf-lua.utils')
  local parts = {}
  for _, b in ipairs(bindings) do
    local key = utils.ansi_from_hl('FzfLuaHeaderBind', '<' .. b[1] .. '>')
    local desc = utils.ansi_from_hl('FzfLuaHeaderText', b[2])
    table.insert(parts, key .. ' to ' .. desc)
  end
  return ':: ' .. table.concat(parts, '|')
end

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
local function checks_picker(f, num, filter, cached_checks)
  filter = filter or 'all'
  local forge_mod = require('forge')

  local function open_picker(checks)
    local filtered = forge_mod.filter_checks(checks, filter)
    local lines = {}
    for i, c in ipairs(filtered) do
      local line = ('%d\t%s'):format(i, forge_mod.format_check(c))
      table.insert(lines, line)
    end

    local function get_check(selected)
      if not selected[1] then
        return nil
      end
      local idx = tonumber(selected[1]:match('^(%d+)'))
      return idx and filtered[idx] or nil
    end

    local labels = {
      all = 'all',
      fail = 'failed',
      pass = 'passed',
      pending = 'running',
    }

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('Checks (#%s, %s)> '):format(num, labels[filter] or filter),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--with-nth'] = '2..',
        ['--delimiter'] = '\t',
        ['--header'] = make_header({
          { 'enter', 'log' },
          { 'ctrl-x', 'browse' },
          { 'ctrl-f', 'failed' },
          { 'ctrl-p', 'passed' },
          { 'ctrl-n', 'running' },
          { 'ctrl-a', 'all' },
        }),
      },
      actions = {
        ['default'] = function(selected)
          local c = get_check(selected)
          if not c then
            return
          end
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
            vim.keymap.set('n', 'gx', function()
              vim.ui.open(vim.b.forge_check_url)
            end, {
              buffer = true,
              desc = 'open check in browser',
            })
          end
        end,
        ['ctrl-x'] = function(selected)
          local c = get_check(selected)
          if c and c.link then
            vim.ui.open(c.link)
          end
        end,
        ['ctrl-f'] = function()
          checks_picker(f, num, 'fail', checks)
        end,
        ['ctrl-p'] = function()
          checks_picker(f, num, 'pass', checks)
        end,
        ['ctrl-n'] = function()
          checks_picker(f, num, 'pending', checks)
        end,
        ['ctrl-a'] = function()
          checks_picker(f, num, 'all', checks)
        end,
        ['ctrl-r'] = function()
          checks_picker(f, num, filter)
        end,
      },
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
    require('fzf-lua').fzf_exec(f:checks_cmd(num), {
      fzf_args = fzf_args,
      prompt = ('Checks (#%s)> '):format(num),
      fzf_opts = { ['--ansi'] = '' },
      actions = {
        ['ctrl-r'] = function()
          checks_picker(f, num, filter)
        end,
      },
    })
  end
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
    table.insert(entries, label)
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

  require('fzf-lua').fzf_exec(entries, {
    fzf_args = fzf_args,
    prompt = ('%s #%s Actions> '):format(kind, num),
    fzf_opts = { ['--no-multi'] = '' },
    actions = {
      ['default'] = function(selected)
        if selected[1] and action_map[selected[1]] then
          action_map[selected[1]]()
        end
      end,
    },
  })
end

local function close_review_view()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match('^fugitive://') or name:match('^diffs://review:') then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(vim.cmd, 'diffoff!')
end

local review_augroup = vim.api.nvim_create_augroup('ForgeReview', { clear = true })

local function end_review()
  local review = require('forge').review
  review.base = nil
  review.mode = 'unified'
  pcall(vim.keymap.del, 'n', 's')
  vim.api.nvim_clear_autocmds({ group = review_augroup })
end

local function toggle_review_mode()
  local review = require('forge').review
  if not review.base then
    return
  end
  if review.mode == 'unified' then
    local ok, commands = pcall(require, 'diffs.commands')
    if not ok then
      return
    end
    local file = commands.review_file_at_line(vim.api.nvim_get_current_buf(), vim.fn.line('.'))
    review.mode = 'split'
    if file then
      vim.cmd('edit ' .. vim.fn.fnameescape(file))
      pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
  else
    local current_file = vim.fn.expand('%:.')
    close_review_view()
    review.mode = 'unified'
    local ok, commands = pcall(require, 'diffs.commands')
    if ok then
      commands.greview(review.base)
    end
    if current_file ~= '' then
      vim.fn.search('diff %-%-git a/' .. vim.pesc(current_file), 'cw')
    end
  end
end

local function start_review(base, mode)
  local review = require('forge').review
  review.base = base
  review.mode = mode or 'unified'
  vim.keymap.set('n', 's', toggle_review_mode, { desc = 'toggle review split/unified' })
  vim.api.nvim_clear_autocmds({ group = review_augroup })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = review_augroup,
    pattern = 'diffs://review:*',
    callback = end_review,
  })
end

---@param f forge.Forge
---@param num string
---@return table<string, function>
local function pr_actions(f, num)
  local kind = f.labels.pr_one
  local actions = {}

  actions['default'] = function()
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
  end

  actions['ctrl-x'] = function()
    f:view_web(f.kinds.pr, num)
  end

  actions['ctrl-w'] = function()
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
  end

  actions['ctrl-d'] = function()
    local forge_mod = require('forge')
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
          start_review(range)
          local ok, commands = pcall(require, 'diffs.commands')
          if ok then
            commands.greview(range, { repo_root = repo_root })
          end
          forge_mod.log(('review ready for %s #%s against %s'):format(kind, num, base))
        end)
      end)
    end)
  end

  actions['ctrl-t'] = function()
    checks_picker(f, num)
  end

  actions['ctrl-a'] = function()
    pr_manage_picker(f, num)
  end

  return actions
end

---@param kind 'issue'|'pr'
---@param state 'all'|'open'|'closed'
---@param f forge.Forge
local function forge_picker(kind, state, f)
  local cli_kind = f.kinds[kind]
  local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]

  local forge_mod = require('forge')
  local cache_key = forge_mod.list_key(kind, state)

  if kind == 'pr' then
    local pr_fields = f:pr_json_fields()

    local show_state = state ~= 'open'

    local function open_pr_list(prs)
      local lines = {}
      for _, pr in ipairs(prs) do
        table.insert(lines, forge_mod.format_pr(pr, pr_fields, show_state))
      end
      local function with_pr_num(selected, fn)
        local num = selected[1] and selected[1]:match('[#!](%d+)')
        if num then
          fn(num)
        end
      end

      require('fzf-lua').fzf_exec(lines, {
        fzf_args = fzf_args,
        prompt = ('%s (%s)> '):format(f.labels[kind], state),
        fzf_opts = {
          ['--ansi'] = '',
          ['--no-multi'] = '',
          ['--header'] = make_header({
            { 'enter', 'checkout' },
            { 'ctrl-d', 'diff' },
            { 'ctrl-w', 'worktree' },
            { 'ctrl-t', 'checks' },
            { 'ctrl-x', 'browse' },
            { 'ctrl-e', 'manage' },
            { 'ctrl-a', 'new' },
            { 'ctrl-o', 'toggle' },
          }),
        },
        actions = {
          ['default'] = function(selected)
            with_pr_num(selected, function(num)
              pr_actions(f, num)['default']()
            end)
          end,
          ['ctrl-x'] = function(selected)
            with_pr_num(selected, function(num)
              f:view_web(cli_kind, num)
            end)
          end,
          ['ctrl-d'] = function(selected)
            with_pr_num(selected, function(num)
              pr_actions(f, num)['ctrl-d']()
            end)
          end,
          ['ctrl-w'] = function(selected)
            with_pr_num(selected, function(num)
              pr_actions(f, num)['ctrl-w']()
            end)
          end,
          ['ctrl-t'] = function(selected)
            with_pr_num(selected, function(num)
              pr_actions(f, num)['ctrl-t']()
            end)
          end,
          ['ctrl-e'] = function(selected)
            with_pr_num(selected, function(num)
              pr_actions(f, num)['ctrl-a']()
            end)
          end,
          ['ctrl-a'] = function()
            forge_mod.create_pr()
          end,
          ['ctrl-o'] = function()
            forge_picker(kind, next_state, f)
          end,
          ['ctrl-r'] = function()
            forge_mod.clear_list(cache_key)
            forge_picker(kind, state, f)
          end,
        },
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
  else
    local issue_fields = f:issue_json_fields()
    local num_field = issue_fields.number
    local issue_show_state = state == 'all'

    local function open_issue_list(issues)
      table.sort(issues, function(a, b)
        return (a[num_field] or 0) > (b[num_field] or 0)
      end)
      local state_field = issue_fields.state
      local state_map = {}
      local lines = {}
      for _, issue in ipairs(issues) do
        local n = tostring(issue[num_field] or '')
        local s = (issue[state_field] or ''):lower()
        state_map[n] = s == 'open' or s == 'opened'
        table.insert(lines, forge_mod.format_issue(issue, issue_fields, issue_show_state))
      end
      local function with_issue_num(selected, fn)
        local num = selected[1] and selected[1]:match('[#!](%d+)')
        if num then
          fn(num)
        end
      end

      require('fzf-lua').fzf_exec(lines, {
        fzf_args = fzf_args,
        prompt = ('%s (%s)> '):format(f.labels[kind], state),
        fzf_opts = {
          ['--ansi'] = '',
          ['--no-multi'] = '',
          ['--header'] = make_header({
            { 'enter', 'browse' },
            { 'ctrl-s', 'close/reopen' },
            { 'ctrl-o', 'toggle' },
          }),
        },
        actions = {
          ['default'] = function(selected)
            with_issue_num(selected, function(num)
              f:view_web(cli_kind, num)
            end)
          end,
          ['ctrl-x'] = function(selected)
            with_issue_num(selected, function(num)
              f:view_web(cli_kind, num)
            end)
          end,
          ['ctrl-s'] = function(selected)
            with_issue_num(selected, function(num)
              issue_toggle_state(f, num, state_map[num] ~= false)
            end)
          end,
          ['ctrl-o'] = function()
            forge_picker(kind, next_state, f)
          end,
          ['ctrl-r'] = function()
            forge_mod.clear_list(cache_key)
            forge_picker(kind, state, f)
          end,
        },
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
end

local function ci_picker(f, branch)
  local forge_mod = require('forge')

  local function open_picker(runs)
    local normalized = {}
    for _, entry in ipairs(runs) do
      table.insert(normalized, f:normalize_run(entry))
    end

    local lines = {}
    for i, run in ipairs(normalized) do
      table.insert(lines, ('%d\t%s'):format(i, forge_mod.format_run(run)))
    end

    local function get_run(selected)
      if not selected[1] then
        return nil
      end
      local idx = tonumber(selected[1]:match('^(%d+)'))
      return idx and normalized[idx] or nil
    end

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('%s (%s)> '):format(f.labels.ci, branch or 'all'),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--with-nth'] = '2..',
        ['--delimiter'] = '\t',
        ['--header'] = make_header({
          { 'enter', 'log' },
          { 'ctrl-x', 'browse' },
          { 'ctrl-r', 'refresh' },
        }),
      },
      actions = {
        ['default'] = function(selected)
          local run = get_run(selected)
          if not run then
            return
          end
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
            vim.keymap.set('n', 'gx', function()
              vim.ui.open(vim.b.forge_run_url)
            end, {
              buffer = true,
              desc = 'open run in browser',
            })
          end
        end,
        ['ctrl-x'] = function(selected)
          local run = get_run(selected)
          if run and run.url ~= '' then
            vim.ui.open(run.url)
          end
        end,
        ['ctrl-r'] = function()
          ci_picker(f, branch)
        end,
      },
    })
  end

  if f.list_runs_json_cmd then
    forge_mod.log_now('fetching CI runs...')
    vim.system(f:list_runs_json_cmd(branch), { text = true }, function(result)
      vim.schedule(function()
        local ok, runs = pcall(vim.json.decode, result.stdout or '[]')
        if ok and runs and #runs > 0 then
          open_picker(runs)
        else
          vim.notify('[forge]: no CI runs found', vim.log.levels.INFO)
          vim.cmd.redraw()
        end
      end)
    end)
  elseif f.list_runs_cmd then
    require('fzf-lua').fzf_exec(f:list_runs_cmd(branch), {
      fzf_args = fzf_args,
      prompt = f.labels.ci .. '> ',
      fzf_opts = { ['--ansi'] = '' },
    })
  end
end

local git_picker = function()
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
  local actions = {}

  local function add(label, action)
    table.insert(items, label)
    actions[label] = action
  end

  if f then
    local pr_label = f.labels.pr_full
    local ci_label = f.labels.ci

    add(pr_label, function()
      forge_picker('pr', 'open', f)
    end)

    add('Issues', function()
      forge_picker('issue', 'all', f)
    end)

    add(ci_label, function()
      ci_picker(f, branch ~= '' and branch or nil)
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

  add('Commits', function()
    local log_cmd =
      'git log --color --pretty=format:"%C(yellow)%h%Creset %Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"'

    local hints = {
      { 'enter', 'checkout' },
      { 'ctrl-d', 'diff' },
      { 'ctrl-y', 'yank hash' },
    }
    if f then
      table.insert(hints, 3, { 'ctrl-x', 'browse' })
    end

    local function with_sha(selected, fn)
      local sha = selected[1] and selected[1]:match('%S+')
      if sha then
        fn(sha)
      end
    end

    require('fzf-lua').fzf_exec(log_cmd, {
      fzf_args = fzf_args,
      prompt = 'Commits> ',
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--preview'] = 'git show --color {1}',
        ['--header'] = make_header(hints),
      },
      actions = {
        ['default'] = function(selected)
          with_sha(selected, function(sha)
            forge_mod.log_now('checking out ' .. sha .. '...')
            vim.system({ 'git', 'checkout', sha }, { text = true }, function(result)
              vim.schedule(function()
                if result.code == 0 then
                  vim.notify(('[forge]: checked out %s (detached)'):format(sha))
                else
                  vim.notify(
                    '[forge]: ' .. cmd_error(result, 'checkout failed'),
                    vim.log.levels.ERROR
                  )
                end
                vim.cmd.redraw()
              end)
            end)
          end)
        end,
        ['ctrl-d'] = function(selected)
          with_sha(selected, function(sha)
            local range = sha .. '^..' .. sha
            start_review(range)
            local ok, commands = pcall(require, 'diffs.commands')
            if ok then
              commands.greview(range)
            end
            forge_mod.log_now('reviewing ' .. sha)
          end)
        end,
        ['ctrl-x'] = function(selected)
          with_sha(selected, function(sha)
            if f then
              f:browse_commit(sha)
            end
          end)
        end,
        ['ctrl-y'] = function(selected)
          with_sha(selected, function(sha)
            vim.fn.setreg('+', sha)
            vim.notify('[forge]: copied ' .. sha)
          end)
        end,
      },
    })
  end)

  add('Branches', function()
    local branch_actions = {
      ['ctrl-d'] = function(selected)
        if not selected[1] then
          return
        end
        local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
        if not br then
          return
        end
        start_review(br)
        local ok, commands = pcall(require, 'diffs.commands')
        if ok then
          commands.greview(br)
        end
        forge_mod.log_now('reviewing ' .. br)
      end,
    }
    if f then
      branch_actions['ctrl-x'] = function(selected)
        if not selected[1] then
          return
        end
        local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
        if br then
          f:browse_branch(br)
        end
      end
    end
    require('fzf-lua').git_branches({ actions = branch_actions })
  end)

  add('Worktrees', function()
    require('fzf-lua').git_worktrees()
  end)

  local prompt = f and (f.name:sub(1, 1):upper() .. f.name:sub(2)) .. '> ' or 'Git> '

  require('fzf-lua').fzf_exec(items, {
    fzf_args = fzf_args,
    prompt = prompt,
    actions = {
      ['default'] = function(selected)
        if selected[1] and actions[selected[1]] then
          actions[selected[1]]()
        end
      end,
    },
  })
end

vim.keymap.set({ 'n', 'v' }, '<c-g>', git_picker, { desc = 'forge git picker' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local items = info.loclist == 1 and vim.fn.getloclist(0) or vim.fn.getqflist()
    if #items == 0 then
      return
    end
    local bufname = vim.fn.bufname(items[1].bufnr)
    if not bufname:match('^diffs://') then
      return
    end
    vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
    vim.fn.matchadd('DiffDelete', [[\v-\d+]])
    vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
    vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
    vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
    vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
  end,
})

local function review_nav(nav_cmd)
  return function()
    local review = require('forge').review
    if review.base and review.mode == 'split' then
      close_review_view()
    end
    local wrap = {
      cnext = 'cfirst',
      cprev = 'clast',
      lnext = 'lfirst',
      lprev = 'llast',
    }
    if not pcall(vim.cmd, nav_cmd) then
      if not pcall(vim.cmd, wrap[nav_cmd]) then
        return
      end
    end
    if review.base and review.mode == 'split' then
      pcall(vim.cmd, 'Gvdiffsplit ' .. review.base)
    end
  end
end

vim.keymap.set('n', ']q', review_nav('cnext'), { desc = 'next quickfix entry' })
vim.keymap.set('n', '[q', review_nav('cprev'), { desc = 'prev quickfix entry' })
vim.keymap.set('n', ']l', review_nav('lnext'), { desc = 'next loclist entry' })
vim.keymap.set('n', '[l', review_nav('lprev'), { desc = 'prev loclist entry' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'fugitive',
  callback = function(args)
    local forge_mod = require('forge')
    local f = forge_mod.detect()
    if not f then
      return
    end
    local buf = args.buf
    vim.keymap.set('n', 'cpr', function()
      forge_mod.create_pr({ draft = false })
    end, { buffer = buf, desc = 'create PR' })
    vim.keymap.set('n', 'cpd', function()
      forge_mod.create_pr({ draft = true })
    end, { buffer = buf, desc = 'create draft PR' })
    vim.keymap.set('n', 'cpf', function()
      forge_mod.create_pr({ instant = true })
    end, { buffer = buf, desc = 'create PR (fill)' })
    vim.keymap.set('n', 'cpw', function()
      forge_mod.create_pr({ web = true })
    end, { buffer = buf, desc = 'create PR (web)' })
  end,
})
