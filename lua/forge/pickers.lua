local M = {}

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

local function build_actions(picker_name, action_defs)
  local cfg = require('forge').config()
  local pk = cfg.picker_keys
  if pk == false then
    pk = {}
  end
  local bindings = pk[picker_name] or {}
  local actions = {}
  local header_entries = {}
  for _, def in ipairs(action_defs) do
    local key = bindings[def.name]
    if key then
      actions[key] = def.fn
      if def.label then
        local display_key = key == 'default' and 'enter' or key:gsub('ctrl%-', 'ctrl-')
        table.insert(header_entries, { display_key, def.label })
      end
    end
  end
  return actions, make_header(header_entries)
end

local function terminal_open_key()
  local cfg = require('forge').config()
  if cfg.keys == false then
    return nil
  end
  return cfg.keys.terminal_open
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
local function pr_actions(f, num)
  local kind = f.labels.pr_one

  local defs = {
    {
      name = 'checkout',
      fn = function()
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
    },
    {
      name = 'browse',
      fn = function()
        f:view_web(f.kinds.pr, num)
      end,
    },
    {
      name = 'worktree',
      fn = function()
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
          vim.system(
            { 'git', 'worktree', 'add', wt_path, branch },
            { text = true },
            function(result)
              vim.schedule(function()
                if result.code == 0 then
                  vim.notify(('[forge]: worktree at %s'):format(wt_path))
                else
                  vim.notify(
                    '[forge]: ' .. cmd_error(result, 'worktree failed'),
                    vim.log.levels.ERROR
                  )
                end
                vim.cmd.redraw()
              end)
            end
          )
        end)
      end,
    },
    {
      name = 'diff',
      fn = function()
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
    },
    {
      name = 'checks',
      fn = function()
        M.checks(f, num)
      end,
    },
    {
      name = 'manage',
      fn = function()
        M.pr_manage(f, num)
      end,
    },
  }

  local name_to_fn = {}
  for _, def in ipairs(defs) do
    name_to_fn[def.name] = def.fn
  end

  local actions = build_actions('pr', defs)
  actions._by_name = name_to_fn
  return actions
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

---@param f forge.Forge
---@param num string
---@param filter string?
---@param cached_checks table[]?
function M.checks(f, num, filter, cached_checks)
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

    local check_actions, check_header = build_actions('checks', {
      {
        name = 'log',
        label = 'log',
        fn = function(selected)
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
          local to_key = terminal_open_key()
          if c.link and to_key then
            vim.b.forge_check_url = c.link
            vim.keymap.set('n', to_key, function()
              vim.ui.open(vim.b.forge_check_url)
            end, {
              buffer = true,
              desc = 'open check in browser',
            })
          end
        end,
      },
      {
        name = 'browse',
        label = 'browse',
        fn = function(selected)
          local c = get_check(selected)
          if c and c.link then
            vim.ui.open(c.link)
          end
        end,
      },
      {
        name = 'failed',
        label = 'failed',
        fn = function()
          M.checks(f, num, 'fail', checks)
        end,
      },
      {
        name = 'passed',
        label = 'passed',
        fn = function()
          M.checks(f, num, 'pass', checks)
        end,
      },
      {
        name = 'running',
        label = 'running',
        fn = function()
          M.checks(f, num, 'pending', checks)
        end,
      },
      {
        name = 'all',
        label = 'all',
        fn = function()
          M.checks(f, num, 'all', checks)
        end,
      },
    })

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('Checks (#%s, %s)> '):format(num, labels[filter] or filter),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--with-nth'] = '2..',
        ['--delimiter'] = '\t',
        ['--header'] = check_header,
      },
      actions = check_actions,
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
          M.checks(f, num, filter)
        end,
      },
    })
  end
end

---@param f forge.Forge
---@param branch string?
function M.ci(f, branch)
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

    local ci_actions, ci_header = build_actions('ci', {
      {
        name = 'log',
        label = 'log',
        fn = function(selected)
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
          local to_key = terminal_open_key()
          if run.url ~= '' and to_key then
            vim.b.forge_run_url = run.url
            vim.keymap.set('n', to_key, function()
              vim.ui.open(vim.b.forge_run_url)
            end, {
              buffer = true,
              desc = 'open run in browser',
            })
          end
        end,
      },
      {
        name = 'browse',
        label = 'browse',
        fn = function(selected)
          local run = get_run(selected)
          if run and run.url ~= '' then
            vim.ui.open(run.url)
          end
        end,
      },
      {
        name = 'refresh',
        label = 'refresh',
        fn = function()
          M.ci(f, branch)
        end,
      },
    })

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('%s (%s)> '):format(f.labels.ci, branch or 'all'),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--with-nth'] = '2..',
        ['--delimiter'] = '\t',
        ['--header'] = ci_header,
      },
      actions = ci_actions,
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

---@param f forge.Forge
function M.commits(f)
  local forge_mod = require('forge')
  local review = require('forge.review')
  local log_cmd =
    'git log --color --pretty=format:"%C(yellow)%h%Creset %Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"'

  local function with_sha(selected, fn)
    local sha = selected[1] and selected[1]:match('%S+')
    if sha then
      fn(sha)
    end
  end

  local defs = {
    {
      name = 'checkout',
      label = 'checkout',
      fn = function(selected)
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
    },
    {
      name = 'diff',
      label = 'diff',
      fn = function(selected)
        with_sha(selected, function(sha)
          local range = sha .. '^..' .. sha
          review.start(range)
          local ok, commands = pcall(require, 'diffs.commands')
          if ok then
            commands.greview(range)
          end
          forge_mod.log_now('reviewing ' .. sha)
        end)
      end,
    },
    {
      name = 'browse',
      label = 'browse',
      fn = function(selected)
        with_sha(selected, function(sha)
          if f then
            f:browse_commit(sha)
          end
        end)
      end,
    },
    {
      name = 'yank',
      label = 'yank hash',
      fn = function(selected)
        with_sha(selected, function(sha)
          vim.fn.setreg('+', sha)
          vim.notify('[forge]: copied ' .. sha)
        end)
      end,
    },
  }

  local commit_actions, commit_header = build_actions('commits', defs)

  require('fzf-lua').fzf_exec(log_cmd, {
    fzf_args = fzf_args,
    prompt = 'Commits> ',
    fzf_opts = {
      ['--ansi'] = '',
      ['--no-multi'] = '',
      ['--preview'] = 'git show --color {1}',
      ['--header'] = commit_header,
    },
    actions = commit_actions,
  })
end

---@param f forge.Forge?
function M.branches(f)
  local forge_mod = require('forge')
  local review = require('forge.review')

  local defs = {
    {
      name = 'diff',
      fn = function(selected)
        if not selected[1] then
          return
        end
        local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
        if not br then
          return
        end
        review.start(br)
        local ok, commands = pcall(require, 'diffs.commands')
        if ok then
          commands.greview(br)
        end
        forge_mod.log_now('reviewing ' .. br)
      end,
    },
    {
      name = 'browse',
      fn = function(selected)
        if not selected[1] then
          return
        end
        local br = selected[1]:match('%s-[%+%*]?%s+([^ ]+)')
        if br and f then
          f:browse_branch(br)
        end
      end,
    },
  }

  local branch_actions = build_actions('branches', defs)
  require('fzf-lua').git_branches({ actions = branch_actions })
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

    local list_actions, list_header = build_actions('pr', {
      {
        name = 'checkout',
        label = 'checkout',
        fn = function(selected)
          with_pr_num(selected, function(num)
            pr_actions(f, num)._by_name.checkout()
          end)
        end,
      },
      {
        name = 'diff',
        label = 'diff',
        fn = function(selected)
          with_pr_num(selected, function(num)
            pr_actions(f, num)._by_name.diff()
          end)
        end,
      },
      {
        name = 'worktree',
        label = 'worktree',
        fn = function(selected)
          with_pr_num(selected, function(num)
            pr_actions(f, num)._by_name.worktree()
          end)
        end,
      },
      {
        name = 'checks',
        label = 'checks',
        fn = function(selected)
          with_pr_num(selected, function(num)
            pr_actions(f, num)._by_name.checks()
          end)
        end,
      },
      {
        name = 'browse',
        label = 'browse',
        fn = function(selected)
          with_pr_num(selected, function(num)
            f:view_web(cli_kind, num)
          end)
        end,
      },
      {
        name = 'manage',
        label = 'manage',
        fn = function(selected)
          with_pr_num(selected, function(num)
            pr_actions(f, num)._by_name.manage()
          end)
        end,
      },
      {
        name = 'create',
        label = 'new',
        fn = function()
          forge_mod.create_pr()
        end,
      },
      {
        name = 'toggle',
        label = 'toggle',
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
    })

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('%s (%s)> '):format(f.labels.pr, state),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--header'] = list_header,
      },
      actions = list_actions,
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

    local issue_actions, issue_header = build_actions('issue', {
      {
        name = 'browse',
        label = 'browse',
        fn = function(selected)
          with_issue_num(selected, function(num)
            f:view_web(cli_kind, num)
          end)
        end,
      },
      {
        name = 'close_reopen',
        label = 'close/reopen',
        fn = function(selected)
          with_issue_num(selected, function(num)
            issue_toggle_state(f, num, state_map[num] ~= false)
          end)
        end,
      },
      {
        name = 'toggle',
        label = 'toggle',
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
    })

    require('fzf-lua').fzf_exec(lines, {
      fzf_args = fzf_args,
      prompt = ('%s (%s)> '):format(f.labels.issue, state),
      fzf_opts = {
        ['--ansi'] = '',
        ['--no-multi'] = '',
        ['--header'] = issue_header,
      },
      actions = issue_actions,
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
  return pr_actions(f, num)
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
  local actions = {}

  local function add(label, action)
    table.insert(items, label)
    actions[label] = action
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

  add('Commits', function()
    M.commits(f)
  end)

  add('Branches', function()
    M.branches(f)
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

return M
