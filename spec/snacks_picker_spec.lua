vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local selected
local close_calls

describe('snacks picker', function()
  local old_preload

  before_each(function()
    captured = nil
    selected = nil
    close_calls = 0
    old_preload = {
      ['snacks'] = package.preload['snacks'],
      ['forge'] = package.preload['forge'],
      ['forge.picker.snacks'] = package.loaded['forge.picker.snacks'],
      ['forge.picker'] = package.loaded['forge.picker'],
    }

    package.preload['snacks'] = function()
      return {
        picker = function(opts)
          captured = opts
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        config = require('forge.config').config,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.snacks'] = nil
    vim.g.forge = nil
  end)

  after_each(function()
    package.preload['snacks'] = old_preload['snacks']
    package.preload['forge'] = old_preload['forge']
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.picker'] = old_preload['forge.picker']
    package.loaded['forge.picker.snacks'] = old_preload['forge.picker.snacks']
  end)

  it('keeps close=false actions open', function()
    local picker = require('forge.picker.snacks')
    local entry = {
      display = { { '#42' } },
      value = '42',
    }

    picker.pick({
      prompt = 'PRs> ',
      entries = { entry },
      actions = {
        {
          name = 'browse',
          label = 'web',
          close = false,
          fn = function(item)
            selected = item
          end,
        },
      },
      picker_name = 'pr',
    })

    local picker_obj = {
      current = function()
        return captured.items[1]
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    captured.actions.forge_browse(picker_obj)
    assert.equals(0, close_calls)
    assert.equals('42', selected.value)
  end)

  it('closes close=false actions when the selected row forces it', function()
    local picker = require('forge.picker.snacks')
    local entry = {
      display = { { 'Load more...' } },
      value = nil,
      load_more = true,
      force_close = true,
    }

    picker.pick({
      prompt = 'Issues> ',
      entries = { entry },
      actions = {
        {
          name = 'default',
          label = 'open',
          close = false,
          fn = function(item)
            selected = item
          end,
        },
      },
      picker_name = 'issue',
    })

    local picker_obj = {
      current = function()
        return captured.items[1]
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    captured.actions.confirm(picker_obj)
    assert.equals(1, close_calls)
    assert.is_true(selected.load_more)
  end)

  it('closes actions by default', function()
    local picker = require('forge.picker.snacks')
    local entry = {
      display = { { '#42' } },
      value = '42',
    }
    vim.g.forge = { keys = { pr = { checkout = '<c-k>' } } }

    picker.pick({
      prompt = 'PRs> ',
      entries = { entry },
      actions = {
        {
          name = 'checkout',
          label = 'checkout',
          fn = function(item)
            selected = item
          end,
        },
      },
      picker_name = 'pr',
    })

    local picker_obj = {
      current = function()
        return captured.items[1]
      end,
      close = function()
        close_calls = close_calls + 1
      end,
    }

    captured.actions.forge_checkout(picker_obj)
    assert.equals(1, close_calls)
    assert.equals('42', selected.value)
  end)
end)
