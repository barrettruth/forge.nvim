vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local selected
local close_calls

describe('telescope picker', function()
  local old_preload

  before_each(function()
    captured = {
      maps = { i = {}, n = {} },
      selected_entry = nil,
      default_action = nil,
    }
    selected = nil
    close_calls = 0
    old_preload = {
      ['telescope.pickers'] = package.preload['telescope.pickers'],
      ['telescope.finders'] = package.preload['telescope.finders'],
      ['telescope.config'] = package.preload['telescope.config'],
      ['telescope.actions'] = package.preload['telescope.actions'],
      ['telescope.actions.state'] = package.preload['telescope.actions.state'],
      ['forge'] = package.preload['forge'],
      ['forge.picker.telescope'] = package.loaded['forge.picker.telescope'],
      ['forge.picker'] = package.loaded['forge.picker'],
    }

    package.preload['telescope.pickers'] = function()
      return {
        new = function(_, opts)
          captured.opts = opts
          return {
            find = function()
              opts.attach_mappings(17, function(mode, key, fn)
                captured.maps[mode][key] = fn
              end)
            end,
          }
        end,
      }
    end

    package.preload['telescope.finders'] = function()
      return {
        new_table = function(opts)
          return opts
        end,
      }
    end

    package.preload['telescope.config'] = function()
      return {
        values = {
          generic_sorter = function()
            return function() end
          end,
        },
      }
    end

    package.preload['telescope.actions'] = function()
      return {
        close = function()
          close_calls = close_calls + 1
        end,
        select_default = {
          replace = function(_, fn)
            captured.default_action = fn
          end,
        },
      }
    end

    package.preload['telescope.actions.state'] = function()
      return {
        get_selected_entry = function()
          return captured.selected_entry
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
    package.loaded['forge.picker.telescope'] = nil
    vim.g.forge = nil
  end)

  after_each(function()
    package.preload['telescope.pickers'] = old_preload['telescope.pickers']
    package.preload['telescope.finders'] = old_preload['telescope.finders']
    package.preload['telescope.config'] = old_preload['telescope.config']
    package.preload['telescope.actions'] = old_preload['telescope.actions']
    package.preload['telescope.actions.state'] = old_preload['telescope.actions.state']
    package.preload['forge'] = old_preload['forge']
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.picker'] = old_preload['forge.picker']
    package.loaded['forge.picker.telescope'] = old_preload['forge.picker.telescope']
  end)

  it('keeps default close=false actions open', function()
    local picker = require('forge.picker.telescope')
    local entry = {
      display = { { '#42' } },
      value = '42',
    }
    captured.selected_entry = { value = entry }

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

    assert.is_not_nil(captured.default_action)
    captured.default_action()
    assert.equals(0, close_calls)
    assert.equals('42', selected.value)
  end)

  it('closes default actions by default', function()
    local picker = require('forge.picker.telescope')
    local entry = {
      display = { { '#42' } },
      value = '42',
    }
    captured.selected_entry = { value = entry }

    picker.pick({
      prompt = 'PRs> ',
      entries = { entry },
      actions = {
        {
          name = 'default',
          label = 'checkout',
          fn = function(item)
            selected = item
          end,
        },
      },
      picker_name = 'pr',
    })

    captured.default_action()
    assert.equals(1, close_calls)
    assert.equals('42', selected.value)
  end)

  it('keeps mapped close=false actions open', function()
    local picker = require('forge.picker.telescope')
    local entry = {
      display = { { '#42' } },
      value = '42',
    }
    captured.selected_entry = { value = entry }

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

    captured.maps.i['<c-x>']()
    assert.equals(0, close_calls)
    assert.equals('42', selected.value)
  end)
end)
