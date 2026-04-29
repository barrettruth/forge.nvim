vim.opt.runtimepath:prepend(vim.fn.getcwd())

local current_config
local old_preload
local old_system

describe('context', function()
  before_each(function()
    current_config = {
      context = 'current',
      contexts = {
        current = true,
      },
    }

    old_system = vim.system
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      local result = {
        code = 1,
        stdout = '',
      }
      if key == 'git rev-parse --show-toplevel' then
        result = { code = 0, stdout = '/repo\n' }
      elseif key == 'git branch --show-current' then
        result = { code = 0, stdout = 'main\n' }
      elseif key == 'git rev-parse HEAD' then
        result = { code = 0, stdout = 'abc123\n' }
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    old_preload = {
      ['forge.detect'] = package.preload['forge.detect'],
      ['forge'] = package.preload['forge'],
      ['forge.repo'] = package.preload['forge.repo'],
    }

    package.preload['forge.detect'] = function()
      return {
        detect = function()
          return { name = 'github' }
        end,
      }
    end
    package.preload['forge'] = function()
      return {
        config = function()
          return current_config
        end,
      }
    end

    package.preload['forge.repo'] = function()
      return {
        file_loc = function()
          return 'lua/forge/init.lua:10'
        end,
      }
    end

    package.loaded['forge.detect'] = nil
    package.loaded['forge'] = nil
    package.loaded['forge.repo'] = nil
    package.loaded['forge.context'] = nil
  end)

  after_each(function()
    vim.system = old_system
    package.preload['forge.detect'] = old_preload['forge.detect']
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.repo'] = old_preload['forge.repo']
    package.loaded['forge.detect'] = nil
    package.loaded['forge'] = nil
    package.loaded['forge.repo'] = nil
    package.loaded['forge.context'] = nil
  end)

  it('resolves the current git context', function()
    local ctx = require('forge.context').resolve()

    assert.equals('current', ctx.id)
    assert.equals('/repo', ctx.root)
    assert.equals('main', ctx.branch)
    assert.equals('abc123', ctx.head)
    assert.equals('github', ctx.forge.name)
  end)

  it('rejects disabled contexts', function()
    current_config.context = 'workspace'
    current_config.contexts.workspace = false

    local ctx, err = require('forge.context').resolve()

    assert.is_nil(ctx)
    assert.equals('disabled context: workspace', err)
  end)

  it('rejects unknown contexts', function()
    local ctx, err = require('forge.context').resolve('workspace')

    assert.is_nil(ctx)
    assert.equals('unknown context: workspace', err)
  end)
end)
