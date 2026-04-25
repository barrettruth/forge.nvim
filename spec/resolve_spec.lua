vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local preload_modules = {
  'forge',
}

local loaded_modules = {
  'forge',
  'forge.resolve',
  'forge.scope',
  'forge.target',
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

describe('current_pr resolver', function()
  local captured
  local old_system
  local old_preload

  local github = {
    name = 'github',
    labels = {
      pr_one = 'PR',
      pr_full = 'PRs',
    },
    pr_for_branch_cmd = function(_, branch, scope)
      return { 'pr-for-branch', branch, scope and scope.slug or '' }
    end,
    fetch_pr_details_cmd = function(_, num, scope)
      return { 'fetch-pr', num, scope and scope.slug or '' }
    end,
  }

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

    helpers.clear_loaded(loaded_modules)
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
      ['pr-for-branch topic owner/upstream'] = helpers.command_result('17\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
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
      scope = repo_scope('upstream'),
    }, pr)
  end)

  it('returns nil cleanly when no PR matches the requested head', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch topic owner/upstream'] = helpers.command_result('\n'),
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
      ['pr-for-branch feature owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch feature owner/upstream'] = helpers.command_result('42\n'),
      ['fetch-pr 42 owner/upstream'] = helpers.command_result(vim.json.encode({
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
      scope = repo_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch feature owner/fork'))
    assert.is_true(vim.tbl_contains(captured.systems, 'pr-for-branch feature owner/upstream'))
    assert.is_true(
      vim.fn.index(captured.systems, 'pr-for-branch feature owner/fork')
        < vim.fn.index(captured.systems, 'pr-for-branch feature owner/upstream')
    )
  end)

  it('uses explicit head-branch push context before collaboration fallback', function()
    use_system_responses({
      ['git config branch.topic.pushRemote'] = helpers.command_result('fork\n'),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['pr-for-branch topic owner/fork'] = helpers.command_result('\n'),
      ['pr-for-branch topic owner/upstream'] = helpers.command_result('57\n'),
      ['fetch-pr 57 owner/upstream'] = helpers.command_result(vim.json.encode({
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
      scope = repo_scope('upstream'),
    }, pr)
    assert.is_true(vim.tbl_contains(captured.systems, 'git config branch.topic.pushRemote'))
    assert.is_false(vim.tbl_contains(captured.systems, 'git branch --show-current'))
  end)

  it('reports ambiguity when multiple PRs match the same head', function()
    use_system_responses({
      ['git remote get-url upstream'] = helpers.command_result(
        'git@github.com:owner/upstream.git\n'
      ),
      ['git remote get-url fork'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['pr-for-branch topic owner/upstream'] = helpers.command_result('17\n18\n'),
      ['fetch-pr 17 owner/upstream'] = helpers.command_result(vim.json.encode({
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
end)
