vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('create_issue', function()
  local captured
  local old_fn_system
  local old_vim_system
  local old_executable
  local old_ui_open
  local old_preload

  before_each(function()
    captured = {
      errors = {},
      infos = {},
      systems = {},
      open_urls = {},
      warnings = {},
    }

    old_fn_system = vim.fn.system
    old_vim_system = vim.system
    old_executable = vim.fn.executable
    old_ui_open = vim.ui.open
    old_preload = {
      ['forge.action'] = package.preload['forge.action'],
      ['forge.client'] = package.preload['forge.client'],
      ['forge.compose'] = package.preload['forge.compose'],
      ['forge.config'] = package.preload['forge.config'],
      ['forge.compose.creation'] = package.preload['forge.compose.creation'],
      ['forge.context'] = package.preload['forge.context'],
      ['forge.format'] = package.preload['forge.format'],
      ['forge.backends.github'] = package.preload['forge.backends.github'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['forge.compose.template'] = package.preload['forge.compose.template'],
    }

    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return 0
    end

    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/repo.git\n'
      end
      return ''
    end

    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      table.insert(captured.systems, key)
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    vim.ui.open = function(url)
      table.insert(captured.open_urls, url)
      return true
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
          captured.opened_calls = (captured.opened_calls or 0) + 1
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

    package.preload['forge.backends.github'] = function()
      return {
        name = 'github',
        cli = 'gh',
        create_issue_web_cmd = function()
          return { 'create-issue-web' }
        end,
        issue_template_paths = function()
          return { '.github/ISSUE_TEMPLATE/' }
        end,
      }
    end
    package.loaded['forge'] = nil
    package.loaded['forge.compose.creation'] = nil
    package.loaded['forge.backends.github'] = nil

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
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
    package.loaded['forge.compose.creation'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.compose.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_vim_system
    vim.fn.executable = old_executable
    vim.ui.open = old_ui_open

    package.preload['forge.action'] = old_preload['forge.action']
    package.preload['forge.client'] = old_preload['forge.client']
    package.preload['forge.compose'] = old_preload['forge.compose']
    package.preload['forge.config'] = old_preload['forge.config']
    package.preload['forge.compose.creation'] = old_preload['forge.compose.creation']
    package.preload['forge.context'] = old_preload['forge.context']
    package.preload['forge.format'] = old_preload['forge.format']
    package.preload['forge.backends.github'] = old_preload['forge.backends.github']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['forge.compose.template'] = old_preload['forge.compose.template']

    package.loaded['forge'] = nil
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.compose.creation'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.compose.template'] = nil
  end)

  it('opens a blank issue compose instead of prompting when multiple templates exist', function()
    package.preload['forge.compose.template'] = function()
      return {
        discover = function()
          return nil,
            {
              {
                name = 'bug_report.md',
                display = 'Bug Report',
                is_yaml = false,
                dir = '/repo/.github/ISSUE_TEMPLATE',
              },
              {
                name = 'feature_request.md',
                display = 'Feature Request',
                is_yaml = false,
                dir = '/repo/.github/ISSUE_TEMPLATE',
              },
            },
            nil
        end,
      }
    end

    require('forge').create_issue()

    assert.equals(1, captured.opened_calls)
    assert.is_nil(captured.opened)
    assert.is_nil(captured.picker)
    assert.same({}, captured.errors)
  end)

  it(
    'logs an error instead of opening an issue when the discovered template fails to load',
    function()
      package.preload['forge.compose.template'] = function()
        return {
          discover = function()
            return nil,
              nil,
              'tree-sitter yaml parser not found; install it to use YAML issue form templates'
          end,
        }
      end

      require('forge').create_issue()

      assert.is_nil(captured.opened_calls)
      assert.is_nil(captured.picker)
      assert.same(
        { 'tree-sitter yaml parser not found; install it to use YAML issue form templates' },
        captured.errors
      )
    end
  )

  it('uses an explicit issue template slug without invoking the picker', function()
    package.preload['forge.compose.template'] = function()
      return {
        entries = function()
          return {
            {
              name = 'bug_report.md',
              display = 'Bug Report',
              is_yaml = false,
              dir = '/repo/.github/ISSUE_TEMPLATE',
            },
            {
              name = 'feature_request.md',
              display = 'Feature Request',
              is_yaml = false,
              dir = '/repo/.github/ISSUE_TEMPLATE',
            },
          }
        end,
        load = function(entry)
          return { body = entry.display }
        end,
      }
    end

    require('forge').create_issue({ template = 'feature_request' })

    assert.equals(1, captured.opened_calls)
    assert.same({ body = 'Feature Request' }, captured.opened)
    assert.is_nil(captured.picker)
    assert.same({}, captured.errors)
  end)

  it('reports success when the web issue command succeeds', function()
    require('forge').create_issue({ web = true })

    helpers.wait_for(function()
      return vim.tbl_contains(captured.infos, 'opened issue creation in browser')
    end)

    assert.same({ 'opened issue creation in browser' }, captured.infos)
    assert.is_true(vim.tbl_contains(captured.systems, 'create-issue-web'))
  end)

  it('reports an error when the web issue command fails', function()
    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      table.insert(captured.systems, key)
      if key == 'create-issue-web' then
        result.code = 1
        result.stderr = 'issue web failed'
      end
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    require('forge').create_issue({ web = true })

    helpers.wait_for(function()
      return #captured.errors > 0
    end)

    assert.same({ 'issue web failed' }, captured.errors)
    assert.is_false(vim.tbl_contains(captured.infos, 'opened issue creation in browser'))
  end)

  it('reports browser open failures for URL-based web issue flows', function()
    package.preload['forge.backends.github'] = function()
      return {
        name = 'github',
        cli = 'gh',
        issue_template_paths = function()
          return { '.github/ISSUE_TEMPLATE/' }
        end,
      }
    end

    vim.ui.open = function(url)
      table.insert(captured.open_urls, url)
      return nil, 'open failed'
    end

    require('forge').create_issue({ web = true })

    assert.same({ 'open failed' }, captured.errors)
    assert.same({ 'https://github.com/owner/repo/issues/new' }, captured.open_urls)
  end)

  it('prefers URL-based web issue flows over command-based ones when both exist', function()
    package.preload['forge.backends.github'] = function()
      return {
        cli = 'gh',
        create_issue_web_cmd = function()
          return { 'create-issue-web' }
        end,
        create_issue_web_url = function()
          return 'https://github.com/owner/repo/issues/new'
        end,
        issue_template_paths = function()
          return { '.github/ISSUE_TEMPLATE/' }
        end,
      }
    end

    require('forge').create_issue({ web = true })

    assert.same({}, captured.systems)
    assert.same({ 'https://github.com/owner/repo/issues/new' }, captured.open_urls)
    assert.same({ 'opened issue creation in browser' }, captured.infos)
  end)

  it('keeps forge detection working when shell_error is stale', function()
    old_fn_system('false')
    assert.not_equals(0, vim.v.shell_error)

    require('forge').create_issue({ web = true })

    helpers.wait_for(function()
      return vim.tbl_contains(captured.infos, 'opened issue creation in browser')
    end)

    assert.is_true(vim.tbl_contains(captured.systems, 'create-issue-web'))
    old_fn_system('true')
  end)
end)
