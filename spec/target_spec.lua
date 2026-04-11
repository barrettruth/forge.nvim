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

  it('rejects unresolved symbolic and malformed addresses', function()
    local target = require('forge.target')
    local _, unresolved = target.resolve_repo('missing')
    local _, invalid_rev = target.parse_rev('main')
    local _, invalid_location = target.parse_location('README.md#L10')

    assert.equals('unresolved repo address: missing', unresolved)
    assert.equals('invalid revision address: main', invalid_rev)
    assert.equals('invalid location address: README.md#L10', invalid_location)
  end)
end)
