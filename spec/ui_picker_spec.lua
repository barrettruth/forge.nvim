vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('ui picker backend', function()
  local captured
  local old_ui_select
  local old_preload

  before_each(function()
    captured = {
      prompts = {},
      items = {},
      actions = {},
    }
    old_ui_select = vim.ui.select
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.picker'] = package.preload['forge.picker'],
    }

    vim.ui.select = function(items, opts, cb)
      table.insert(captured.prompts, opts.prompt)
      table.insert(captured.items, items)
      if #captured.prompts == 1 then
        cb(items[1])
      else
        cb(items[2])
      end
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            keys = {
              back = '<c-o>',
            },
          }
        end,
      }
    end

    package.preload['forge.picker'] = function()
      return require('forge.picker.init')
    end

    package.loaded['forge'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.ui'] = nil
  end)

  after_each(function()
    vim.ui.select = old_ui_select
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.loaded['forge'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.ui'] = nil
  end)

  it('offers an action menu after selecting an entry', function()
    require('forge.picker.ui').pick({
      prompt = 'PRs> ',
      picker_name = 'pr',
      entries = {
        {
          display = { { 'Entry 1' } },
          value = 1,
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function(entry)
            table.insert(captured.actions, { name = 'open', value = entry.value })
          end,
        },
        {
          name = 'browse',
          label = 'browse',
          fn = function(entry)
            table.insert(captured.actions, { name = 'browse', value = entry.value })
          end,
        },
      },
    })

    assert.same({ 'PRs> ', 'PRs> Action> ' }, captured.prompts)
    assert.same({ { name = 'browse', value = 1 } }, captured.actions)
  end)

  it('runs back when the action menu selects it', function()
    local first_action_menu = true
    vim.ui.select = function(items, opts, cb)
      table.insert(captured.prompts, opts.prompt)
      if opts.prompt == 'PRs> ' then
        cb(items[1])
        return
      end
      if first_action_menu then
        first_action_menu = false
        cb(items[#items])
      else
        cb(nil)
      end
    end

    require('forge.picker.ui').pick({
      prompt = 'PRs> ',
      picker_name = 'pr',
      entries = {
        {
          display = { { 'Entry 1' } },
          value = 1,
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function(entry)
            table.insert(captured.actions, { name = 'open', value = entry.value })
          end,
        },
      },
      back = function()
        table.insert(captured.actions, { name = 'back' })
      end,
    })

    assert.same({ { name = 'back' } }, captured.actions)
  end)
end)
