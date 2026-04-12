vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('create_pr', function()
  local captured
  local old_system
  local old_fn_system
  local old_executable
  local old_ui_open
  local old_preload

  before_each(function()
    captured = {
      errors = {},
      infos = {},
      warnings = {},
      systems = {},
      open_urls = {},
    }

    old_system = vim.system
    old_fn_system = vim.fn.system
    old_executable = vim.fn.executable
    old_ui_open = vim.ui.open
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

    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/repo.git\n'
      end
      if cmd == 'git branch --show-current' then
        return 'feature\n'
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
      if key == 'pr-for-branch feature' then
        result.stdout = '\n'
      elseif key == 'default-branch' then
        result.stdout = 'main\n'
      elseif key == 'git diff --quiet origin/main..HEAD' then
        result.code = 1
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
        open_pr = function(_, _, _, _, result)
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
        labels = { pr_one = 'PR' },
        pr_for_branch_cmd = function(_, branch)
          return { 'pr-for-branch', branch }
        end,
        default_branch_cmd = function()
          return { 'default-branch' }
        end,
        create_pr_web_cmd = function()
          return { 'create-pr-web' }
        end,
        template_paths = function()
          return { '.github/PULL_REQUEST_TEMPLATE/' }
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

    vim.ui.open = function(url)
      table.insert(captured.open_urls, url)
      return true
    end

    package.preload['forge.picker'] = function()
      return {
        pick = function(opts)
          captured.picker = opts
        end,
      }
    end

    package.preload['forge.template'] = function()
      return {
        discover = function()
          return nil,
            {
              {
                name = 'pull_request.md',
                display = 'Pull Request',
                is_yaml = false,
                dir = '/repo/.github/PULL_REQUEST_TEMPLATE',
              },
            },
            nil
        end,
        load = function()
          return { body = 'template' }
        end,
        fill_from_commits = function()
          return 'title', 'body'
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
    vim.system = old_system
    vim.fn.system = old_fn_system
    vim.fn.executable = old_executable
    vim.ui.open = old_ui_open

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

  it('preserves back on the PR template picker', function()
    local back_calls = 0

    require('forge').create_pr({
      back = function()
        back_calls = back_calls + 1
      end,
    })

    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.is_not_nil(captured.picker)
    assert.is_function(captured.picker.back)

    captured.picker.back()

    assert.equals(1, back_calls)
  end)

  it('blocks web PR creation when the current branch already matches the base', function()
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/repo.git\n'
      end
      if cmd == 'git branch --show-current' then
        return 'main\n'
      end
      return ''
    end

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.warnings > 0
    end)

    assert.same({ 'current branch already matches base main' }, captured.warnings)
    assert.is_false(vim.tbl_contains(captured.systems, 'git push -u origin main'))
    assert.is_false(vim.tbl_contains(captured.systems, 'create-pr-web'))
  end)

  it('blocks web PR creation when there are no changes from the base branch', function()
    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      table.insert(captured.systems, key)
      if key == 'pr-for-branch feature' then
        result.stdout = '\n'
      elseif key == 'default-branch' then
        result.stdout = 'main\n'
      elseif key == 'git diff --quiet origin/main..HEAD' then
        result.code = 0
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

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.warnings > 0
    end)

    assert.same({ 'no changes from origin/main' }, captured.warnings)
    assert.is_false(vim.tbl_contains(captured.systems, 'git push -u origin feature'))
    assert.is_false(vim.tbl_contains(captured.systems, 'create-pr-web'))
  end)

  it('pushes and opens the web flow only when the branch is creatable', function()
    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return vim.tbl_contains(captured.infos, 'opened PR creation in browser')
    end)

    assert.is_true(vim.tbl_contains(captured.systems, 'git push -u origin feature'))
    assert.is_true(vim.tbl_contains(captured.systems, 'create-pr-web'))
    assert.is_true(vim.tbl_contains(captured.infos, 'opened PR creation in browser'))
  end)

  it('reports an error when the web PR command fails', function()
    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      table.insert(captured.systems, key)
      if key == 'pr-for-branch feature' then
        result.stdout = '\n'
      elseif key == 'default-branch' then
        result.stdout = 'main\n'
      elseif key == 'git diff --quiet origin/main..HEAD' then
        result.code = 1
      elseif key == 'create-pr-web' then
        result.code = 1
        result.stderr = 'web failed'
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

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.errors > 0
    end)

    assert.same({ 'web failed' }, captured.errors)
    assert.is_false(vim.tbl_contains(captured.infos, 'opened PR creation in browser'))
  end)

  it('reports browser open failures for URL-based web PR flows', function()
    package.preload['forge.github'] = function()
      return {
        cli = 'gh',
        labels = { pr_one = 'PR' },
        pr_for_branch_cmd = function(_, branch)
          return { 'pr-for-branch', branch }
        end,
        default_branch_cmd = function()
          return { 'default-branch' }
        end,
        create_pr_web_url = function()
          return 'https://example.test/compare/main...feature'
        end,
        template_paths = function()
          return { '.github/PULL_REQUEST_TEMPLATE/' }
        end,
      }
    end

    vim.ui.open = function(url)
      table.insert(captured.open_urls, url)
      return nil, 'open failed'
    end

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.errors > 0
    end)

    assert.same({ 'open failed' }, captured.errors)
    assert.same({ 'https://example.test/compare/main...feature' }, captured.open_urls)
  end)
end)
