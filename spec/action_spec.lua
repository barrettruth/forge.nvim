vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local old_preload

describe('action', function()
  before_each(function()
    captured = nil

    old_preload = {
      ['forge.routes'] = package.preload['forge.routes'],
    }

    package.preload['forge.routes'] = function()
      return {
        open = function(name, opts)
          captured = {
            name = name,
            opts = opts,
          }
        end,
      }
    end

    package.loaded['forge.routes'] = nil
    package.loaded['forge.action'] = nil
  end)

  after_each(function()
    package.preload['forge.routes'] = old_preload['forge.routes']
    package.loaded['forge.routes'] = nil
    package.loaded['forge.action'] = nil
  end)

  it('binds the built-in open action to route dispatch', function()
    local def = require('forge.action').bind('open', {
      name = 'default',
      context = 'workspace',
    })

    def.fn({ value = 'issues.open' })

    assert.equals('issues.open', captured.name)
    assert.equals('workspace', captured.opts.context)
  end)

  it('runs custom registered actions', function()
    require('forge.action').register('ping', function(entry, opts)
      captured = {
        entry = entry,
        opts = opts,
      }
    end)

    local ok = require('forge.action').run('ping', { value = 'x' }, { count = 2 })

    assert.is_true(ok)
    assert.equals('x', captured.entry.value)
    assert.equals(2, captured.opts.count)
  end)

  it('returns an error for unknown actions', function()
    local ok, err = require('forge.action').run('missing', nil, {})

    assert.is_false(ok)
    assert.equals('unknown action: missing', err)
  end)
end)
