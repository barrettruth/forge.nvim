vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('state', function()
  local state = require('forge.state')
  local detect = require('forge.detect')
  local old_executable
  local old_fn_system
  local old_system
  local real_github
  local updates

  local function github_scope(repo)
    return assert(require('forge.scope').from_url('github', 'https://github.com/owner/' .. repo))
  end

  before_each(function()
    old_executable = vim.fn.executable
    old_fn_system = vim.fn.system
    old_system = vim.system
    real_github = require('forge.backends.github')
    updates = 0
    local group = vim.api.nvim_create_augroup('forge_state_spec', { clear = true })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'ForgeStatusUpdate',
      callback = function()
        updates = updates + 1
      end,
    })
  end)

  after_each(function()
    vim.fn.executable = old_executable
    vim.fn.system = old_fn_system
    vim.system = old_system
    detect.register('github', real_github)
    detect.clear_cache()
    state.clear_cache()
    pcall(vim.api.nvim_del_augroup_by_name, 'forge_state_spec')
  end)

  it('caches repo info lookups per repo and scope', function()
    local calls = 0
    local fake = {
      repo_info = function(_, scope)
        calls = calls + 1
        return {
          permission = scope and scope.slug or '',
        }
      end,
    }
    local scope = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/forge.nvim',
    }
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      return ''
    end

    local first = state.repo_info(fake, scope)
    local second = state.repo_info(fake, scope)

    assert.equals(1, calls)
    assert.same(first, second)
  end)

  it('caches PR state lookups per repo, scope, and number', function()
    local calls = 0
    local fake = {
      pr_state = function(_, num, scope)
        calls = calls + 1
        return {
          state = 'OPEN',
          mergeable = 'UNKNOWN',
          review_decision = num .. '|' .. (scope and scope.slug or ''),
          is_draft = false,
        }
      end,
    }
    local scope = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/forge.nvim',
    }
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      return ''
    end

    local first = state.pr_state(fake, '42', scope)
    local second = state.pr_state(fake, '42', scope)

    assert.equals(1, calls)
    assert.same(first, second)
  end)

  it('refreshes and caches branch, scope, and current PR', function()
    local calls = {}
    detect.register(
      'github',
      vim.tbl_extend('force', real_github, {
        pr_for_branch_cmd = function(_, branch, scope, state_name)
          return { 'pr-for-branch', state_name or 'open', branch, scope and scope.slug or '' }
        end,
        fetch_pr_details_cmd = function(_, num, scope)
          return { 'fetch-pr', num, scope and scope.slug or '' }
        end,
      })
    )
    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return old_executable(bin)
    end
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      return ''
    end
    vim.system = helpers.system_router({
      calls = calls,
      responses = {
        ['git -C /repo remote get-url origin'] = helpers.command_result(
          'git@github.com:owner/current.git\n'
        ),
        ['git -C /repo branch --show-current'] = helpers.command_result('feature\n'),
        ['git -C /repo config branch.feature.pushRemote'] = helpers.command_result('fork\n'),
        ['git -C /repo remote get-url fork'] = helpers.command_result(
          'git@github.com:owner/fork.git\n'
        ),
        ['git -C /repo remote get-url upstream'] = helpers.command_result(
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
      },
      default = helpers.command_result('', 1),
    })

    assert.is_nil(state.status())
    assert.is_true(helpers.wait_for(function()
      return updates > 0 and state.status() ~= nil
    end, { timeout = 200 }))
    assert.same({
      branch = 'feature',
      scope = github_scope('fork'),
      pr = {
        num = '42',
        scope = github_scope('upstream'),
      },
    }, state.status())

    local before = #calls
    assert.same({
      branch = 'feature',
      scope = github_scope('fork'),
      pr = {
        num = '42',
        scope = github_scope('upstream'),
      },
    }, state.status())
    assert.equals(before, #calls)
  end)
end)
