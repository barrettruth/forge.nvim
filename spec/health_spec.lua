vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('health', function()
  local captured
  local old_executable
  local old_exists
  local old_health
  local old_inspect
  local old_preload

  before_each(function()
    captured = {
      starts = {},
      oks = {},
      infos = {},
      warns = {},
      errors = {},
    }

    old_executable = vim.fn.executable
    old_exists = vim.fn.exists
    old_health = {
      start = vim.health.start,
      ok = vim.health.ok,
      info = vim.health.info,
      warn = vim.health.warn,
      error = vim.health.error,
    }
    old_inspect = vim.treesitter.language.inspect
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['fzf-lua'] = package.preload['fzf-lua'],
    }

    vim.fn.executable = function(bin)
      if bin == 'git' or bin == 'gh' then
        return 1
      end
      return 0
    end
    vim.fn.exists = function(name)
      if name == ':DiffviewOpen' then
        return 0
      end
      return old_exists(name)
    end

    vim.health.start = function(msg)
      table.insert(captured.starts, msg)
    end
    vim.health.ok = function(msg)
      table.insert(captured.oks, msg)
    end
    vim.health.info = function(msg)
      table.insert(captured.infos, msg)
    end
    vim.health.warn = function(msg)
      table.insert(captured.warns, msg)
    end
    vim.health.error = function(msg)
      table.insert(captured.errors, msg)
    end

    vim.treesitter.language.inspect = function(lang)
      error('missing parser: ' .. lang)
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            review = {
              adapter = 'checkout',
            },
          }
        end,
        review_adapter_names = function()
          return { 'browse', 'checkout', 'diffview', 'worktree' }
        end,
        registered_sources = function()
          return {}
        end,
      }
    end

    package.preload['forge.picker'] = function()
      return {
        backend = function()
          return 'fzf-lua'
        end,
        detect_order = { 'fzf-lua' },
      }
    end

    package.preload['fzf-lua'] = function()
      return {}
    end

    package.loaded['forge'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.health'] = nil
    package.loaded['fzf-lua'] = nil
  end)

  after_each(function()
    vim.fn.executable = old_executable
    vim.fn.exists = old_exists
    vim.health.start = old_health.start
    vim.health.ok = old_health.ok
    vim.health.info = old_health.info
    vim.health.warn = old_health.warn
    vim.health.error = old_health.error
    vim.treesitter.language.inspect = old_inspect

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['fzf-lua'] = old_preload['fzf-lua']

    package.loaded['forge'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.health'] = nil
    package.loaded['fzf-lua'] = nil
  end)

  it('reports a missing yaml parser as a health error', function()
    require('forge.health').check()

    assert.is_true(vim.tbl_contains(captured.starts, 'Core tools'))
    assert.is_true(vim.tbl_contains(captured.starts, 'Review adapters'))
    assert.is_true(vim.tbl_contains(captured.oks, 'git found'))
    assert.is_true(vim.tbl_contains(captured.oks, 'configured review adapter "checkout" available'))
    assert.is_true(vim.tbl_contains(captured.oks, 'fzf-lua found (interactive picker UI enabled)'))
    assert.is_true(
      vim.tbl_contains(captured.infos, 'diffview.nvim not found (adapter=diffview unavailable)')
    )
    assert.is_true(
      vim.tbl_contains(
        captured.errors,
        'tree-sitter yaml parser not found (required for YAML issue form templates)'
      )
    )
  end)

  it('reports missing optional interactive picker UI as info', function()
    package.preload['fzf-lua'] = nil
    package.loaded['fzf-lua'] = nil
    package.loaded['forge.health'] = nil

    require('forge.health').check()

    assert.is_true(
      vim.tbl_contains(
        captured.infos,
        'fzf-lua not found (interactive picker UI disabled; direct :Forge commands still available)'
      )
    )
  end)

  it('warns when the configured diffview adapter is unavailable', function()
    package.preload['forge'] = function()
      return {
        config = function()
          return {
            review = {
              adapter = 'diffview',
            },
          }
        end,
        review_adapter_names = function()
          return { 'browse', 'checkout', 'diffview', 'worktree' }
        end,
        registered_sources = function()
          return {}
        end,
      }
    end
    package.loaded['forge'] = nil
    package.loaded['forge.health'] = nil

    require('forge.health').check()

    assert.is_true(
      vim.tbl_contains(
        captured.warns,
        'review.adapter=diffview but diffview.nvim is not available (:DiffviewOpen missing)'
      )
    )
  end)
end)
