vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('edit_pr', function()
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
      ['forge.client'] = package.preload['forge.client'],
      ['forge.compose'] = package.preload['forge.compose'],
      ['forge.config'] = package.preload['forge.config'],
      ['forge.context'] = package.preload['forge.context'],
      ['forge.format'] = package.preload['forge.format'],
      ['forge.github'] = package.preload['forge.github'],
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
      if cmd == 'git branch --show-current' then
        return 'other-local-branch\n'
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
      if key == 'fetch-pr 23' then
        result.stdout = vim.json.encode({
          title = 'PR title',
          body = 'PR body',
          isDraft = false,
          headRefName = 'real-pr-head',
          baseRefName = 'main',
          labels = {
            { name = 'bug' },
          },
          assignees = {
            { login = 'alice' },
          },
          reviewRequests = {
            { login = 'bob' },
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

    package.preload['forge.client'] = function()
      return {
        register = function() end,
      }
    end

    package.preload['forge.compose'] = function()
      return {
        open_pr_edit = function(_, num, details, current_branch, scope)
          captured.opened = {
            num = num,
            details = details,
            current_branch = current_branch,
            scope = scope,
          }
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
        labels = { pr_one = 'PR' },
        fetch_pr_details_cmd = function(_, num)
          return { 'fetch-pr', num }
        end,
        parse_pr_details = function(_, json)
          return {
            title = json.title,
            body = json.body,
            draft = json.isDraft == true,
            head_branch = json.headRefName,
            base_branch = json.baseRefName,
            labels = { 'bug' },
            assignees = { 'alice' },
            reviewers = { 'bob' },
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
    package.loaded['forge.action'] = nil
    package.loaded['forge.client'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.context'] = nil
    package.loaded['forge.format'] = nil
    package.loaded['forge.github'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_vim_system
    vim.fn.executable = old_executable

    package.preload['forge.action'] = old_preload['forge.action']
    package.preload['forge.client'] = old_preload['forge.client']
    package.preload['forge.compose'] = old_preload['forge.compose']
    package.preload['forge.config'] = old_preload['forge.config']
    package.preload['forge.context'] = old_preload['forge.context']
    package.preload['forge.format'] = old_preload['forge.format']
    package.preload['forge.github'] = old_preload['forge.github']
    package.preload['forge.logger'] = old_preload['forge.logger']
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
    package.loaded['forge.template'] = nil
  end)

  it('uses fetched PR head/base metadata instead of the current local branch', function()
    require('forge').edit_pr('23')

    vim.wait(100, function()
      return captured.opened ~= nil
    end)

    assert.same({
      num = '23',
      details = {
        title = 'PR title',
        body = 'PR body',
        draft = false,
        head_branch = 'real-pr-head',
        base_branch = 'main',
        labels = { 'bug' },
        assignees = { 'alice' },
        reviewers = { 'bob' },
        milestone = 'v1',
      },
      current_branch = 'other-local-branch',
      scope = nil,
    }, captured.opened)
    assert.is_true(vim.tbl_contains(captured.infos, 'fetching PR #23...'))
    assert.is_false(vim.tbl_contains(captured.systems, 'pr-base 23'))
  end)

  it('still opens PR edit while detached HEAD', function()
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/repo.git\n'
      end
      if cmd == 'git branch --show-current' then
        return '\n'
      end
      return ''
    end

    require('forge').edit_pr('23')

    vim.wait(100, function()
      return captured.opened ~= nil
    end)

    assert.equals('', captured.opened.current_branch)
    assert.same({}, captured.warnings or {})
  end)
end)
