vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe(':Forge command', function()
  local captured
  local old_preload

  before_each(function()
    captured = {
      pr_action_num = nil,
      reviews = {},
      warnings = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.pickers'] = package.preload['forge.pickers'],
    }

    package.preload['forge.logger'] = function()
      return {
        warn = function(msg)
          table.insert(captured.warnings, msg)
        end,
        info = function() end,
        debug = function() end,
        error = function() end,
      }
    end

    package.preload['forge'] = function()
      return {
        detect = function()
          return {
            capabilities = {
              per_pr_checks = true,
            },
            labels = {
              pr_one = 'PR',
            },
            kinds = {
              pr = 'pr',
            },
          }
        end,
        open = function() end,
      }
    end

    package.preload['forge.pickers'] = function()
      return {
        pr_actions = function(_, num)
          captured.pr_action_num = num
          return {
            review = function()
              table.insert(captured.reviews, num)
            end,
          }
        end,
        checks = function() end,
        ci = function() end,
        pr_manage = function() end,
        pr_close = function() end,
        pr_reopen = function() end,
      }
    end

    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil

    dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
  end)

  after_each(function()
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.pickers'] = old_preload['forge.pickers']
    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil
    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end
  end)

  it('dispatches :Forge pr review to the PR review action', function()
    vim.cmd('Forge pr review 42')

    assert.equals('42', captured.pr_action_num)
    assert.same({ '42' }, captured.reviews)
  end)

  it('keeps :Forge pr diff as an alias for the PR review action', function()
    vim.cmd('Forge pr diff 7')

    assert.equals('7', captured.pr_action_num)
    assert.same({ '7' }, captured.reviews)
  end)
end)
