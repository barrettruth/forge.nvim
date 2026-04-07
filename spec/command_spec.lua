vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe(':Forge command', function()
  local captured
  local old_preload

  before_each(function()
    captured = {
      pr_action_num = nil,
      reviews = {},
      review_actions = {},
      warnings = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.pickers'] = package.preload['forge.pickers'],
      ['forge.review'] = package.preload['forge.review'],
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
        current_context = function()
          return {
            root = '/repo',
            branch = 'main',
            head = 'abc123',
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

    package.preload['forge.review'] = function()
      return {
        toggle = function()
          table.insert(captured.review_actions, 'toggle')
        end,
        stop = function()
          table.insert(captured.review_actions, 'end')
        end,
        files = function()
          table.insert(captured.review_actions, 'files')
        end,
        next_file = function()
          table.insert(captured.review_actions, 'next-file')
        end,
        prev_file = function()
          table.insert(captured.review_actions, 'prev-file')
        end,
        next_hunk = function()
          table.insert(captured.review_actions, 'next-hunk')
        end,
        prev_hunk = function()
          table.insert(captured.review_actions, 'prev-hunk')
        end,
        start_branch = function(_, branch)
          table.insert(captured.review_actions, 'branch:' .. branch)
        end,
        start_commit = function(_, sha)
          table.insert(captured.review_actions, 'commit:' .. sha)
        end,
      }
    end

    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.review'] = nil

    dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
  end)

  after_each(function()
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.pickers'] = old_preload['forge.pickers']
    package.preload['forge.review'] = old_preload['forge.review']
    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.review'] = nil
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

  it('dispatches review navigation subcommands', function()
    vim.cmd('Forge review files')
    vim.cmd('Forge review next-file')
    vim.cmd('Forge review prev-file')
    vim.cmd('Forge review next-hunk')
    vim.cmd('Forge review prev-hunk')

    assert.same(
      { 'files', 'next-file', 'prev-file', 'next-hunk', 'prev-hunk' },
      captured.review_actions
    )
  end)

  it('dispatches branch and commit review launchers', function()
    vim.cmd('Forge review branch feature')
    vim.cmd('Forge review commit deadbeef')

    assert.same({ 'branch:feature', 'commit:deadbeef' }, captured.review_actions)
  end)
end)
