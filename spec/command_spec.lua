vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe(':Forge command', function()
  local captured
  local old_preload
  local old_systemlist
  local old_system

  before_each(function()
    captured = {
      opens = {},
      ops_calls = {},
      pr_action_num = nil,
      pr_action_scope = nil,
      warnings = {},
      closed_prs = {},
      closed_issues = {},
      browse_calls = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.ops'] = package.preload['forge.ops'],
      ['forge.pickers'] = package.preload['forge.pickers'],
    }
    old_systemlist = vim.fn.systemlist
    old_system = vim.system

    vim.system = function(cmd, _, cb)
      local key = table.concat(cmd, ' ')
      local result = {
        code = 1,
        stdout = '',
        stderr = '',
      }
      if key == 'git remote get-url origin' then
        result = { code = 0, stdout = 'git@github.com:owner/current.git\n', stderr = '' }
      elseif key == 'git remote get-url upstream' then
        result = { code = 0, stdout = 'git@github.com:owner/upstream.git\n', stderr = '' }
      elseif key == 'git remote' then
        result = { code = 0, stdout = 'origin\nupstream\n', stderr = '' }
      elseif key == 'git branch --show-current' then
        result = { code = 0, stdout = 'main\n', stderr = '' }
      elseif key == 'git config branch.main.pushRemote' then
        result = { code = 1, stdout = '', stderr = '' }
      elseif key == 'git rev-parse --abbrev-ref main@{upstream}' then
        result = { code = 0, stdout = 'origin/main\n', stderr = '' }
      elseif key == 'git rev-list --max-count=20 --abbrev-commit HEAD' then
        result = { code = 0, stdout = 'deadbee\nabc123\n', stderr = '' }
      end
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
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

    package.preload['forge'] = function()
      return {
        detect = function()
          return {
            name = 'github',
            capabilities = {
              per_pr_checks = true,
            },
            labels = {
              pr_one = 'PR',
            },
            kinds = {
              pr = 'pr',
              issue = 'issue',
            },
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
        edit_pr = function(num)
          captured.edit_pr = num
        end,
        create_issue = function(opts)
          captured.create_issue = opts
        end,
        clear_cache = function()
          captured.cleared = true
        end,
        file_loc = function()
          return 'lua/forge/init.lua:10'
        end,
        open = function(route, opts)
          table.insert(captured.opens, { route = route, opts = opts })
        end,
        template_slugs = function()
          return {}
        end,
      }
    end

    package.preload['forge.ops'] = function()
      return {
        pr_list = function(state, opts)
          table.insert(captured.ops_calls, { name = 'pr_list', state = state, opts = opts })
          require('forge').open(state and ('prs.' .. state) or 'prs', opts)
        end,
        pr_create = function(opts)
          table.insert(captured.ops_calls, { name = 'pr_create', opts = opts })
          require('forge').create_pr(opts)
        end,
        pr_edit = function(pr)
          table.insert(captured.ops_calls, { name = 'pr_edit', pr = pr })
          require('forge').edit_pr(pr.num, pr.scope)
        end,
        pr_checkout = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_checkout', pr = pr })
        end,
        pr_worktree = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_worktree', pr = pr })
        end,
        pr_ci = function(_, pr, opts)
          table.insert(captured.ops_calls, { name = 'pr_ci', pr = pr, opts = opts })
        end,
        pr_browse = function(f, pr)
          table.insert(captured.ops_calls, { name = 'pr_browse', pr = pr })
          f:view_web(f.kinds.pr, pr.num, pr.scope)
        end,
        pr_manage = function(_, pr)
          table.insert(captured.ops_calls, { name = 'pr_manage', pr = pr })
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
        issue_list = function(state, opts)
          table.insert(captured.ops_calls, { name = 'issue_list', state = state, opts = opts })
          require('forge').open(state and ('issues.' .. state) or 'issues', opts)
        end,
        issue_create = function(opts)
          table.insert(captured.ops_calls, { name = 'issue_create', opts = opts })
          require('forge').create_issue(opts)
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
        ci_list = function(branch, opts)
          table.insert(captured.ops_calls, { name = 'ci_list', branch = branch, opts = opts })
          require('forge').open(
            branch == nil and 'ci.all' or 'ci.current_branch',
            vim.tbl_extend('force', opts or {}, { branch = branch })
          )
        end,
        ci_log = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_log', run = run })
        end,
        ci_watch = function(_, run)
          table.insert(captured.ops_calls, { name = 'ci_watch', run = run })
        end,
        release_list = function(state, opts)
          table.insert(captured.ops_calls, { name = 'release_list', state = state, opts = opts })
          require('forge').open(state and ('releases.' .. state) or 'releases', opts)
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
        browse_commit = function(opts)
          table.insert(captured.ops_calls, { name = 'browse_commit', opts = opts })
          require('forge').open('browse.commit', opts)
        end,
        browse_branch = function(branch, opts)
          table.insert(captured.ops_calls, { name = 'browse_branch', branch = branch, opts = opts })
          require('forge').open(
            'browse.branch',
            vim.tbl_extend('force', opts or {}, { branch = branch })
          )
        end,
        browse_contextual = function(opts)
          table.insert(captured.ops_calls, { name = 'browse_contextual', opts = opts })
          require('forge').open('browse.contextual', opts)
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
        pr_manage = function() end,
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

    package.loaded['forge'] = nil
    package.loaded['forge.cmd'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.pickers'] = nil

    dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.systemlist = old_systemlist
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.ops'] = old_preload['forge.ops']
    package.preload['forge.pickers'] = old_preload['forge.pickers']
    package.loaded['forge'] = nil
    package.loaded['forge.cmd'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.pickers'] = nil
    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end
  end)

  it('dispatches git-local route subcommands', function()
    vim.cmd('Forge branches')
    vim.cmd('Forge commits feature')
    vim.cmd('Forge worktrees')

    assert.equals('branches', captured.opens[1].route)
    assert.is_nil(captured.opens[1].opts)
    assert.equals('commits', captured.opens[2].route)
    assert.same({ branch = 'feature' }, captured.opens[2].opts)
    assert.equals('worktrees', captured.opens[3].route)
    assert.is_nil(captured.opens[3].opts)
  end)

  it('uses explicit browse defaults for omitted targets', function()
    vim.cmd('Forge browse')

    assert.same({
      loc = 'lua/forge/init.lua:10',
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

  it('dispatches browse subcommands through the route aliases', function()
    vim.cmd('Forge browse --root')
    vim.cmd('Forge browse --commit')

    assert.equals('browse.branch', captured.opens[1].route)
    assert.equals('browse.commit', captured.opens[2].route)
  end)

  it('dispatches normalized create and clear commands through the command layer', function()
    vim.cmd('Forge pr create --draft --fill --web')
    vim.cmd('Forge issue create --blank --template=bug')
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
    }, captured.create_pr)
    assert.same({ web = false, blank = true, template = 'bug', scope = nil }, captured.create_issue)
    assert.is_true(captured.cleared)
  end)

  it('applies collaboration and ci default scopes to list commands', function()
    vim.cmd('Forge pr')
    vim.cmd('Forge ci')

    assert.equals('prs', captured.opens[1].route)
    assert.equals('owner/upstream', captured.opens[1].opts.scope.slug)
    assert.equals('ci.current_branch', captured.opens[2].route)
    assert.equals('owner/current', captured.opens[2].opts.scope.slug)
    assert.equals('main', captured.opens[2].opts.branch)
  end)

  it('rejects unsupported bang with E477 and no side effects', function()
    local ok, err = pcall(vim.cmd, 'Forge! pr checkout 42')

    assert.is_false(ok)
    assert.matches('E477: No ! allowed', err)
    assert.is_nil(captured.ops_calls[1])
  end)

  it('allows supported bang on close subcommands', function()
    vim.cmd('Forge! pr close 42')
    vim.cmd('Forge! issue close 9')

    assert.same({ name = 'pr_close', pr = { num = '42', scope = nil } }, captured.ops_calls[1])
    assert.same({ name = 'issue_close', issue = { num = '9', scope = nil } }, captured.ops_calls[2])
  end)

  it('dispatches PR management parity subcommands through forge.ops', function()
    vim.cmd('Forge pr approve 42')
    vim.cmd('Forge pr merge 42 repo=upstream')
    vim.cmd('Forge pr draft 42')
    vim.cmd('Forge pr ready 42')

    assert.same({ name = 'pr_approve', pr = { num = '42', scope = nil } }, captured.ops_calls[1])
    assert.same({
      name = 'pr_merge',
      pr = {
        num = '42',
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
      method = nil,
    }, captured.ops_calls[2])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '42', scope = nil },
      is_draft = false,
    }, captured.ops_calls[3])
    assert.same({
      name = 'pr_toggle_draft',
      pr = { num = '42', scope = nil },
      is_draft = true,
    }, captured.ops_calls[4])
  end)

  it('passes through an explicit merge method when provided', function()
    vim.cmd('Forge pr merge 42 method=squash')

    assert.same({
      name = 'pr_merge',
      pr = { num = '42', scope = nil },
      method = 'squash',
    }, captured.ops_calls[1])
  end)

  it('dispatches CI log and watch subcommands through forge.ops', function()
    vim.cmd('Forge ci log 123 repo=upstream')
    vim.cmd('Forge ci watch 456')

    assert.same({
      name = 'ci_log',
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
    assert.same({
      name = 'ci_watch',
      run = { id = '456', scope = nil },
    }, captured.ops_calls[2])
  end)

  it('completes families, verbs, and valid canonical modifiers contextually', function()
    local families = vim.fn.getcompletion('Forge ', 'cmdline')
    local pr = vim.fn.getcompletion('Forge pr ', 'cmdline')
    local pr_create = vim.fn.getcompletion('Forge pr create ', 'cmdline')
    local issue_create = vim.fn.getcompletion('Forge issue create ', 'cmdline')

    assert.is_true(vim.tbl_contains(families, 'pr'))
    assert.is_true(vim.tbl_contains(families, 'ci'))
    assert.is_true(vim.tbl_contains(families, 'browse'))

    assert.is_true(vim.tbl_contains(pr, 'list'))
    assert.is_true(vim.tbl_contains(pr, 'approve'))
    assert.is_true(vim.tbl_contains(pr, 'merge'))
    assert.is_true(vim.tbl_contains(pr, 'draft'))
    assert.is_true(vim.tbl_contains(pr, 'ready'))
    assert.is_true(vim.tbl_contains(pr, 'state='))
    assert.is_true(vim.tbl_contains(pr, 'repo='))

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

  it('completes modifier values for repo, revision, and target addresses', function()
    local repos = vim.fn.getcompletion('Forge pr list repo=', 'cmdline')
    local revs = vim.fn.getcompletion('Forge ci list rev=', 'cmdline')
    local heads = vim.fn.getcompletion('Forge pr create head=', 'cmdline')
    local target_revs = vim.fn.getcompletion('Forge browse target=work@', 'cmdline')

    assert.is_true(vim.tbl_contains(repos, 'repo=work'))
    assert.is_true(vim.tbl_contains(repos, 'repo=mirror'))
    assert.is_true(vim.tbl_contains(repos, 'repo=origin'))
    assert.is_true(vim.tbl_contains(repos, 'repo=upstream'))

    assert.is_true(vim.tbl_contains(revs, 'rev=@main'))
    assert.is_true(vim.tbl_contains(revs, 'rev=@feature'))
    assert.is_true(vim.tbl_contains(revs, 'rev=@v1.0.0'))
    assert.is_true(vim.tbl_contains(revs, 'rev=@deadbee'))

    assert.is_true(vim.tbl_contains(heads, 'head=work@'))
    assert.is_true(vim.tbl_contains(heads, 'head=origin@'))
    assert.is_true(vim.tbl_contains(heads, 'head=@main'))
    assert.is_true(vim.tbl_contains(heads, 'head=@deadbee'))

    assert.is_true(vim.tbl_contains(target_revs, 'target=work@main:'))
    assert.is_true(vim.tbl_contains(target_revs, 'target=work@feature:'))
  end)

  it('completes git-local subcommands and commit refs', function()
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge br', 'cmdline'), 'branches'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge comm', 'cmdline'), 'commits'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge work', 'cmdline'), 'worktrees'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge commits ', 'cmdline'), 'main'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge commits f', 'cmdline'), 'feature'))
  end)
end)
