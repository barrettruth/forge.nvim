vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('edit_issue', function()
  local captured
  local old_fn_system
  local old_vim_system
  local old_executable
  local old_preload

  before_each(function()
    captured = {
      errors = {},
      infos = {},
      systems = {},
    }

    old_fn_system = vim.fn.system
    old_vim_system = vim.system
    old_executable = vim.fn.executable
    old_preload = {
      ['forge.action'] = package.preload['forge.action'],
      ['forge.ci'] = package.preload['forge.ci'],
      ['forge.client'] = package.preload['forge.client'],
      ['forge.compose'] = package.preload['forge.compose'],
      ['forge.config'] = package.preload['forge.config'],
      ['forge.context'] = package.preload['forge.context'],
      ['forge.format'] = package.preload['forge.format'],
      ['forge.backends.github'] = package.preload['forge.backends.github'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.template'] = package.preload['forge.template'],
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
      if key == 'fetch-issue 23' then
        result.stdout = vim.json.encode({
          title = 'Issue title',
          body = 'Issue body',
          labels = {
            { name = 'bug' },
          },
          assignees = {
            { login = 'alice' },
          },
          milestone = {
            title = 'v1',
          },
        })
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

    package.preload['forge.action'] = function()
      return {
        register = function() end,
        run = function() end,
      }
    end

    package.preload['forge.ci'] = function()
      return {}
    end

    package.preload['forge.client'] = function()
      return {
        register = function() end,
      }
    end

    package.preload['forge.compose'] = function()
      return {
        open_issue_edit = function(_, num, details, scope)
          captured.opened = { num = num, details = details, scope = scope }
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
        cli = 'gh',
        fetch_issue_details_cmd = function(_, num)
          return { 'fetch-issue', num }
        end,
        parse_issue_details = function(_, json)
          return {
            title = json.title,
            body = json.body,
            labels = { 'bug' },
            assignees = { 'alice' },
            milestone = 'v1',
          }
        end,
      }
    end

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

    package.preload['forge.template'] = function()
      return {}
    end

    package.loaded['forge'] = nil
    package.loaded['forge.ci'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_vim_system
    vim.fn.executable = old_executable

    package.preload['forge.action'] = old_preload['forge.action']
    package.preload['forge.ci'] = old_preload['forge.ci']
    package.preload['forge.client'] = old_preload['forge.client']
    package.preload['forge.compose'] = old_preload['forge.compose']
    package.preload['forge.config'] = old_preload['forge.config']
    package.preload['forge.context'] = old_preload['forge.context']
    package.preload['forge.format'] = old_preload['forge.format']
    package.preload['forge.backends.github'] = old_preload['forge.backends.github']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.ci'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil
  end)

  it('fetches issue details and opens the issue edit compose flow', function()
    require('forge').edit_issue('23')

    vim.wait(100, function()
      return captured.opened ~= nil
    end)

    assert.same({
      num = '23',
      details = {
        title = 'Issue title',
        body = 'Issue body',
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      scope = nil,
    }, captured.opened)
    assert.is_true(vim.tbl_contains(captured.infos, 'fetching issue #23...'))
  end)
end)
