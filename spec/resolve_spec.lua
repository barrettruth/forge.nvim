vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local preload_modules = {
  'forge',
  'forge.detect',
}

local loaded_modules = {
  'forge',
  'forge.detect',
  'forge.resolve',
  'forge.scope',
  'forge.target',
  'forge.backends.github',
  'forge.backends.gitlab',
  'forge.backends.forgejo',
}

local function github_scope(repo)
  return assert(require('forge.scope').from_url('github', 'https://github.com/owner/' .. repo))
end

local function gitlab_scope(slug)
  return assert(require('forge.scope').from_url('gitlab', 'https://gitlab.com/' .. slug))
end

local function forgejo_scope(repo)
  return assert(require('forge.scope').from_url('forgejo', 'https://codeberg.org/owner/' .. repo))
end

describe('current_pr resolver', function()
  local captured
  local old_system
  local old_preload

  local function fake_backend(name)
    local backend = require('forge.backends.' .. name)
    return vim.tbl_extend('force', backend, {
      pr_for_branch_cmd = function(_, branch, scope, state)
        return { 'pr-for-branch', state or 'open', branch, scope and scope.slug or '' }
      end,
      fetch_pr_details_cmd = function(_, num, scope)
        return { 'fetch-pr', num, scope and scope.slug or '' }
      end,
    })
  end

  local github, gitlab, forgejo

  before_each(function()
    captured = {
      systems = {},
    }
    old_system = vim.system
    old_preload = helpers.capture_preload(preload_modules)

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            targets = {},
          }
        end,
      }
    end
    package.preload['forge.detect'] = function()
      return {
        detect = function()
          return github
        end,
      }
    end

    helpers.clear_loaded(loaded_modules)

    github = fake_backend('github')
    gitlab = fake_backend('gitlab')
    forgejo = fake_backend('forgejo')
  end)

  after_each(function()
    vim.system = old_system
    helpers.restore_preload(old_preload)
    helpers.clear_loaded(loaded_modules)
  end)

  local function use_system_responses(responses)
    vim.system = helpers.system_router({
      calls = captured.systems,
      responses = responses,
      default = helpers.command_result('', 1),
    })
  end

  it('resolves explicit repo and head addresses into the matching PR', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('17\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(err)
    assert.same({
      num = '17',
      scope = github_scope('upstream'),
    }, pr)
  end)

  it('returns nil cleanly when no PR matches the requested head', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('\n'),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(pr)
    assert.is_nil(err)
  end)

  it('reports detached HEAD when current head resolution has no branch', function()
    use_system_responses({
      ['git branch --show-current'] = helpers.command_result('', 1),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
    })

    assert.is_nil(pr)
    assert.same({
      code = 'detached_head',
      message = 'detached HEAD',
    }, err)
  end)

  it('falls back from the push repo to the collaboration repo when needed', function()
    use_system_responses({
      ['git branch --show-current'] = helpers.command_result('feature\n'),
      ['git config branch.feature.pushRemote'] = helpers.command_result('fork\n'),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['pr-for-branch open feature owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch open feature owner/upstream'] = helpers.command_result('42\n'),
      ['fetch-pr 42 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'feature',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
    })

    assert.is_nil(err)
    assert.same({
      num = '42',
      scope = github_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch open feature owner/fork'))
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch open feature owner/upstream'))
    assert.is_true(
      vim.fn.index(captured.systems, 'pr-for-branch open feature owner/fork')
        < vim.fn.index(captured.systems, 'pr-for-branch open feature owner/upstream')
    )
  end)

  it('uses explicit head-branch push context before collaboration fallback', function()
    use_system_responses({
      ['git config branch.topic.pushRemote'] = helpers.command_result('fork\n'),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['pr-for-branch open topic owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('57\n'),
      ['fetch-pr 57 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      head_branch = 'topic',
    })

    assert.is_nil(err)
    assert.same({
      num = '57',
      scope = github_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'git config branch.topic.pushRemote'))
    assert.is_false(vim.tbl_contains(captured.systems, 'git branch --show-current'))
  end)

  it('keeps current_pr open-only when broader branch PR states exist', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('\n'),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(pr)
    assert.is_nil(err)
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch open topic owner/upstream'))
    assert.is_false(vim.tbl_contains(captured.systems, 'pr-for-branch closed topic owner/upstream'))
    assert.is_false(vim.tbl_contains(captured.systems, 'pr-for-branch merged topic owner/upstream'))
  end)

  it('resolves merged GitHub PRs through branch_pr', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch merged topic owner/upstream'] = helpers.command_result('17\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'MERGED',
        mergedAt = '2026-04-27T00:00:00Z',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').branch_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    }, {
      searches = { { 'merged' } },
    })

    assert.is_nil(err)
    assert.same({
      num = '17',
      scope = github_scope('upstream'),
    }, pr)
  end)

  it('supports open-first fallback policies across candidate repos', function()
    use_system_responses({
      ['git branch --show-current'] = helpers.command_result('feature\n'),
      ['git config branch.feature.pushRemote'] = helpers.command_result('fork\n'),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['pr-for-branch open feature owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch open feature owner/upstream'] = helpers.command_result('42\n'),
      ['fetch-pr 42 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'feature',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').branch_pr({
      forge = github,
    }, {
      searches = {
        { 'open' },
        { 'closed', 'merged' },
      },
    })

    assert.is_nil(err)
    assert.same({
      num = '42',
      scope = github_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch open feature owner/fork'))
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch open feature owner/upstream'))
    assert.is_false(vim.tbl_contains(captured.systems, 'pr-for-branch closed feature owner/fork'))
    assert.is_false(
      vim.tbl_contains(captured.systems, 'pr-for-branch merged feature owner/upstream')
    )
  end)

  it('resolves current PR relative to an explicit cwd', function()
    use_system_responses({
      ['git -C /tmp/worktree branch --show-current'] = helpers.command_result('feature\n'),
      ['git -C /tmp/worktree config branch.feature.pushRemote'] = helpers.command_result('fork\n'),
      ['git -C /tmp/worktree remote get-url fork'] = helpers.command_result(
        'git@github.com:owner/fork.git\n'
      ),
      ['git -C /tmp/worktree remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['pr-for-branch open feature owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch open feature owner/upstream'] = helpers.command_result('42\n'),
      ['fetch-pr 42 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'feature',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      target_opts = {
        cwd = '/tmp/worktree',
      },
    })

    assert.is_nil(err)
    assert.same({
      num = '42',
      scope = github_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'git -C /tmp/worktree branch --show-current'))
    assert.is_false(vim.tbl_contains(captured.systems, 'git branch --show-current'))
  end)

  it('matches GitLab merge requests by source project and branch', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@gitlab.com:group/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@gitlab.com:group/fork.git\n'),
      ['pr-for-branch open topic group/upstream'] = helpers.command_result('8\n'),
      ['fetch-pr 8 group/upstream'] = helpers.command_result(vim.json.encode({
        state = 'opened',
        source_branch = 'topic',
        source_project_id = 101,
      })),
      ['glab api --hostname gitlab.com projects/group%2Ffork'] = helpers.command_result(
        vim.json.encode({ id = 101 })
      ),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = gitlab,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(err)
    assert.same({
      num = '8',
      scope = gitlab_scope('group/upstream'),
    }, pr)
  end)

  it('matches GitLab merged requests by source project and branch in branch_pr', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@gitlab.com:group/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@gitlab.com:group/fork.git\n'),
      ['pr-for-branch merged topic group/upstream'] = helpers.command_result('8\n'),
      ['fetch-pr 8 group/upstream'] = helpers.command_result(vim.json.encode({
        state = 'merged',
        source_branch = 'topic',
        source_project_id = 101,
      })),
      ['glab api --hostname gitlab.com projects/group%2Ffork'] = helpers.command_result(
        vim.json.encode({ id = 101 })
      ),
    })

    local pr, err = require('forge.resolve').branch_pr({
      forge = gitlab,
      repo = 'upstream',
      head = 'fork@topic',
    }, {
      searches = { { 'merged' } },
    })

    assert.is_nil(err)
    assert.same({
      num = '8',
      scope = gitlab_scope('group/upstream'),
    }, pr)
  end)

  it('matches Forgejo pull requests by head repo and branch', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@codeberg.org:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@codeberg.org:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('13\n'),
      ['fetch-pr 13 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'open',
        head = {
          ref = 'topic',
          repo = {
            full_name = 'owner/fork',
          },
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = forgejo,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(err)
    assert.same({
      num = '13',
      scope = forgejo_scope('upstream'),
    }, pr)
  end)

  it(
    'treats Forgejo merged PRs as merged even though branch lookup uses closed candidates',
    function()
      use_system_responses({
        ['git remote get-url upstream'] = helpers.command_result(
          'git@codeberg.org:owner/upstream.git\n'
        ),
        ['git remote get-url fork'] = helpers.command_result('git@codeberg.org:owner/fork.git\n'),
        ['pr-for-branch closed topic owner/upstream'] = helpers.command_result('13\n'),
        ['fetch-pr 13 owner/upstream'] = helpers.command_result(vim.json.encode({
          state = 'closed',
          merged = true,
          merged_at = '2026-04-27T00:00:00Z',
          head = {
            ref = 'topic',
            repo = {
              full_name = 'owner/fork',
            },
          },
        })),
      })

      local pr, err = require('forge.resolve').branch_pr({
        forge = forgejo,
        repo = 'upstream',
        head = 'fork@topic',
      }, {
        searches = { { 'merged' } },
      })

      assert.is_nil(err)
      assert.same({
        num = '13',
        scope = forgejo_scope('upstream'),
      }, pr)
    end
  )

  it('excludes merged Forgejo PRs from closed-only branch_pr policies', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@codeberg.org:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@codeberg.org:owner/fork.git\n'),
      ['pr-for-branch closed topic owner/upstream'] = helpers.command_result('13\n'),
      ['fetch-pr 13 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'closed',
        merged = true,
        merged_at = '2026-04-27T00:00:00Z',
        head = {
          ref = 'topic',
          repo = {
            full_name = 'owner/fork',
          },
        },
      })),
    })

    local pr, err = require('forge.resolve').branch_pr({
      forge = forgejo,
      repo = 'upstream',
      head = 'fork@topic',
    }, {
      searches = { { 'closed' } },
    })

    assert.is_nil(pr)
    assert.is_nil(err)
  end)

  it('uses existing fetch-style error phrasing for resolver failures', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('', 1),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(pr)
    assert.same({
      code = 'lookup_failed',
      message = 'failed to fetch PRs',
    }, err)
  end)

  it('reports ambiguity when multiple PRs match the same head', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('17\n18\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
      ['fetch-pr 18 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'OPEN',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(pr)
    assert.same('ambiguous_pr', err.code)
    assert.matches('pass repo= or head=', err.message)
  end)

  it('reports ambiguity when multiple non-open PRs match the same head', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch closed topic owner/upstream'] = helpers.command_result('17\n'),
      ['pr-for-branch merged topic owner/upstream'] = helpers.command_result('18\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'CLOSED',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
      ['fetch-pr 18 owner/upstream'] = helpers.command_result(vim.json.encode({
        state = 'MERGED',
        mergedAt = '2026-04-27T00:00:00Z',
        headRefName = 'topic',
        headRepository = {
          name = 'fork',
          nameWithOwner = 'owner/fork',
        },
        headRepositoryOwner = {
          login = 'owner',
        },
      })),
    })

    local pr, err = require('forge.resolve').branch_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    }, {
      searches = { { 'closed', 'merged' } },
    })

    assert.is_nil(pr)
    assert.same('ambiguous_pr', err.code)
    assert.matches('pass repo= or head=', err.message)
  end)

  it('uses existing parse-detail phrasing when PR details are malformed', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch open topic owner/upstream'] = helpers.command_result('17\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result('{'),
    })

    local pr, err = require('forge.resolve').current_pr({
      forge = github,
      repo = 'upstream',
      head = 'fork@topic',
    })

    assert.is_nil(pr)
    assert.same({
      code = 'lookup_failed',
      message = 'failed to parse PR details',
    }, err)
  end)
end)
