vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local selected
local old_preload

describe('client', function()
  before_each(function()
    captured = nil
    selected = nil

    old_preload = {
      ['forge.picker'] = package.preload['forge.picker'],
    }

    package.preload['forge.picker'] = function()
      return {
        pick = function(opts)
          captured = opts
        end,
      }
    end

    package.loaded['forge.picker'] = nil
    package.loaded['forge.client'] = nil
  end)

  after_each(function()
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.loaded['forge.picker'] = nil
    package.loaded['forge.client'] = nil
  end)

  it('opens root entries through the picker client', function()
    local entry = { value = 'issues.open' }
    local ok = require('forge.client').open_root('picker', {
      prompt = 'Git> ',
      entries = { entry },
      on_select = function(item)
        selected = item
      end,
    })

    assert.is_true(ok)
    assert.equals('Git> ', captured.prompt)
    assert.same({ entry }, captured.entries)

    captured.actions[1].fn(entry)

    assert.same(entry, selected)
  end)

  it('returns an error for unknown clients', function()
    local ok, err = require('forge.client').open_root('custom', {
      prompt = 'Git> ',
      entries = {},
    })

    assert.is_false(ok)
    assert.equals('unknown client: custom', err)
  end)
end)
