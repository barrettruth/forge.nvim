vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('create_issue', function()
  local captured
  local old_system
  local old_executable
  local old_preload

  before_each(function()
    captured = {
      errors = {},
    }

    old_system = vim.fn.system
    old_executable = vim.fn.executable
    old_preload = {
      ['forge.action'] = package.preload['forge.action'],
      ['forge.client'] = package.preload['forge.client'],
      ['forge.compose'] = package.preload['forge.compose'],
      ['forge.config'] = package.preload['forge.config'],
      ['forge.context'] = package.preload['forge.context'],
      ['forge.format'] = package.preload['forge.format'],
      ['forge.github'] = package.preload['forge.github'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return 0
    end

    package.preload['forge.action'] = function()
      return {
        register = function() end,
        run = function() end,
      }
    end

    package.preload['forge.client'] = function()
      return {
        register = function() end,
      }
    end

    package.preload['forge.compose'] = function()
      return {
        open_issue = function(_, result)
          captured.opened = result
        end,
      }
    end

    package.preload['forge.config'] = function()
      return {
        config = function()
          return {
            sources = {
              github = { hosts = { 'github.com' } },
              gitlab = { hosts = { 'gitlab.com' } },
              codeberg = { hosts = { 'codeberg.org', 'gitea.com', 'forgejo.org' } },
            },
          }
        end,
      }
    end

    package.preload['forge.context'] = function()
      return {
        register = function() end,
      }
    end

    package.preload['forge.format'] = function()
      return {}
    end

    package.preload['forge.github'] = function()
      return {
        cli = 'gh',
        issue_template_paths = function()
          return { '.github/ISSUE_TEMPLATE/' }
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function() end,
        warn = function(msg)
          table.insert(captured.warnings or {}, msg)
        end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
      }
    end

    package.preload['forge.picker'] = function()
      return {
        pick = function(opts)
          captured.picker = opts
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_system
    vim.fn.executable = old_executable

    package.preload['forge.action'] = old_preload['forge.action']
    package.preload['forge.client'] = old_preload['forge.client']
    package.preload['forge.compose'] = old_preload['forge.compose']
    package.preload['forge.config'] = old_preload['forge.config']
    package.preload['forge.context'] = old_preload['forge.context']
    package.preload['forge.format'] = old_preload['forge.format']
    package.preload['forge.github'] = old_preload['forge.github']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.template'] = nil
  end)

  it('aborts issue creation when a single yaml template cannot be loaded', function()
    package.preload['forge.template'] = function()
      return {
        discover = function()
          return nil,
            nil,
            'tree-sitter yaml parser not found; install it to use YAML issue form templates'
        end,
        load = function() end,
      }
    end

    require('forge').create_issue()

    assert.is_nil(captured.opened)
    assert.is_nil(captured.picker)
    assert.same(
      { 'tree-sitter yaml parser not found; install it to use YAML issue form templates' },
      captured.errors
    )
  end)

  it(
    'logs an error instead of opening a blank issue when a selected yaml template fails to load',
    function()
      package.preload['forge.template'] = function()
        return {
          discover = function()
            return nil,
              {
                {
                  name = 'bug_report.yaml',
                  display = 'Bug Report',
                  is_yaml = true,
                  dir = '/repo/.github/ISSUE_TEMPLATE',
                },
              },
              nil
          end,
          load = function()
            return nil,
              'tree-sitter yaml parser not found; install it to use YAML issue form templates'
          end,
        }
      end

      require('forge').create_issue()

      assert.is_not_nil(captured.picker)
      captured.picker.actions[1].fn(captured.picker.entries[1])

      assert.is_nil(captured.opened)
      assert.same(
        { 'tree-sitter yaml parser not found; install it to use YAML issue form templates' },
        captured.errors
      )
    end
  )
end)
