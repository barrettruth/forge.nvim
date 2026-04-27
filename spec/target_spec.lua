vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('target parsing', function()
  local old_system

  before_each(function()
    old_system = vim.system
  end)

  after_each(function()
    vim.system = old_system
    package.loaded['forge.target'] = nil
  end)

  it('parses symbolic, path, and hosted repo addresses', function()
    local target = require('forge.target')
    local symbolic = assert(target.parse_repo('upstream'))
    local path = assert(target.parse_repo('barrettruth/forge.nvim'))
    local hosted = assert(target.parse_repo('github.com/barrettruth/forge.nvim'))

    assert.equals('symbolic', symbolic.form)
    assert.equals('upstream', symbolic.name)
    assert.equals('path', path.form)
    assert.equals('barrettruth/forge.nvim', path.slug)
    assert.equals('hosted', hosted.form)
    assert.equals('github.com', hosted.host)
    assert.equals('barrettruth/forge.nvim', hosted.slug)
  end)

  it('parses revision addresses with optional repo prefixes', function()
    local target = require('forge.target')
    local short = assert(target.parse_rev('@main'))
    local scoped = assert(target.parse_rev('upstream@topic'))

    assert.equals('main', short.rev)
    assert.is_nil(short.repo)
    assert.equals('topic', scoped.rev)
    assert.equals('symbolic', scoped.repo.form)
    assert.equals('upstream', scoped.repo.name)
  end)

  it('parses plain browse branch and commit addresses', function()
    local target = require('forge.target')
    local branch = assert(target.parse_branch('main'))
    local commit = assert(target.parse_commit('deadbee'))

    assert.equals('main', branch.branch)
    assert.equals('deadbee', commit.commit)
  end)

  it('parses location addresses with line ranges', function()
    local target = require('forge.target')
    local location = assert(target.parse_location('upstream@main:lua/forge/init.lua#L10-L40'))

    assert.equals('main', location.rev.rev)
    assert.equals('upstream', location.rev.repo.name)
    assert.equals('lua/forge/init.lua', location.path)
    assert.same({ start_line = 10, end_line = 40 }, location.range)
  end)

  it('resolves aliases before remotes', function()
    vim.system = function(cmd)
      if table.concat(cmd, ' ') == 'git remote get-url upstream' then
        return {
          wait = function()
            return {
              code = 0,
              stdout = 'git@github.com:barrettruth/forge.nvim.git\n',
            }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local resolved = assert(target.resolve_repo('upstream', {
      aliases = {
        upstream = 'github.com/example/override',
      },
    }))

    assert.equals('alias', resolved.via)
    assert.equals('github.com', resolved.host)
    assert.equals('example/override', resolved.slug)
  end)

  it('resolves remotes when no alias matches', function()
    vim.system = function(cmd)
      if table.concat(cmd, ' ') == 'git remote get-url origin' then
        return {
          wait = function()
            return {
              code = 0,
              stdout = 'git@gitlab.com:group/subgroup/project.git\n',
            }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local resolved = assert(target.resolve_repo('origin'))

    assert.equals('remote', resolved.via)
    assert.equals('gitlab.com', resolved.host)
    assert.equals('group/subgroup/project', resolved.slug)
    assert.equals('origin', resolved.remote)
  end)

  it('prefers configured collaboration repos before upstream and origin', function()
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      if key == 'git remote get-url upstream' then
        return {
          wait = function()
            return {
              code = 0,
              stdout = 'git@github.com:owner/upstream.git\n',
            }
          end,
        }
      end
      if key == 'git remote get-url origin' then
        return {
          wait = function()
            return {
              code = 0,
              stdout = 'git@github.com:owner/current.git\n',
            }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local configured = assert(target.collaboration_repo({
      default_repo = 'work',
      aliases = {
        work = 'github.com/owner/shared',
      },
    }))
    local fallback = assert(target.collaboration_repo({}))

    assert.equals('owner/shared', configured.slug)
    assert.equals('owner/upstream', fallback.slug)
  end)

  it('resolves current push context through branch push remotes', function()
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      if key == 'git branch --show-current' then
        return {
          wait = function()
            return { code = 0, stdout = 'feature\n' }
          end,
        }
      end
      if key == 'git config branch.feature.pushRemote' then
        return {
          wait = function()
            return { code = 0, stdout = 'fork\n' }
          end,
        }
      end
      if key == 'git remote get-url fork' then
        return {
          wait = function()
            return { code = 0, stdout = 'git@github.com:owner/fork.git\n' }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local rev = assert(target.push_rev({}))

    assert.equals('feature', rev.rev)
    assert.equals('owner/fork', rev.repo.slug)
  end)

  it('resolves current push context relative to an explicit cwd', function()
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      if key == 'git -C /tmp/worktree branch --show-current' then
        return {
          wait = function()
            return { code = 0, stdout = 'feature\n' }
          end,
        }
      end
      if key == 'git -C /tmp/worktree config branch.feature.pushRemote' then
        return {
          wait = function()
            return { code = 0, stdout = 'fork\n' }
          end,
        }
      end
      if key == 'git -C /tmp/worktree remote get-url fork' then
        return {
          wait = function()
            return { code = 0, stdout = 'git@github.com:owner/fork.git\n' }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local rev = assert(target.push_rev({ cwd = '/tmp/worktree' }))

    assert.equals('feature', rev.rev)
    assert.equals('owner/fork', rev.repo.slug)
  end)

  it('resolves explicit branch push context without consulting the current branch', function()
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      if key == 'git config branch.topic.pushRemote' then
        return {
          wait = function()
            return { code = 0, stdout = 'fork\n' }
          end,
        }
      end
      if key == 'git remote get-url fork' then
        return {
          wait = function()
            return { code = 0, stdout = 'git@github.com:owner/fork.git\n' }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = '' }
        end,
      }
    end

    local target = require('forge.target')
    local rev = assert(target.push_rev_for_branch('topic', {}))

    assert.equals('topic', rev.rev)
    assert.equals('owner/fork', rev.repo.slug)
  end)

  it('converts resolved repo targets into forge scopes', function()
    local target = require('forge.target')
    local scope = assert(target.repo_scope({
      kind = 'repo',
      form = 'hosted',
      host = 'github.com',
      slug = 'owner/repo',
    }, 'github'))

    assert.equals('github', scope.kind)
    assert.equals('owner/repo', scope.slug)
  end)

  it('rejects unresolved symbolic and malformed addresses', function()
    local target = require('forge.target')
    local _, unresolved = target.resolve_repo('missing')
    local _, invalid_rev = target.parse_rev('main')
    local _, invalid_branch = target.parse_branch('@main')
    local _, invalid_commit = target.parse_commit('abc:def')
    local _, invalid_location = target.parse_location('README.md#L10')

    assert.equals('unresolved repo address: missing', unresolved)
    assert.equals('invalid revision address: main', invalid_rev)
    assert.equals('invalid branch: @main', invalid_branch)
    assert.equals('invalid commit: abc:def', invalid_commit)
    assert.equals('invalid location address: README.md#L10', invalid_location)
  end)
end)
