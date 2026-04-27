vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local preload_modules = {
  'forge.action',
  'forge.backends.github',
  'forge.cache',
  'forge.compose',
  'forge.config',
  'forge.context',
  'forge.format',
  'forge.logger',
  'forge.ops',
  'forge.resolve',
  'forge.review',
  'forge.routes',
  'forge.scope',
  'forge.target',
  'forge.template',
}

local loaded_modules = vim.list_extend({ 'forge' }, preload_modules)

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

describe('high-level implicit-ref API', function()
  local captured
  local old_fn_system
  local old_executable
  local old_preload

  before_each(function()
    captured = {
      branch_pr_calls = {},
      branch_pr_error = nil,
      branch_pr_result = nil,
      current_pr_calls = {},
      current_pr_error = nil,
      current_pr_result = nil,
      errors = {},
      head_calls = {},
      head_error = nil,
      head_result = nil,
      infos = {},
      opens = {},
      ops_calls = {},
      repo_calls = {},
      repo_error = nil,
      repo_result = nil,
      warnings = {},
    }

    old_fn_system = vim.fn.system
    old_executable = vim.fn.executable
    old_preload = helpers.capture_preload(preload_modules)

    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return 0
    end

    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/current.git\n'
      end
      if cmd == 'git branch --show-current' then
        return 'feature\n'
      end
      return ''
    end

    package.preload['forge.action'] = function()
      return {
        register = function() end,
        run = function() end,
      }
    end

    package.preload['forge.backends.github'] = function()
      return {
        name = 'github',
        cli = 'gh',
        labels = {
          ci = 'CI',
          pr_one = 'PR',
        },
      }
    end

    package.preload['forge.cache'] = function()
      return {
        new = function()
          return {
            clear = function() end,
            clear_prefix = function() end,
            get = function()
              return nil
            end,
            set = function() end,
          }
        end,
      }
    end

    package.preload['forge.compose'] = function()
      return {}
    end

    package.preload['forge.config'] = function()
      return {
        config = function()
          return {
            sources = {
              github = { hosts = { 'github.com' } },
              gitlab = { hosts = { 'gitlab.com' } },
              codeberg = { hosts = { 'codeberg.org', 'gitea.com', 'forgejo.org' } },
            },
          }
        end,
      }
    end

    package.preload['forge.context'] = function()
      return {
        register = function() end,
      }
    end

    package.preload['forge.format'] = function()
      return {}
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
        warn = function(msg)
          table.insert(captured.warnings, msg)
        end,
      }
    end

    package.preload['forge.ops'] = function()
      return {
        ci = function(f, head, opts)
          table.insert(captured.ops_calls, { name = 'ci', f = f, head = head, opts = opts })
        end,
        pr_ci = function(f, pr, opts)
          table.insert(captured.ops_calls, { name = 'pr_ci', f = f, pr = pr, opts = opts })
        end,
        pr_edit = function(pr)
          table.insert(captured.ops_calls, { name = 'pr_edit', pr = pr })
        end,
        pr_review = function(f, pr, opts)
          table.insert(
            captured.ops_calls,
            { name = 'pr_review', f = f, pr = pr, opts = opts or {} }
          )
        end,
      }
    end

    package.preload['forge.resolve'] = function()
      return {
        branch_pr = function(opts, policy)
          table.insert(captured.branch_pr_calls, { opts = opts, policy = policy })
          return captured.branch_pr_result, captured.branch_pr_error
        end,
        current_pr = function(opts)
          table.insert(captured.current_pr_calls, opts)
          return captured.current_pr_result, captured.current_pr_error
        end,
        head = function(head, opts)
          table.insert(captured.head_calls, { head = head, opts = opts })
          return captured.head_result, captured.head_error
        end,
        repo = function(repo, opts)
          table.insert(captured.repo_calls, { repo = repo, opts = opts })
          return captured.repo_result, captured.repo_error
        end,
      }
    end

    package.preload['forge.review'] = function()
      return {
        names = function()
          return {}
        end,
        register = function() end,
      }
    end

    package.preload['forge.routes'] = function()
      return {
        current_context = function()
          return nil
        end,
        open = function(route, opts)
          table.insert(captured.opens, { route = route, opts = opts })
        end,
      }
    end

    package.preload['forge.scope'] = function()
      return {
        from_url = function(kind, url)
          local host, owner, repo = url:match('^https://([^/]+)/([^/]+)/([^/]+)$')
          return {
            kind = kind,
            host = host,
            owner = owner,
            repo = repo,
            slug = owner .. '/' .. repo,
            repo_arg = owner .. '/' .. repo,
            web_url = url,
          }
        end,
        key = function(scope)
          if type(scope) ~= 'table' then
            return ''
          end
          return table.concat({
            scope.kind or '',
            scope.host or '',
            scope.slug or '',
          }, '|')
        end,
        remote_name = function(scope)
          return type(scope) == 'table' and scope.repo or nil
        end,
        remote_ref = function(scope, branch)
          return ((type(scope) == 'table' and scope.repo) or 'origin') .. '/' .. branch
        end,
        same = function(a, b)
          return (a and a.kind or '') == (b and b.kind or '')
            and (a and a.host or '') == (b and b.host or '')
            and (a and a.slug or '') == (b and b.slug or '')
        end,
        web_url = function(scope)
          return type(scope) == 'table' and scope.web_url or ''
        end,
      }
    end

    package.preload['forge.target'] = function()
      return {}
    end

    package.preload['forge.template'] = function()
      return {}
    end

    helpers.clear_loaded(loaded_modules)
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.fn.executable = old_executable

    helpers.restore_preload(old_preload)
    helpers.clear_loaded(loaded_modules)
  end)

  it('opens the current PR through the high-level pr() entrypoint', function()
    captured.current_pr_result = {
      num = '42',
      scope = repo_scope('upstream'),
    }

    require('forge').pr()

    assert.equals(1, #captured.current_pr_calls)
    assert.equals('github', captured.current_pr_calls[1].forge.name)
    assert.same({
      name = 'pr_edit',
      pr = { num = '42', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({}, captured.warnings)
  end)

  it(
    'routes explicit PR targets through review() and pr_ci() without current_pr fallback',
    function()
      captured.repo_result = repo_scope('upstream')

      local forge = require('forge')
      forge.review({ num = '57', repo = 'upstream', adapter = 'worktree' })
      forge.pr_ci({ num = '57', repo = 'upstream' })

      assert.same({}, captured.current_pr_calls)
      assert.equals(2, #captured.repo_calls)
      for _, call in ipairs(captured.repo_calls) do
        assert.is_nil(call.repo)
        assert.equals('upstream', call.opts.repo)
      end
      assert.equals('pr_review', captured.ops_calls[1].name)
      assert.equals('github', captured.ops_calls[1].f.name)
      assert.same({ num = '57', scope = repo_scope('upstream') }, captured.ops_calls[1].pr)
      assert.same({ adapter = 'worktree' }, captured.ops_calls[1].opts)
      assert.equals('pr_ci', captured.ops_calls[2].name)
      assert.equals('github', captured.ops_calls[2].f.name)
      assert.same({ num = '57', scope = repo_scope('upstream') }, captured.ops_calls[2].pr)
      assert.is_nil(captured.ops_calls[2].opts)
      assert.same({}, captured.warnings)
    end
  )

  it(
    'does not fall back to ambient resolution when explicit PR targeting omits a usable number',
    function()
      require('forge').pr({ num = '   ', repo = 'upstream' })

      assert.same({}, captured.current_pr_calls)
      assert.same({}, captured.repo_calls)
      assert.same({}, captured.ops_calls)
      assert.same({ 'missing PR number' }, captured.warnings)
    end
  )

  it(
    'does not fall back to current PR resolution when explicit PR targeting has an invalid repo',
    function()
      captured.repo_error = {
        code = 'invalid_repo',
        message = 'invalid repo address',
      }

      require('forge').pr({ num = '42', repo = 'upstream' })

      assert.same({}, captured.current_pr_calls)
      assert.same({}, captured.ops_calls)
      assert.same({ 'invalid repo address' }, captured.warnings)
    end
  )

  it(
    'routes review() through current_pr() and pr_ci() through branch_pr() with explicit address opts',
    function()
      captured.current_pr_result = {
        num = '57',
        scope = repo_scope('upstream'),
      }
      captured.branch_pr_result = {
        num = '57',
        scope = repo_scope('upstream'),
      }

      local forge = require('forge')
      forge.review({ repo = 'upstream', head = 'origin@topic', adapter = 'worktree' })
      forge.pr_ci({ repo = 'upstream', head = 'origin@topic' })

      assert.equals(1, #captured.current_pr_calls)
      assert.equals('github', captured.current_pr_calls[1].forge.name)
      assert.equals('upstream', captured.current_pr_calls[1].repo)
      assert.equals('origin@topic', captured.current_pr_calls[1].head)
      assert.equals(1, #captured.branch_pr_calls)
      assert.equals('github', captured.branch_pr_calls[1].opts.forge.name)
      assert.equals('upstream', captured.branch_pr_calls[1].opts.repo)
      assert.equals('origin@topic', captured.branch_pr_calls[1].opts.head)
      assert.same({
        searches = {
          { 'open' },
          { 'closed', 'merged' },
        },
      }, captured.branch_pr_calls[1].policy)
      assert.equals('pr_review', captured.ops_calls[1].name)
      assert.equals('github', captured.ops_calls[1].f.name)
      assert.same({ num = '57', scope = repo_scope('upstream') }, captured.ops_calls[1].pr)
      assert.same({ adapter = 'worktree' }, captured.ops_calls[1].opts)
      assert.equals('pr_ci', captured.ops_calls[2].name)
      assert.equals('github', captured.ops_calls[2].f.name)
      assert.same({ num = '57', scope = repo_scope('upstream') }, captured.ops_calls[2].pr)
      assert.is_nil(captured.ops_calls[2].opts)
    end
  )

  it('opens current-branch CI through ci() and supports explicit head targeting', function()
    local forge = require('forge')

    captured.head_result = {
      branch = 'feature',
      scope = repo_scope('current'),
    }
    forge.ci()

    captured.head_result = {
      branch = 'release',
      scope = repo_scope('upstream'),
    }
    forge.ci({ head = 'upstream@release' })

    assert.equals(2, #captured.head_calls)
    assert.is_nil(captured.head_calls[1].head)
    assert.equals('upstream@release', captured.head_calls[2].head)
    assert.same({
      name = 'ci',
      f = { name = 'github', cli = 'gh', labels = { ci = 'CI', pr_one = 'PR' } },
      head = { branch = 'feature', scope = repo_scope('current') },
    }, captured.ops_calls[1])
    assert.same({
      name = 'ci',
      f = { name = 'github', cli = 'gh', labels = { ci = 'CI', pr_one = 'PR' } },
      head = { branch = 'release', scope = repo_scope('upstream') },
    }, captured.ops_calls[2])
    assert.same({}, captured.repo_calls)
    assert.same({}, captured.opens)
  end)

  it('uses explicit repo targeting for ci() when only the repo is overridden', function()
    captured.head_result = {
      branch = 'feature',
      scope = repo_scope('current'),
    }
    captured.repo_result = repo_scope('upstream')

    require('forge').ci({ repo = 'upstream' })

    assert.equals(1, #captured.repo_calls)
    assert.is_nil(captured.repo_calls[1].repo)
    assert.equals('upstream', captured.repo_calls[1].opts.repo)
    assert.same({
      name = 'ci',
      f = { name = 'github', cli = 'gh', labels = { ci = 'CI', pr_one = 'PR' } },
      head = { branch = 'feature', scope = repo_scope('upstream') },
    }, captured.ops_calls[1])
    assert.same({}, captured.opens)
  end)

  it('warns cleanly when no current PR matches the high-level current-ref entrypoints', function()
    local forge = require('forge')

    forge.pr()
    forge.review()
    forge.pr_ci()

    assert.same({
      'no open PR found for this branch',
      'no open PR found for this branch',
      'no PR found for this branch',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('surfaces branch-relative PR lookup warnings from pr_ci()', function()
    captured.branch_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }

    require('forge').pr_ci()

    assert.same({
      'multiple PRs match head owner/current@main; pass repo= or head=',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)

  it('surfaces resolver warnings from the high-level current-ref entrypoints', function()
    captured.current_pr_error = {
      code = 'ambiguous_pr',
      message = 'multiple PRs match head owner/current@main; pass repo= or head=',
    }
    captured.head_error = {
      code = 'detached_head',
      message = 'detached HEAD',
    }

    local forge = require('forge')
    forge.pr()
    forge.ci()

    assert.same({
      'multiple PRs match head owner/current@main; pass repo= or head=',
      'detached HEAD',
    }, captured.warnings)
    assert.same({}, captured.ops_calls)
  end)
end)
