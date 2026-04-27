vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local preload_modules = {
  'forge',
  'forge.logger',
  'forge.ops',
  'forge.pickers',
  'forge.resolve',
}

local loaded_modules = {
  'forge',
  'forge.cmd',
  'forge.logger',
  'forge.ops',
  'forge.pickers',
  'forge.resolve',
}

local function repo_scope(repo)
  return {
    kind = 'github',
    host = 'github.com',
    owner = 'owner',
    repo = repo,
    slug = 'owner/' .. repo,
    repo_arg = 'owner/' .. repo,
    web_url = 'https://github.com/owner/' .. repo,
  }
end

local function scope_key(scope)
  if type(scope) ~= 'table' then
    return ''
  end
  return table.concat({
    scope.kind or '',
    scope.host or '',
    scope.slug or '',
  }, '|')
end

local function scoped_id(id, suffix)
  if suffix ~= nil and suffix ~= '' then
    return id .. '|' .. suffix
  end
  return id
end

local function list_key(kind, id, scope)
  return kind .. ':' .. scoped_id(id, scope_key(scope))
end

local function use_named_current_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

local function completion(cmdline)
  return vim.fn.getcompletion(cmdline, 'cmdline')
end

describe(':Forge command', function()
  local captured
  local detected_forge_name
  local extra_review_adapters
  local old_preload
  local old_systemlist
  local old_system
  local old_ui_open

  before_each(function()
    extra_review_adapters = {}
    detected_forge_name = 'github'
    captured = {
      opens = {},
      ops_calls = {},
      ci_calls = {},
      branch_pr_calls = {},
      branch_pr_result = nil,
      branch_pr_error = nil,
      current_pr_calls = {},
      current_pr_result = nil,
      current_pr_error = nil,
      pr_action_num = nil,
      pr_action_scope = nil,
      warnings = {},
      closed_prs = {},
      closed_issues = {},
      browse_calls = {},
      opened_urls = {},
      system_calls = {},
      system_responses = {},
      lists = {},
      get_list_calls = {},
      pr_states = {},
      repo_infos = {},
    }
    old_preload = helpers.capture_preload(preload_modules)
    old_systemlist = vim.fn.systemlist
    old_system = vim.system
    old_ui_open = vim.ui.open

    captured.system_responses = {
      ['git remote get-url origin'] = helpers.command_result('git@github.com:owner/current.git\n'),
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote'] = helpers.command_result('origin\nupstream\n'),
      ['git branch --show-current'] = helpers.command_result('main\n'),
      ['git config branch.main.pushRemote'] = helpers.command_result('', 1),
      ['git rev-parse --abbrev-ref main@{upstream}'] = helpers.command_result('origin/main\n'),
      ['git rev-list --max-count=20 --abbrev-commit HEAD'] = helpers.command_result(
        'deadbee\nabc123\n'
      ),
    }
    vim.system = helpers.system_router({
      default = helpers.command_result('', 1),
      calls = captured.system_calls,
      responses = captured.system_responses,
    })
    vim.ui.open = function(url)
      table.insert(captured.opened_urls, url)
      return true
    end

    package.preload['forge.logger'] = function()
      return {
        warn = function(msg)
          table.insert(captured.warnings, msg)
        end,
        info = function() end,
        debug = function() end,
        error = function() end,
      }
    end

    package.preload['forge.resolve'] = function()
      return {
        branch_pr = function(opts, policy)
          table.insert(captured.branch_pr_calls, { opts = opts, policy = policy })
          if type(captured.branch_pr_result) == 'function' then
            return captured.branch_pr_result(opts, policy)
          end
          if type(captured.branch_pr_error) == 'function' then
            return nil, captured.branch_pr_error(opts, policy)
          end
          return captured.branch_pr_result, captured.branch_pr_error
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        detect = function()
          return {
            name = detected_forge_name,
            capabilities = {
              per_pr_checks = true,
              draft = true,
              ci_json = true,
            },
            labels = {
              pr_one = 'PR',
            },
            kinds = {
              pr = 'pr',
              issue = 'issue',
            },
            pr_fields = {
              number = 'number',
              title = 'title',
              state = 'state',
              is_draft = 'isDraft',
            },
            issue_fields = {
              number = 'number',
              title = 'title',
              state = 'state',
            },
            release_fields = {
              tag = 'tagName',
              title = 'name',
              is_draft = 'isDraft',
              is_prerelease = 'isPrerelease',
            },
            list_pr_json_cmd = function(_, state, limit, scope)
              local cmd = {
                'gh',
                'pr',
                'list',
                '--limit',
                tostring(limit),
                '--state',
                state,
                '--json',
                'number,title,state,isDraft',
              }
              local repo = scope and scope.repo_arg or nil
              if repo then
                table.insert(cmd, '-R')
                table.insert(cmd, repo)
              end
              return cmd
            end,
            list_issue_json_cmd = function(_, state, limit, scope)
              local cmd = {
                'gh',
                'issue',
                'list',
                '--limit',
                tostring(limit),
                '--state',
                state,
                '--json',
                'number,title,state',
              }
              local repo = scope and scope.repo_arg or nil
              if repo then
                table.insert(cmd, '-R')
                table.insert(cmd, repo)
              end
              return cmd
            end,
            list_runs_json_cmd = function(_, branch, scope, limit)
              local cmd = {
                'gh',
                'run',
                'list',
                '--json',
                'databaseId,name,headBranch,status,conclusion,url',
                '--limit',
                tostring(limit),
              }
              local repo = scope and scope.repo_arg or nil
              if repo then
                table.insert(cmd, '-R')
                table.insert(cmd, repo)
              end
              if branch then
                table.insert(cmd, '--branch')
                table.insert(cmd, branch)
              end
              return cmd
            end,
            list_releases_json_cmd = function(_, scope, limit)
              local cmd = {
                'gh',
                'release',
                'list',
                '--json',
                'tagName,name,isDraft,isPrerelease',
                '--limit',
                tostring(limit),
              }
              local repo = scope and scope.repo_arg or nil
              if repo then
                table.insert(cmd, '-R')
                table.insert(cmd, repo)
              end
              return cmd
            end,
            normalize_run = function(_, entry)
              local status = entry.status or ''
              if status == 'completed' then
                status = entry.conclusion or 'unknown'
              end
              return {
                id = tostring(entry.databaseId or ''),
                name = entry.name or '',
                branch = entry.headBranch or '',
                status = status,
                url = entry.url or '',
              }
            end,
            view_web = function(_, kind, num, scope)
              captured.view_web = {
                kind = kind,
                num = num,
                scope = scope,
              }
            end,
            browse = function(_, loc, branch, scope)
              table.insert(captured.browse_calls, {
                loc = loc,
                branch = branch,
                scope = scope,
              })
            end,
            browse_release = function(_, tag, scope)
              captured.release_browse = {
                tag = tag,
                scope = scope,
              }
            end,
          }
        end,
        current_context = function()
          return {
            root = '/repo',
            branch = 'main',
            head = 'abc123',
          }
        end,
        current_scope = function()
          return repo_scope('current')
        end,
        config = function()
          return {
            targets = {
              aliases = {
                mirror = 'remote:upstream',
                work = 'github.com/owner/work',
              },
              ci = {
                repo = 'current',
              },
            },
          }
        end,
        create_pr = function(opts)
          captured.create_pr = opts
        end,
        ci = function(opts)
          table.insert(captured.ci_calls, opts or {})
        end,
        current_pr = function(opts)
          table.insert(captured.current_pr_calls, opts)
          return captured.current_pr_result, captured.current_pr_error
        end,
        create_issue = function(opts)
          captured.create_issue = opts
        end,
        clear_cache = function()
          captured.cleared = true
        end,
        clear_list_kind = function(kind)
          captured.cleared_kinds = captured.cleared_kinds or {}
          table.insert(captured.cleared_kinds, kind)
        end,
        scope_key = scope_key,
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          table.insert(captured.get_list_calls, key)
          return captured.lists[key]
        end,
        set_list = function(key, value)
          captured.lists[key] = value
        end,
        pr_state = function(_, num, scope)
          return captured.pr_states[(scope and scope.slug or 'owner/current') .. '#' .. num] or {}
        end,
        repo_info = function(_, scope)
          return captured.repo_infos[scope and scope.slug or 'owner/current']
            or { permission = 'WRITE', merge_methods = { 'merge', 'squash', 'rebase' } }
        end,
        file_loc = function(range)
          local name = vim.api.nvim_buf_get_name(0)
          if name:match('^%w[%w+.-]*://') then
            return ''
          end
          if type(range) == 'table' and range.start_line and range.end_line then
            if range.start_line == range.end_line then
              return ('lua/forge/init.lua:%d'):format(range.start_line)
            end
            return ('lua/forge/init.lua:%d-%d'):format(range.start_line, range.end_line)
          end
          return 'lua/forge/init.lua'
        end,
        remote_web_url = function(scope)
          return (scope or repo_scope('current')).web_url
        end,
        open = function(route, opts)
          table.insert(captured.opens, { route = route, opts = opts })
        end,
        template_slugs = function()
          return { 'bug', 'feature' }
        end,
        review_adapter_names = function()
          local adapters = { 'browse', 'checkout', 'codediff', 'diffs', 'diffview', 'worktree' }
          for _, name in ipairs(extra_review_adapters) do
            adapters[#adapters + 1] = name
          end
          return adapters
        end,
      }
    end

    package.preload['forge.ops'] = function()
      return {
        pr_edit = function(pr)
          table.insert(captured.ops_calls, { name = 'pr_edit', pr = pr })
        end,
        pr_review = function(_, pr, opts)
          table.insert(captured.ops_calls, { name = 'pr_review', pr = pr, opts = opts or {} })
        end,
        pr_ci = function(_, pr, opts)
          table.insert(captured.ops_calls, { name = 'pr_ci', pr = pr, opts = opts })
        end,
        pr_approve = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_approve', pr = pr })
        end,
        pr_merge = function(_, pr, method)
          table.insert(captured.ops_calls, { name = 'pr_merge', pr = pr, method = method })
        end,
        pr_toggle_draft = function(_, pr, is_draft)
          table.insert(
            captured.ops_calls,
            { name = 'pr_toggle_draft', pr = pr, is_draft = is_draft }
          )
        end,
        pr_close = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_close', pr = pr })
        end,
        pr_reopen = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_reopen', pr = pr })
        end,
        pr_browse = function(f, pr)
          table.insert(captured.ops_calls, { name = 'pr_browse', pr = pr })
          f:view_web(f.kinds.pr, pr.num, pr.scope)
        end,
        browse_subject = function(f, ref)
          table.insert(captured.ops_calls, { name = 'browse_subject', ref = ref })
          if f.browse_subject then
            f:browse_subject(ref.num, ref.scope)
          end
        end,
        issue_edit = function(issue)
          table.insert(captured.ops_calls, { name = 'issue_edit', issue = issue })
        end,
        issue_browse = function(f, issue)
          table.insert(captured.ops_calls, { name = 'issue_browse', issue = issue })
          f:view_web(f.kinds.issue, issue.num, issue.scope)
        end,
        issue_close = function(_, issue)
          table.insert(captured.ops_calls, { name = 'issue_close', issue = issue })
        end,
        issue_reopen = function(_, issue)
          table.insert(captured.ops_calls, { name = 'issue_reopen', issue = issue })
        end,
        ci_log = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_log', run = run })
        end,
        ci_open = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_open', run = run })
        end,
        ci_watch = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_watch', run = run })
        end,
        ci_browse = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_browse', run = run })
        end,
        release_browse = function(f, release)
          table.insert(captured.ops_calls, { name = 'release_browse', release = release })
          f:browse_release(release.tag, release.scope)
        end,
        release_delete = function(_, release, opts)
          table.insert(
            captured.ops_calls,
            { name = 'release_delete', release = release, opts = opts }
          )
        end,
        list_browse = function(_, kind, opts)
          table.insert(captured.ops_calls, { name = 'list_browse', kind = kind, opts = opts })
        end,
        browse_repo = function(opts)
          table.insert(captured.ops_calls, { name = 'browse_repo', opts = opts })
          vim.ui.open(require('forge').remote_web_url(opts and opts.scope or nil))
          return true
        end,
        browse_location = function(f, location, scope)
          table.insert(
            captured.ops_calls,
            { name = 'browse_location', location = location, scope = scope }
          )
          f:browse(location.path .. ':10-20', location.rev.rev, scope)
          return true
        end,
        browse_file = function(f, file_loc, branch, scope)
          if vim.trim(file_loc or '') == '' or vim.trim(branch or '') == '' then
            return false
          end
          table.insert(captured.ops_calls, {
            name = 'browse_file',
            file_loc = file_loc,
            branch = branch,
            scope = scope,
          })
          f:browse(file_loc, branch, scope)
          return true
        end,
      }
    end

    package.preload['forge.pickers'] = function()
      return {
        pr_actions = function(_, pr)
          local ref = type(pr) == 'table' and pr or { num = pr }
          captured.pr_action_num = ref.num
          captured.pr_action_scope = ref.scope
          return {
            checkout = function() end,
            worktree = function() end,
          }
        end,
        checks = function() end,
        ci = function() end,
        pr_close = function(_, num)
          table.insert(captured.closed_prs, num)
        end,
        pr_reopen = function() end,
        issue_close = function(_, num)
          table.insert(captured.closed_issues, num)
        end,
        issue_reopen = function() end,
      }
    end

    vim.fn.systemlist = function(cmd)
      if cmd == 'git for-each-ref --format=%(refname:short) refs/heads refs/tags' then
        return { 'main', 'feature', 'v1.0.0' }
      end
      return old_systemlist(cmd)
    end

    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end

    helpers.clear_loaded(loaded_modules)

    dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.systemlist = old_systemlist
    vim.ui.open = old_ui_open
    helpers.restore_preload(old_preload)
    helpers.clear_loaded(loaded_modules)
    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end
  end)

  it('warns instead of opening interactive surfaces for missing or unsupported commands', function()
    vim.cmd('Forge')
    vim.cmd('Forge pr checkout 42')
    vim.cmd('Forge pr worktree 42')
    vim.cmd('Forge release')
    vim.cmd('Forge branches')
    vim.cmd('Forge commits feature')
    vim.cmd('Forge worktrees')

    assert.same({
      'missing command',
      'unknown pr action: checkout',
      'unknown pr action: worktree',
      'missing action',
      'unknown command: branches',
      'unknown command: commits',
      'unknown command: worktrees',
    }, captured.warnings)
    assert.is_nil(captured.opens[1])
    assert.is_nil(captured.ops_calls[1])
  end)

  it('warns when bare :Forge ci would enter interactive current-branch history', function()
    vim.cmd('Forge ci')
    vim.cmd('Forge ci repo=upstream')

    assert.same({
      "current-branch CI runs are not available from :Forge; use require('forge').ci()",
      "current-branch CI runs are not available from :Forge; use require('forge').ci()",
    }, captured.warnings)
    assert.same({}, captured.ci_calls)
    assert.same({}, captured.ops_calls)
  end)

  it('dispatches implicit current-PR commands through forge.current_pr', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr')
    vim.cmd('Forge review adapter=worktree')

    assert.equals(2, #captured.current_pr_calls)
    assert.equals('github', captured.current_pr_calls[1].forge.name)
    assert.is_nil(captured.current_pr_calls[1].repo)
    assert.is_nil(captured.current_pr_calls[1].head)
    assert.equals('github', captured.current_pr_calls[2].forge.name)
    assert.same({
      name = 'pr_edit',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({
      name = 'pr_review',
      pr = { num = '42', scope = repo_scope('upstream') },
      opts = { adapter = 'worktree' },
    }, captured.ops_calls[2])
    assert.same({}, captured.branch_pr_calls)
    assert.same({}, captured.warnings)
  end)

  it('warns when :Forge pr ci would enter interactive PR checks', function()
    captured.branch_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr ci')

    assert.same({
      "PR checks are not available from :Forge; use require('forge').pr_ci()",
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
    assert.same({}, captured.branch_pr_calls)
  end)

  it('passes repo= and head= disambiguation through implicit current-PR commands', function()
    captured.current_pr_result = {
      num = '57',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr repo=upstream head=origin@topic')
    vim.cmd('Forge review repo=upstream head=origin@topic adapter=worktree')

    assert.equals(2, #captured.current_pr_calls)
    for _, call in ipairs(captured.current_pr_calls) do
      assert.equals('github', call.forge.name)
      assert.equals('repo', call.repo.kind)
      assert.equals('owner/upstream', call.repo.slug)
      assert.equals('rev', call.head.kind)
      assert.equals('topic', call.head.rev)
      assert.equals('owner/current', call.head.repo.slug)
    end

    assert.same({
      name = 'pr_edit',
      pr = { num = '57', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({
      name = 'pr_review',
      pr = { num = '57', scope = repo_scope('upstream') },
      opts = { adapter = 'worktree' },
    }, captured.ops_calls[2])
  end)

  it('warns for :Forge pr ci even when repo= and head= are provided', function()
    captured.branch_pr_result = {
      num = '57',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr ci repo=upstream head=origin@topic')

    assert.same({
      "PR checks are not available from :Forge; use require('forge').pr_ci()",
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
    assert.same({}, captured.branch_pr_calls)
  end)

  it('dispatches implicit pr reopen through closed-only branch lookup', function()
    captured.branch_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr reopen')

    assert.equals(1, #captured.branch_pr_calls)
    assert.equals('github', captured.branch_pr_calls[1].opts.forge.name)
    assert.is_nil(captured.branch_pr_calls[1].opts.repo)
    assert.is_nil(captured.branch_pr_calls[1].opts.head)
    assert.same({
      searches = {
        { 'closed' },
      },
    }, captured.branch_pr_calls[1].policy)
    assert.same({
      name = 'pr_reopen',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({}, captured.warnings)
  end)

  it('passes repo= and head= disambiguation through implicit pr reopen branch lookup', function()
    captured.branch_pr_result = {
      num = '57',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr reopen repo=upstream head=origin@topic')

    assert.equals(1, #captured.branch_pr_calls)
    assert.equals('github', captured.branch_pr_calls[1].opts.forge.name)
    assert.equals('repo', captured.branch_pr_calls[1].opts.repo.kind)
    assert.equals('owner/upstream', captured.branch_pr_calls[1].opts.repo.slug)
    assert.equals('rev', captured.branch_pr_calls[1].opts.head.kind)
    assert.equals('topic', captured.branch_pr_calls[1].opts.head.rev)
    assert.equals('owner/current', captured.branch_pr_calls[1].opts.head.repo.slug)
    assert.same({
      name = 'pr_reopen',
      pr = { num = '57', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
  end)

  it('dispatches implicit current-open-PR mutators through forge.current_pr', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr approve')
    vim.cmd('Forge pr merge')
    vim.cmd('Forge pr close')
    vim.cmd('Forge pr draft')
    vim.cmd('Forge pr ready')

    assert.equals(5, #captured.current_pr_calls)
    for _, call in ipairs(captured.current_pr_calls) do
      assert.equals('github', call.forge.name)
      assert.is_nil(call.repo)
      assert.is_nil(call.head)
    end

    assert.same({
      name = 'pr_approve',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({
      name = 'pr_merge',
      pr = { num = '42', scope = repo_scope('upstream') },
      method = nil,
    }, captured.ops_calls[2])
    assert.same({
      name = 'pr_close',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[3])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '42', scope = repo_scope('upstream') },
      is_draft = false,
    }, captured.ops_calls[4])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '42', scope = repo_scope('upstream') },
      is_draft = true,
    }, captured.ops_calls[5])
    assert.same({}, captured.warnings)
  end)

  it('passes repo= and head= disambiguation through implicit current-open-PR mutators', function()
    captured.current_pr_result = {
      num = '57',
      scope = repo_scope('upstream'),
    }

    vim.cmd('Forge pr approve repo=upstream head=origin@topic')
    vim.cmd('Forge pr merge repo=upstream head=origin@topic method=squash')
    vim.cmd('Forge pr close repo=upstream head=origin@topic')
    vim.cmd('Forge pr draft repo=upstream head=origin@topic')
    vim.cmd('Forge pr ready repo=upstream head=origin@topic')

    for _, call in ipairs(captured.current_pr_calls) do
      assert.equals('github', call.forge.name)
      assert.equals('repo', call.repo.kind)
      assert.equals('owner/upstream', call.repo.slug)
      assert.equals('rev', call.head.kind)
      assert.equals('topic', call.head.rev)
      assert.equals('owner/current', call.head.repo.slug)
    end

    assert.same({
      name = 'pr_approve',
      pr = { num = '57', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({
      name = 'pr_merge',
      pr = { num = '57', scope = repo_scope('upstream') },
      method = 'squash',
    }, captured.ops_calls[2])
    assert.same({
      name = 'pr_close',
      pr = { num = '57', scope = repo_scope('upstream') },
    }, captured.ops_calls[3])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '57', scope = repo_scope('upstream') },
      is_draft = false,
    }, captured.ops_calls[4])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '57', scope = repo_scope('upstream') },
      is_draft = true,
    }, captured.ops_calls[5])
  end)

  it('warns cleanly when implicit current-PR commands find no matching PR', function()
    vim.cmd('Forge pr')
    vim.cmd('Forge review')

    assert.same({
      'no open PR found for this branch',
      'no open PR found for this branch',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('warns cleanly when implicit pr ci finds no matching branch PR', function()
    vim.cmd('Forge pr ci')

    assert.same({
      "PR checks are not available from :Forge; use require('forge').pr_ci()",
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
    assert.same({}, captured.branch_pr_calls)
  end)

  it('warns cleanly when implicit pr reopen finds no matching branch PR', function()
    vim.cmd('Forge pr reopen')

    assert.same({
      'no reopenable PR found for this branch',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('warns cleanly when implicit current-open-PR mutators find no matching PR', function()
    vim.cmd('Forge pr approve')
    vim.cmd('Forge pr merge')
    vim.cmd('Forge pr close')
    vim.cmd('Forge pr draft')
    vim.cmd('Forge pr ready')

    assert.same({
      'no open PR found for this branch',
      'no open PR found for this branch',
      'no open PR found for this branch',
      'no open PR found for this branch',
      'no open PR found for this branch',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('surfaces resolver errors from implicit current-PR commands', function()
    captured.current_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    vim.cmd('Forge pr')

    assert.same({
      'multiple PRs match head owner/current@main; pass repo= or head=',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('does not consult the resolver for unsupported implicit pr ci flows', function()
    captured.branch_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    vim.cmd('Forge pr ci')

    assert.same({
      "PR checks are not available from :Forge; use require('forge').pr_ci()",
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
    assert.same({}, captured.branch_pr_calls)
  end)

  it('surfaces resolver errors from implicit pr reopen branch lookup', function()
    captured.branch_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    vim.cmd('Forge pr reopen')

    assert.same({
      'multiple PRs match head owner/current@main; pass repo= or head=',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('surfaces resolver errors from implicit current-open-PR mutators', function()
    captured.current_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    vim.cmd('Forge pr merge')

    assert.same({
      'multiple PRs match head owner/current@main; pass repo= or head=',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('allows :Forge to be followed by a bar command', function()
    vim.g.forge_bar_works = nil

    vim.cmd('Forge clear | let g:forge_bar_works = 1')

    assert.is_true(captured.cleared)
    assert.equal(1, vim.g.forge_bar_works)
  end)

  it('uses explicit browse defaults for omitted targets', function()
    vim.cmd('Forge browse')

    assert.same({
      loc = 'lua/forge/init.lua',
      branch = 'main',
      scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'current',
        slug = 'owner/current',
        repo_arg = 'owner/current',
        web_url = 'https://github.com/owner/current',
      },
    }, captured.browse_calls[1])
  end)

  it('uses repo browsing when special buffers have no file location', function()
    use_named_current_buf('canola://issue/123')

    vim.cmd('Forge browse')

    assert.same({
      name = 'browse_repo',
      opts = {
        scope = {
          kind = 'github',
          host = 'github.com',
          owner = 'owner',
          repo = 'current',
          slug = 'owner/current',
          repo_arg = 'owner/current',
          web_url = 'https://github.com/owner/current',
        },
      },
    }, captured.ops_calls[1])
    assert.same({ 'https://github.com/owner/current' }, captured.opened_urls)
  end)

  it('uses explicit branch browsing when special buffers have no file location', function()
    use_named_current_buf('canola://issue/123')

    vim.cmd('Forge browse branch=main')

    assert.equals('browse.branch', captured.opens[1].route)
    assert.equals('main', captured.opens[1].opts.branch)
    assert.same(repo_scope('current'), captured.opens[1].opts.scope)
  end)

  it('dispatches explicit commit browsing through forge.open', function()
    vim.cmd('Forge browse commit=abc1234')

    assert.equals('browse.commit', captured.opens[1].route)
    assert.equals('abc1234', captured.opens[1].opts.commit)
    assert.same(repo_scope('current'), captured.opens[1].opts.scope)
  end)

  it('dispatches explicit location browsing through ops.browse_location', function()
    vim.cmd('Forge browse target=upstream@main:lua/forge/init.lua#L10-L20')

    assert.equals('browse_location', captured.ops_calls[1].name)
    assert.equals('lua/forge/init.lua', captured.ops_calls[1].location.path)
    assert.same({ start_line = 10, end_line = 20 }, captured.ops_calls[1].location.range)
    assert.equals('main', captured.ops_calls[1].location.rev.rev)
    assert.same(repo_scope('upstream'), captured.ops_calls[1].scope)
    assert.same({
      loc = 'lua/forge/init.lua:10-20',
      branch = 'main',
      scope = repo_scope('upstream'),
    }, captured.browse_calls[1])
  end)

  it('dispatches argless kind browse through ops.list_browse', function()
    vim.cmd('Forge issue browse')
    vim.cmd('Forge ci browse')
    vim.cmd('Forge release browse')

    assert.same({ name = 'list_browse', kind = 'issue', opts = {} }, captured.ops_calls[1])
    assert.same({ name = 'list_browse', kind = 'ci', opts = {} }, captured.ops_calls[2])
    assert.same({ name = 'list_browse', kind = 'release', opts = {} }, captured.ops_calls[3])
  end)

  it('keeps argful kind browse routed to entity-scoped ops helpers', function()
    vim.cmd('Forge issue browse 7')
    vim.cmd('Forge pr browse 42')
    vim.cmd('Forge ci browse 99')
    vim.cmd('Forge release browse v1.2.3')

    assert.equals('issue_browse', captured.ops_calls[1].name)
    assert.equals('7', captured.ops_calls[1].issue.num)
    assert.equals('pr_browse', captured.ops_calls[2].name)
    assert.equals('42', captured.ops_calls[2].pr.num)
    assert.equals('ci_browse', captured.ops_calls[3].name)
    assert.equals('99', captured.ops_calls[3].run.id)
    assert.equals('release_browse', captured.ops_calls[4].name)
    assert.equals('v1.2.3', captured.ops_calls[4].release.tag)
  end)

  it('routes :Forge browse {num} through ops.browse_subject', function()
    vim.cmd('Forge browse 42')
    vim.cmd('Forge browse 7 repo=upstream')

    assert.equals('browse_subject', captured.ops_calls[1].name)
    assert.equals('42', captured.ops_calls[1].ref.num)
    assert.same(repo_scope('current'), captured.ops_calls[1].ref.scope)

    assert.equals('browse_subject', captured.ops_calls[2].name)
    assert.equals('7', captured.ops_calls[2].ref.num)
    assert.same(repo_scope('upstream'), captured.ops_calls[2].ref.scope)
  end)

  it('dispatches review through forge.ops with adapter overrides', function()
    vim.cmd('Forge review 42')
    vim.cmd('Forge review 42 adapter=worktree repo=upstream')

    assert.same({
      name = 'pr_review',
      pr = { num = '42', scope = nil },
      opts = {},
    }, captured.ops_calls[1])
    assert.same({
      name = 'pr_review',
      pr = { num = '42', scope = repo_scope('upstream') },
      opts = { adapter = 'worktree' },
    }, captured.ops_calls[2])
  end)

  it('keeps explicit PR open direct while rejecting explicit PR checks from Ex', function()
    vim.cmd('Forge pr open 42')
    vim.cmd('Forge pr ci 42 repo=upstream')

    assert.same({
      name = 'pr_edit',
      pr = { num = '42', scope = nil },
    }, captured.ops_calls[1])
    assert.same({
      "PR checks are not available from :Forge; use require('forge').pr_ci()",
    }, captured.warnings)
  end)

  it('keeps explicit PR reopen routed directly through forge.ops', function()
    vim.cmd('Forge pr reopen 42 repo=upstream')

    assert.same({
      name = 'pr_reopen',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({}, captured.branch_pr_calls)
  end)

  it('passes ex ranges through browse file resolution', function()
    assert.equals('.', vim.api.nvim_get_commands({ builtin = false }).Forge.range)
    vim.api.nvim_buf_set_name(0, '/repo/lua/forge/init.lua')

    require('forge.cmd').run({
      args = 'browse',
      line1 = 2,
      line2 = 4,
      range = 2,
    })

    assert.same({
      loc = 'lua/forge/init.lua:2-4',
      branch = 'main',
      scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'current',
        slug = 'owner/current',
        repo_arg = 'owner/current',
        web_url = 'https://github.com/owner/current',
      },
    }, captured.browse_calls[1])
  end)

  it('dispatches normalized create and clear commands through the command layer', function()
    vim.cmd('Forge pr create draft fill web')
    vim.cmd('Forge issue create blank template=bug')
    vim.cmd('Forge clear')

    assert.same({
      draft = true,
      instant = true,
      web = true,
      scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'upstream',
        slug = 'owner/upstream',
        repo_arg = 'owner/upstream',
        web_url = 'https://github.com/owner/upstream',
      },
      head_branch = 'main',
      head_scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'current',
        slug = 'owner/current',
        repo_arg = 'owner/current',
        web_url = 'https://github.com/owner/current',
      },
      base_branch = nil,
      base_scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'upstream',
        slug = 'owner/upstream',
        repo_arg = 'owner/upstream',
        web_url = 'https://github.com/owner/upstream',
      },
    }, captured.create_pr)
    assert.same({ web = false, blank = true, template = 'bug', scope = nil }, captured.create_issue)
    assert.is_true(captured.cleared)
  end)

  it('passes explicit create head and base targets through the command layer', function()
    vim.cmd('Forge pr create head=origin@topic base=upstream@release')

    assert.same({
      draft = false,
      instant = false,
      web = false,
      scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'upstream',
        slug = 'owner/upstream',
        repo_arg = 'owner/upstream',
        web_url = 'https://github.com/owner/upstream',
      },
      head_branch = 'topic',
      head_scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'current',
        slug = 'owner/current',
        repo_arg = 'owner/current',
        web_url = 'https://github.com/owner/current',
      },
      base_branch = 'release',
      base_scope = {
        kind = 'github',
        host = 'github.com',
        owner = 'owner',
        repo = 'upstream',
        slug = 'owner/upstream',
        repo_arg = 'owner/upstream',
        web_url = 'https://github.com/owner/upstream',
      },
    }, captured.create_pr)
  end)

  it('dispatches issue edit through forge.ops with scoped parity', function()
    vim.cmd('Forge issue edit 174 repo=upstream')

    assert.same({
      name = 'issue_edit',
      issue = {
        num = '174',
        scope = {
          kind = 'github',
          host = 'github.com',
          owner = 'owner',
          repo = 'upstream',
          slug = 'owner/upstream',
          repo_arg = 'owner/upstream',
          web_url = 'https://github.com/owner/upstream',
        },
      },
    }, captured.ops_calls[1])
  end)

  it('rejects explicit list verbs with no picker dispatch side effects', function()
    vim.cmd('Forge pr list')
    vim.cmd('Forge issue list')
    vim.cmd('Forge ci list')
    vim.cmd('Forge release list')

    assert.same({
      'unknown pr action: list',
      'unknown issue action: list',
      'unknown action: list',
      'unknown release action: list',
    }, captured.warnings)
    assert.is_nil(captured.opens[1])
  end)

  it('dispatches PR management parity subcommands through forge.ops', function()
    for _, case in ipairs({
      {
        cmd = 'Forge pr approve 42',
        expected = { name = 'pr_approve', pr = { num = '42', scope = nil } },
      },
      {
        cmd = 'Forge pr merge 42 repo=upstream',
        expected = {
          name = 'pr_merge',
          pr = { num = '42', scope = repo_scope('upstream') },
          method = nil,
        },
      },
      {
        cmd = 'Forge pr draft 42',
        expected = { name = 'pr_toggle_draft', pr = { num = '42', scope = nil }, is_draft = false },
      },
      {
        cmd = 'Forge pr ready 42',
        expected = { name = 'pr_toggle_draft', pr = { num = '42', scope = nil }, is_draft = true },
      },
    }) do
      vim.cmd(case.cmd)
    end

    for index, case in ipairs({
      {
        expected = { name = 'pr_approve', pr = { num = '42', scope = nil } },
      },
      {
        expected = {
          name = 'pr_merge',
          pr = { num = '42', scope = repo_scope('upstream') },
          method = nil,
        },
      },
      {
        expected = { name = 'pr_toggle_draft', pr = { num = '42', scope = nil }, is_draft = false },
      },
      {
        expected = { name = 'pr_toggle_draft', pr = { num = '42', scope = nil }, is_draft = true },
      },
    }) do
      assert.same(case.expected, captured.ops_calls[index])
    end
  end)

  it('passes through an explicit merge method when provided', function()
    vim.cmd('Forge pr merge 42 method=squash')

    assert.same({
      name = 'pr_merge',
      pr = { num = '42', scope = nil },
      method = 'squash',
    }, captured.ops_calls[1])
  end)

  it('dispatches CI open through forge.ops', function()
    vim.cmd('Forge ci open 123 repo=upstream')

    assert.same({
      name = 'ci_open',
      run = {
        id = '123',
        scope = {
          kind = 'github',
          host = 'github.com',
          owner = 'owner',
          repo = 'upstream',
          slug = 'owner/upstream',
          repo_arg = 'owner/upstream',
          web_url = 'https://github.com/owner/upstream',
        },
      },
    }, captured.ops_calls[1])
  end)

  it('keeps GitLab family aliases unavailable outside GitLab surfaces', function()
    vim.cmd('Forge mr edit 42')
    vim.cmd('Forge pipeline browse 123')

    assert.same({
      'unknown command: mr',
      'unknown command: pipeline',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('dispatches GitLab family aliases through the canonical command families', function()
    detected_forge_name = 'gitlab'

    vim.cmd('Forge mr edit 42')
    vim.cmd('Forge pipeline browse 123')

    assert.same({
      {
        name = 'pr_edit',
        pr = {
          num = '42',
          scope = nil,
        },
      },
      {
        name = 'ci_browse',
        run = {
          id = '123',
          scope = nil,
        },
      },
    }, captured.ops_calls)
    assert.same({}, captured.warnings)
  end)

  it('dispatches refresh verbs to forge.clear_list_kind per family', function()
    vim.cmd('Forge pr refresh')
    vim.cmd('Forge issue refresh')
    vim.cmd('Forge ci refresh')
    vim.cmd('Forge release refresh')

    assert.same({ 'pr', 'issue', 'ci', 'release' }, captured.cleared_kinds)
    assert.is_nil(captured.cleared)
  end)

  it('covers the stock completion slot matrix explicitly', function()
    local scope = repo_scope('current')
    captured.lists[list_key('release', 'list', scope)] = {
      { tagName = 'v1.0.0', name = 'First' },
      { tagName = 'v1.1.0', name = 'Second' },
    }

    for _, case in ipairs({
      {
        cmdline = 'Forge ',
        expected = { 'pr', 'review', 'issue', 'ci', 'release', 'browse', 'clear' },
      },
      {
        cmdline = 'Forge pr ',
        expected = {
          'open',
          'browse',
          'create',
          'edit',
          'refresh',
          'repo=',
          'head=',
        },
      },
      {
        cmdline = 'Forge issue ',
        expected = { 'browse', 'close', 'reopen', 'create', 'edit', 'refresh' },
      },
      {
        cmdline = 'Forge ci ',
        expected = { 'open', 'browse', 'refresh' },
      },
      {
        cmdline = 'Forge release ',
        expected = { 'browse', 'delete', 'refresh' },
      },
      {
        cmdline = 'Forge browse ',
        expected = { 'repo=', 'branch=', 'commit=', 'target=' },
      },
      {
        cmdline = 'Forge clear ',
        expected = {},
      },
      {
        cmdline = 'Forge review ',
        expected = { 'open', 'repo=', 'head=', 'adapter=' },
      },
      {
        cmdline = 'Forge pr ci ',
        expected = {},
      },
      {
        cmdline = 'Forge pr reopen ',
        expected = { 'repo=', 'head=' },
      },
      {
        cmdline = 'Forge issue browse ',
        expected = { 'repo=' },
      },
      {
        cmdline = 'Forge ci browse ',
        expected = { 'repo=' },
      },
      {
        cmdline = 'Forge release browse ',
        expected = { 'repo=', 'v1.0.0', 'v1.1.0' },
      },
      {
        cmdline = 'Forge release delete ',
        expected = { 'v1.0.0', 'v1.1.0' },
      },
    }) do
      assert.same(case.expected, completion(case.cmdline))
    end
  end)

  it('completes families, verbs, and valid canonical modifiers contextually', function()
    local families = completion('Forge ')
    local pr = completion('Forge pr ')
    local review = completion('Forge review ')
    local issue = completion('Forge issue ')
    local ci = completion('Forge ci ')
    local release = completion('Forge release ')
    local pr_ci = completion('Forge pr ci ')
    local browse = completion('Forge browse ')
    local pr_create = completion('Forge pr create ')
    local issue_create = completion('Forge issue create ')

    assert.is_true(vim.tbl_contains(families, 'pr'))
    assert.is_true(vim.tbl_contains(families, 'review'))
    assert.is_true(vim.tbl_contains(families, 'ci'))
    assert.is_true(vim.tbl_contains(families, 'browse'))
    assert.is_false(vim.tbl_contains(families, 'mr'))
    assert.is_false(vim.tbl_contains(families, 'pipeline'))
    assert.is_false(vim.tbl_contains(families, 'branches'))
    assert.is_false(vim.tbl_contains(families, 'commits'))
    assert.is_false(vim.tbl_contains(families, 'worktrees'))

    assert.is_true(vim.tbl_contains(pr, 'open'))
    assert.is_false(vim.tbl_contains(pr, 'ci'))
    assert.is_true(vim.tbl_contains(pr, 'create'))
    assert.is_false(vim.tbl_contains(pr, 'approve'))
    assert.is_false(vim.tbl_contains(pr, 'merge'))
    assert.is_false(vim.tbl_contains(pr, 'draft'))
    assert.is_false(vim.tbl_contains(pr, 'ready'))
    assert.is_false(vim.tbl_contains(pr, 'close'))
    assert.is_false(vim.tbl_contains(pr, 'reopen'))
    assert.is_true(vim.tbl_contains(pr, 'refresh'))
    assert.is_true(vim.tbl_contains(pr, 'repo='))
    assert.is_true(vim.tbl_contains(pr, 'head='))
    assert.is_false(vim.tbl_contains(pr, 'checkout'))
    assert.is_false(vim.tbl_contains(pr, 'worktree'))
    assert.is_true(vim.tbl_contains(pr, 'browse'))
    assert.is_false(vim.tbl_contains(pr, 'state='))
    assert.is_true(vim.tbl_contains(review, 'adapter='))
    assert.is_true(vim.tbl_contains(review, 'repo='))
    assert.is_true(vim.tbl_contains(review, 'head='))
    assert.is_true(vim.tbl_contains(ci, 'open'))
    assert.is_true(vim.tbl_contains(ci, 'browse'))
    assert.is_true(vim.tbl_contains(ci, 'refresh'))
    assert.is_false(vim.tbl_contains(ci, 'repo='))
    assert.is_false(vim.tbl_contains(ci, 'log'))
    assert.is_false(vim.tbl_contains(ci, 'watch'))
    assert.same({}, pr_ci)
    assert.is_true(vim.tbl_contains(issue, 'edit'))
    assert.is_true(vim.tbl_contains(issue, 'refresh'))
    assert.is_true(vim.tbl_contains(release, 'browse'))
    assert.is_true(vim.tbl_contains(release, 'delete'))
    assert.is_true(vim.tbl_contains(release, 'refresh'))
    assert.is_true(vim.tbl_contains(browse, 'branch='))
    assert.is_true(vim.tbl_contains(browse, 'commit='))
    assert.is_true(vim.tbl_contains(browse, 'target='))

    assert.is_true(vim.tbl_contains(pr_create, 'head='))
    assert.is_true(vim.tbl_contains(pr_create, 'base='))
    assert.is_true(vim.tbl_contains(pr_create, 'draft'))
    assert.is_true(vim.tbl_contains(pr_create, 'fill'))
    assert.is_true(vim.tbl_contains(pr_create, 'web'))
    assert.is_false(vim.tbl_contains(pr_create, 'state='))

    assert.is_true(vim.tbl_contains(issue_create, 'template='))
    assert.is_true(vim.tbl_contains(issue_create, 'blank'))
    assert.is_true(vim.tbl_contains(issue_create, 'web'))
    assert.is_false(vim.tbl_contains(issue_create, 'head='))
  end)

  it('filters bare pr verb completion for an open non-draft branch PR', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }
    captured.pr_states['owner/upstream#42'] = {
      state = 'OPEN',
      review_decision = '',
      is_draft = false,
    }
    captured.repo_infos['owner/upstream'] = {
      permission = 'WRITE',
      merge_methods = { 'merge', 'squash' },
    }

    local pr = completion('Forge pr ')

    assert.is_true(vim.tbl_contains(pr, 'approve'))
    assert.is_true(vim.tbl_contains(pr, 'merge'))
    assert.is_true(vim.tbl_contains(pr, 'close'))
    assert.is_true(vim.tbl_contains(pr, 'draft'))
    assert.is_false(vim.tbl_contains(pr, 'ready'))
    assert.is_false(vim.tbl_contains(pr, 'reopen'))
    assert.equals(1, #captured.current_pr_calls)
    assert.same({}, captured.branch_pr_calls)
  end)

  it('filters bare pr verb completion for an open draft branch PR', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }
    captured.pr_states['owner/upstream#42'] = {
      state = 'OPEN',
      review_decision = '',
      is_draft = true,
    }
    captured.repo_infos['owner/upstream'] = {
      permission = 'WRITE',
      merge_methods = { 'merge', 'squash' },
    }

    local pr = completion('Forge pr ')

    assert.is_true(vim.tbl_contains(pr, 'approve'))
    assert.is_true(vim.tbl_contains(pr, 'close'))
    assert.is_true(vim.tbl_contains(pr, 'ready'))
    assert.is_false(vim.tbl_contains(pr, 'merge'))
    assert.is_false(vim.tbl_contains(pr, 'draft'))
    assert.is_false(vim.tbl_contains(pr, 'reopen'))
  end)

  it('filters bare pr verb completion for a closed branch PR', function()
    captured.branch_pr_result = function(_, policy)
      local state = policy and policy.searches and policy.searches[1] and policy.searches[1][1]
        or nil
      if state == 'closed' then
        return {
          num = '42',
          scope = repo_scope('upstream'),
        }
      end
      return nil
    end

    local pr = completion('Forge pr ')

    assert.is_true(vim.tbl_contains(pr, 'reopen'))
    assert.is_false(vim.tbl_contains(pr, 'approve'))
    assert.is_false(vim.tbl_contains(pr, 'merge'))
    assert.is_false(vim.tbl_contains(pr, 'close'))
    assert.is_false(vim.tbl_contains(pr, 'draft'))
    assert.is_false(vim.tbl_contains(pr, 'ready'))
    assert.equals(1, #captured.current_pr_calls)
    assert.equals(1, #captured.branch_pr_calls)
    assert.same({ { 'closed' } }, captured.branch_pr_calls[1].policy.searches)
  end)

  it('suppresses implicit current-pr action verbs when branch completion is ambiguous', function()
    captured.current_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    local pr = completion('Forge pr ')

    for _, verb in ipairs({ 'approve', 'merge', 'close', 'draft', 'ready', 'reopen' }) do
      assert.is_false(vim.tbl_contains(pr, verb))
    end
    assert.is_true(vim.tbl_contains(pr, 'repo='))
    assert.is_true(vim.tbl_contains(pr, 'head='))
  end)

  it('completes GitLab family aliases contextually', function()
    detected_forge_name = 'gitlab'

    local families = completion('Forge ')
    local mr = completion('Forge mr ')
    local pipeline = completion('Forge pipeline ')

    assert.is_true(vim.tbl_contains(families, 'pr'))
    assert.is_true(vim.tbl_contains(families, 'ci'))
    assert.is_true(vim.tbl_contains(families, 'mr'))
    assert.is_true(vim.tbl_contains(families, 'pipeline'))
    assert.same({
      'open',
      'browse',
      'create',
      'edit',
      'refresh',
      'repo=',
      'head=',
    }, mr)
    assert.same({ 'open', 'browse', 'refresh' }, pipeline)
  end)

  it(
    'completes local-only and static modifier values without consulting forge entity lists',
    function()
      local repos = completion('Forge pr create repo=')
      local current_pr_repos = completion('Forge pr repo=')
      local branches = completion('Forge browse branch=')
      local commits = completion('Forge browse commit=')
      local targets = completion('Forge browse target=')
      local heads = completion('Forge pr create head=')
      local bases = completion('Forge pr create base=')
      local current_pr_heads = completion('Forge pr head=')
      local review_heads = completion('Forge review head=')
      local pr_ci_heads = completion('Forge pr ci head=')
      local templates = completion('Forge issue create template=')
      local adapters = completion('Forge review 42 adapter=')
      local methods = completion('Forge pr merge method=')

      for _, values in ipairs({ repos, current_pr_repos }) do
        assert.is_true(vim.tbl_contains(values, 'repo=work'))
        assert.is_true(vim.tbl_contains(values, 'repo=mirror'))
        assert.is_true(vim.tbl_contains(values, 'repo=origin'))
        assert.is_true(vim.tbl_contains(values, 'repo=upstream'))
      end

      assert.is_true(vim.tbl_contains(branches, 'branch=main'))
      assert.is_true(vim.tbl_contains(branches, 'branch=feature'))
      assert.is_true(vim.tbl_contains(branches, 'branch=v1.0.0'))
      assert.is_true(vim.tbl_contains(branches, 'branch=deadbee'))

      assert.is_true(vim.tbl_contains(commits, 'commit=main'))
      assert.is_true(vim.tbl_contains(commits, 'commit=feature'))
      assert.is_true(vim.tbl_contains(commits, 'commit=v1.0.0'))
      assert.is_true(vim.tbl_contains(commits, 'commit=deadbee'))

      assert.is_true(vim.tbl_contains(targets, 'target=work@'))
      assert.is_true(vim.tbl_contains(targets, 'target=origin@'))
      assert.is_true(vim.tbl_contains(targets, 'target=@main:'))
      assert.is_true(vim.tbl_contains(targets, 'target=@deadbee:'))

      for _, case in ipairs({
        { values = heads, prefix = 'head=' },
        { values = bases, prefix = 'base=' },
        { values = current_pr_heads, prefix = 'head=' },
        { values = review_heads, prefix = 'head=' },
      }) do
        local values = case.values
        local prefix = case.prefix
        assert.is_true(vim.tbl_contains(values, prefix .. 'work@'))
        assert.is_true(vim.tbl_contains(values, prefix .. 'origin@'))
        assert.is_true(vim.tbl_contains(values, prefix .. '@main'))
        assert.is_true(vim.tbl_contains(values, prefix .. '@deadbee'))
      end

      assert.same({}, pr_ci_heads)

      assert.is_true(vim.tbl_contains(templates, 'template=bug'))
      assert.is_true(vim.tbl_contains(templates, 'template=feature'))

      assert.is_true(vim.tbl_contains(adapters, 'adapter=browse'))
      assert.is_true(vim.tbl_contains(adapters, 'adapter=checkout'))
      assert.is_true(vim.tbl_contains(adapters, 'adapter=codediff'))
      assert.is_true(vim.tbl_contains(adapters, 'adapter=diffs'))
      assert.is_true(vim.tbl_contains(adapters, 'adapter=diffview'))
      assert.is_true(vim.tbl_contains(adapters, 'adapter=worktree'))

      assert.same({ 'method=merge', 'method=squash', 'method=rebase' }, methods)

      assert.same({}, completion('Forge browse rev='))
      assert.same({}, captured.get_list_calls)
      assert.equals(
        0,
        vim.iter(captured.system_calls):fold(0, function(acc, item)
          return acc + (item:match('^gh ') and 1 or 0)
        end)
      )
    end
  )

  it('filters implicit merge method completion through repo-supported merge methods', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }
    captured.pr_states['owner/upstream#42'] = {
      state = 'OPEN',
      review_decision = '',
      is_draft = false,
    }
    captured.repo_infos['owner/upstream'] = {
      permission = 'WRITE',
      merge_methods = { 'squash' },
    }

    assert.same({ 'method=squash' }, completion('Forge pr merge method='))
    assert.equals(1, #captured.current_pr_calls)
  end)

  it('filters explicit merge method completion through the targeted repo info', function()
    captured.pr_states['owner/upstream#42'] = {
      state = 'OPEN',
      review_decision = '',
      is_draft = false,
    }
    captured.repo_infos['owner/upstream'] = {
      permission = 'WRITE',
      merge_methods = { 'rebase' },
    }

    assert.same({ 'method=rebase' }, completion('Forge pr merge 42 repo=upstream method='))
    assert.same({}, captured.current_pr_calls)
  end)

  it('completes registered review adapters for adapter=', function()
    extra_review_adapters = { 'custom-test-review' }

    local adapters = completion('Forge review 42 adapter=')

    assert.is_true(vim.tbl_contains(adapters, 'adapter=custom-test-review'))
  end)

  it('keeps parser acceptance broader than repo= suggestions', function()
    local repos = completion('Forge pr create repo=')
    local command = assert(require('forge.cmd').parse({
      'pr',
      'create',
      'repo=github.com/example/custom',
    }))

    assert.is_false(vim.tbl_contains(repos, 'repo=github.com/example/custom'))
    assert.equals('github.com', command.parsed_modifiers.repo.host)
    assert.equals('example/custom', command.parsed_modifiers.repo.slug)
  end)

  it('does not complete picker-only command families', function()
    assert.is_false(vim.tbl_contains(completion('Forge br'), 'branches'))
    assert.is_false(vim.tbl_contains(completion('Forge comm'), 'commits'))
    assert.is_false(vim.tbl_contains(completion('Forge work'), 'worktrees'))
  end)

  it('returns empty results instead of helpful-noise fallbacks when nothing matches', function()
    local scope = repo_scope('current')
    captured.lists[list_key('release', 'list', scope)] = {
      { tagName = 'v1.0.0', name = 'First' },
    }

    assert.same({}, require('forge.cmd').complete('zzz', 'Forge browse zzz', 0))
    assert.same({}, require('forge.cmd').complete('zzz', 'Forge review zzz', 0))
    assert.same({}, require('forge.cmd').complete('zzz', 'Forge release delete zzz', 0))
  end)

  it('suppresses PR subject completion in stock cmdline and keeps useful modifiers', function()
    local scope = repo_scope('current')
    captured.lists[list_key('pr', 'open', scope)] = {
      { number = 101, title = 'Ready', state = 'OPEN', isDraft = false },
      { number = 102, title = 'Draft', state = 'OPEN', isDraft = true },
      { number = 103, title = 'Approved', state = 'OPEN', isDraft = false },
    }
    captured.pr_states['owner/current#101'] = { review_decision = '', is_draft = false }
    captured.pr_states['owner/current#102'] = { review_decision = '', is_draft = true }
    captured.pr_states['owner/current#103'] = { review_decision = 'APPROVED', is_draft = false }

    local pr = vim.fn.getcompletion('Forge pr ', 'cmdline')
    local close = vim.fn.getcompletion('Forge pr close ', 'cmdline')
    local edit = vim.fn.getcompletion('Forge pr edit ', 'cmdline')
    local approve = vim.fn.getcompletion('Forge pr approve ', 'cmdline')
    local merge = vim.fn.getcompletion('Forge pr merge ', 'cmdline')
    local pr_ci = vim.fn.getcompletion('Forge pr ci ', 'cmdline')
    local draft = vim.fn.getcompletion('Forge pr draft ', 'cmdline')
    local ready = vim.fn.getcompletion('Forge pr ready ', 'cmdline')
    local review = vim.fn.getcompletion('Forge review ', 'cmdline')

    assert.is_true(vim.tbl_contains(pr, 'open'))
    assert.is_true(vim.tbl_contains(pr, 'repo='))
    assert.is_true(vim.tbl_contains(pr, 'head='))
    assert.is_true(vim.tbl_contains(close, 'repo='))
    assert.is_true(vim.tbl_contains(close, 'head='))
    assert.is_true(vim.tbl_contains(edit, 'repo='))
    assert.is_true(vim.tbl_contains(approve, 'repo='))
    assert.is_true(vim.tbl_contains(approve, 'head='))
    assert.is_true(vim.tbl_contains(merge, 'repo='))
    assert.is_true(vim.tbl_contains(merge, 'head='))
    assert.is_true(vim.tbl_contains(merge, 'method='))
    assert.same({}, pr_ci)
    assert.is_true(vim.tbl_contains(draft, 'repo='))
    assert.is_true(vim.tbl_contains(draft, 'head='))
    assert.is_true(vim.tbl_contains(ready, 'repo='))
    assert.is_true(vim.tbl_contains(ready, 'head='))
    assert.is_true(vim.tbl_contains(review, 'open'))
    assert.is_true(vim.tbl_contains(review, 'repo='))
    assert.is_true(vim.tbl_contains(review, 'head='))
    assert.is_true(vim.tbl_contains(review, 'adapter='))

    for _, results in ipairs({ pr, close, edit, approve, merge, pr_ci, draft, ready, review }) do
      assert.is_false(vim.tbl_contains(results, '101'))
      assert.is_false(vim.tbl_contains(results, '102'))
      assert.is_false(vim.tbl_contains(results, '103'))
    end

    assert.same({}, captured.get_list_calls)
    assert.same({}, captured.system_calls)
  end)

  it('suppresses PR reopen subject completion even when closed PRs are cached', function()
    local scope = repo_scope('current')
    captured.lists[list_key('pr', 'closed', scope)] = {
      { number = 201, title = 'Closed', state = 'CLOSED' },
      { number = 202, title = 'Merged', state = 'MERGED' },
    }

    local reopen = vim.fn.getcompletion('Forge pr reopen ', 'cmdline')

    assert.is_true(vim.tbl_contains(reopen, 'repo='))
    assert.is_true(vim.tbl_contains(reopen, 'head='))
    assert.is_false(vim.tbl_contains(reopen, '201'))
    assert.is_false(vim.tbl_contains(reopen, '202'))
    assert.same({}, captured.get_list_calls)
    assert.same({}, captured.system_calls)
  end)

  it('does not consult scoped PR caches for suppressed subject completion', function()
    local current = repo_scope('current')
    local upstream = repo_scope('upstream')
    captured.lists[list_key('pr', 'open', current)] = {
      { number = 301, title = 'Current', state = 'OPEN', isDraft = false },
    }
    captured.lists[list_key('pr', 'open', upstream)] = {
      { number = 302, title = 'Upstream', state = 'OPEN', isDraft = false },
    }

    local merge = require('forge.cmd').complete('', 'Forge pr merge repo=upstream ', 0)

    assert.is_false(vim.tbl_contains(merge, 'repo='))
    assert.is_true(vim.tbl_contains(merge, 'head='))
    assert.is_true(vim.tbl_contains(merge, 'method='))
    assert.is_false(vim.tbl_contains(merge, '302'))
    assert.is_false(vim.tbl_contains(merge, '301'))
    assert.same({}, captured.get_list_calls)
    assert.same({}, captured.system_calls)
  end)

  it('suppresses issue subject completion and does not consult caches or fetch', function()
    local scope = repo_scope('current')
    captured.lists[list_key('issue', 'open', scope)] = {
      { number = 7, title = 'Bug', state = 'OPEN' },
    }
    captured.lists[list_key('issue', 'closed', scope)] = {
      { number = 8, title = 'Closed bug', state = 'CLOSED' },
    }
    captured.system_responses['gh issue list --limit 100 --state open --json number,title,state -R owner/current'] =
      helpers.command_result('[{"number":7,"title":"Bug","state":"OPEN"}]\n')

    local browse = vim.fn.getcompletion('Forge issue browse ', 'cmdline')
    local close = vim.fn.getcompletion('Forge issue close ', 'cmdline')
    local reopen = vim.fn.getcompletion('Forge issue reopen ', 'cmdline')
    local edit = vim.fn.getcompletion('Forge issue edit ', 'cmdline')

    assert.is_true(vim.tbl_contains(browse, 'repo='))
    assert.is_true(vim.tbl_contains(close, 'repo='))
    assert.is_true(vim.tbl_contains(reopen, 'repo='))
    assert.is_true(vim.tbl_contains(edit, 'repo='))

    for _, results in ipairs({ browse, close, reopen, edit }) do
      assert.is_false(vim.tbl_contains(results, '7'))
      assert.is_false(vim.tbl_contains(results, '8'))
    end

    assert.same({}, captured.get_list_calls)
    assert.same({}, captured.system_calls)
  end)

  it('suppresses numeric entity completion even with a numeric prefix', function()
    local pr = require('forge.cmd').complete('1', 'Forge pr merge 1', 0)
    local issue = require('forge.cmd').complete('7', 'Forge issue close 7', 0)
    local ci = require('forge.cmd').complete('4', 'Forge ci open 4', 0)

    assert.same({}, pr)
    assert.same({}, issue)
    assert.same({}, ci)
    assert.same({}, captured.get_list_calls)
    assert.same({}, captured.system_calls)
  end)

  it('suppresses CI run ids while keeping release tags dynamic', function()
    local scope = repo_scope('current')
    captured.lists[list_key('ci', 'all', scope)] = {
      { id = '401', name = 'build', branch = 'main', status = 'success' },
      { id = '402', name = 'test', branch = 'main', status = 'failure' },
    }
    captured.lists[list_key('release', 'list', scope)] = {
      { tagName = 'v1.0.0', name = 'First' },
      { tagName = 'v1.1.0', name = 'Second' },
    }

    local open = vim.fn.getcompletion('Forge ci open ', 'cmdline')
    local browse = vim.fn.getcompletion('Forge ci browse ', 'cmdline')
    local release_browse = vim.fn.getcompletion('Forge release browse ', 'cmdline')
    local release_delete = vim.fn.getcompletion('Forge release delete ', 'cmdline')

    assert.is_true(vim.tbl_contains(open, 'repo='))
    assert.is_true(vim.tbl_contains(browse, 'repo='))
    assert.is_false(vim.tbl_contains(open, '401'))
    assert.is_false(vim.tbl_contains(open, '402'))
    assert.is_false(vim.tbl_contains(browse, '401'))
    assert.is_false(vim.tbl_contains(browse, '402'))
    assert.equals('repo=', release_browse[1])
    assert.is_true(vim.tbl_contains(release_browse, 'v1.0.0'))
    assert.is_true(vim.tbl_contains(release_browse, 'v1.1.0'))
    assert.is_false(vim.tbl_contains(release_delete, 'repo='))
    assert.is_true(vim.tbl_contains(release_delete, 'v1.0.0'))
    assert.is_true(vim.tbl_contains(release_delete, 'v1.1.0'))
    assert.equals(
      0,
      vim.iter(captured.get_list_calls):fold(0, function(acc, key)
        return acc + (key:match('^ci:') and 1 or 0)
      end)
    )
  end)

  it('fetches release tags on explicit completion when the release cache is cold', function()
    local scope = repo_scope('current')
    local key = list_key('release', 'list', scope)
    captured.system_responses['gh release list --json tagName,name,isDraft,isPrerelease --limit 30 -R owner/current'] =
      helpers.command_result('[{"tagName":"v2.0.0","name":"Second"}]\n')

    local first = vim.fn.getcompletion('Forge release browse ', 'cmdline')
    local second = vim.fn.getcompletion('Forge release browse ', 'cmdline')
    local narrowed = vim.fn.getcompletion('Forge release delete v2', 'cmdline')

    assert.equals('repo=', first[1])
    assert.is_true(vim.tbl_contains(first, 'v2.0.0'))
    assert.is_true(vim.tbl_contains(second, 'v2.0.0'))
    assert.same({ 'v2.0.0' }, narrowed)
    assert.same({
      { tagName = 'v2.0.0', name = 'Second' },
    }, captured.lists[key])
    assert.equals(
      1,
      vim.iter(captured.system_calls):fold(0, function(acc, item)
        return acc
          + (
            item
                == 'gh release list --json tagName,name,isDraft,isPrerelease --limit 30 -R owner/current'
              and 1
            or 0
          )
      end)
    )
  end)

  it('does not fetch release tags while completing the repo= subtree', function()
    local repos = vim.fn.getcompletion('Forge release browse repo=', 'cmdline')

    assert.is_true(vim.tbl_contains(repos, 'repo=mirror'))
    assert.is_true(vim.tbl_contains(repos, 'repo=origin'))
    assert.equals(
      0,
      vim.iter(captured.system_calls):fold(0, function(acc, item)
        return acc + (item:match('^gh release list') and 1 or 0)
      end)
    )
    assert.equals(
      0,
      vim.iter(captured.get_list_calls):fold(0, function(acc, key)
        return acc + (key:match('^release:') and 1 or 0)
      end)
    )
  end)
end)
