vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

local preload_modules = {
  'forge.action',
  'forge.client',
  'forge.compose',
  'forge.config',
  'forge.context',
  'forge.format',
  'forge.backends.github',
  'forge.logger',
  'forge.picker',
  'forge.template',
}

local loaded_modules = vim.list_extend({ 'forge' }, preload_modules)

local function repo_scope(repo)
  return {
    kind = 'github',
    host = 'github.com',
    owner = 'owner',
    repo = repo,
    slug = 'owner/' .. repo,
    repo_arg = 'owner/' .. repo,
    web_url = 'https://github.com/owner/' .. repo,
  }
end

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
    old_preload = helpers.capture_preload(preload_modules)

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
      local fail = {
        ['git config branch.feature.pushRemote'] = true,
        ['git config remote.pushDefault'] = true,
        ['git remote get-url upstream'] = true,
        ['git diff --quiet origin/main..HEAD'] = true,
      }
      table.insert(captured.systems, key)
      if fail[key] then
        result.code = 1
      end
      if key == 'pr-for-branch feature' then
        result.stdout = '\n'
      elseif key == 'default-branch' then
        result.stdout = 'main\n'
      elseif key == 'git rev-parse --abbrev-ref feature@{upstream}' then
        result.stdout = 'origin/feature\n'
      elseif key == 'git remote' then
        result.stdout = 'origin\nupstream\n'
      elseif key == 'git remote get-url origin' then
        result.stdout = 'git@github.com:owner/repo.git\n'
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
        labels = { pr_one = 'PR' },
        pr_for_branch_cmd = function(_, branch)
          return { 'pr-for-branch', branch }
        end,
        default_branch_cmd = function()
          return { 'default-branch' }
        end,
        create_pr_web_cmd = function(_, scope, head_scope, head_branch, base_branch)
          captured.web_create = {
            scope = scope,
            head_scope = head_scope,
            head_branch = head_branch,
            base_branch = base_branch,
          }
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

    helpers.clear_loaded(loaded_modules)
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.system = old_fn_system
    vim.fn.executable = old_executable
    vim.ui.open = old_ui_open

    helpers.restore_preload(old_preload)
    helpers.clear_loaded(loaded_modules)
  end)

  local function use_branch_context(branch, origin_url)
    local values = {
      ['git rev-parse --show-toplevel'] = '/repo\n',
      ['git remote get-url origin'] = origin_url or 'git@github.com:owner/repo.git\n',
      ['git branch --show-current'] = branch .. '\n',
    }
    vim.fn.system = function(cmd)
      return values[cmd] or ''
    end
  end

  local function use_system_responses(responses)
    vim.system = helpers.system_router({
      calls = captured.systems,
      responses = responses,
      default = helpers.command_result(),
    })
  end

  it('opens PR compose without prompting when multiple templates exist', function()
    require('forge').create_pr()

    vim.wait(100, function()
      return captured.opened_calls ~= nil
    end)

    assert.equals(1, captured.opened_calls)
    assert.is_nil(captured.opened)
    assert.is_nil(captured.picker)
  end)

  it('blocks web PR creation when the current branch already matches the base', function()
    use_branch_context('main')
    use_system_responses({
      ['git config branch.main.pushRemote'] = helpers.command_result('', 1),
      ['git config remote.pushDefault'] = helpers.command_result('', 1),
      ['git remote get-url upstream'] = helpers.command_result('', 1),
      ['git diff --quiet origin/main..HEAD'] = helpers.command_result('', 1),
      ['pr-for-branch main'] = helpers.command_result('\n'),
      ['default-branch'] = helpers.command_result('main\n'),
      ['git rev-parse --abbrev-ref main@{upstream}'] = helpers.command_result('origin/main\n'),
      ['git remote'] = helpers.command_result('origin\nupstream\n'),
      ['git remote get-url origin'] = helpers.command_result('git@github.com:owner/repo.git\n'),
    })

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.warnings > 0
    end)

    assert.same({ 'current branch already matches base main' }, captured.warnings)
    assert.is_false(vim.tbl_contains(captured.systems, 'git push -u origin main'))
    assert.is_false(vim.tbl_contains(captured.systems, 'create-pr-web'))
  end)

  it('allows web PR creation when the branch matches the base name in a different repo', function()
    use_branch_context('main', 'git@github.com:owner/fork.git\n')
    use_system_responses({
      ['git config branch.main.pushRemote'] = helpers.command_result('', 1),
      ['git config remote.pushDefault'] = helpers.command_result('', 1),
      ['git diff --quiet upstream/main..HEAD'] = helpers.command_result('', 1),
      ['pr-for-branch main'] = helpers.command_result('\n'),
      ['default-branch'] = helpers.command_result('main\n'),
      ['git rev-parse --abbrev-ref main@{upstream}'] = helpers.command_result('origin/main\n'),
      ['git remote'] = helpers.command_result('origin\nupstream\n'),
      ['git remote get-url origin'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result('git@github.com:owner/repo.git\n'),
    })

    require('forge').create_pr({
      web = true,
      scope = repo_scope('repo'),
    })

    vim.wait(100, function()
      return vim.tbl_contains(captured.infos, 'opened PR creation in browser')
    end)

    assert.same({}, captured.warnings)
    assert.is_true(vim.tbl_contains(captured.systems, 'git diff --quiet upstream/main..HEAD'))
    assert.is_true(vim.tbl_contains(captured.systems, 'git push -u origin main'))
    assert.is_true(vim.tbl_contains(captured.systems, 'create-pr-web'))
  end)

  it('blocks web PR creation when there are no changes from the base branch', function()
    use_system_responses({
      ['pr-for-branch feature'] = helpers.command_result('\n'),
      ['default-branch'] = helpers.command_result('main\n'),
      ['git diff --quiet origin/main..HEAD'] = helpers.command_result(),
    })

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
    assert.equals('feature', captured.web_create.head_branch)
    assert.equals('main', captured.web_create.base_branch)
  end)

  it('uses explicit head and base overrides for web PR creation', function()
    use_system_responses({
      ['git diff --quiet upstream/stable..topic'] = helpers.command_result('', 1),
      ['pr-for-branch topic'] = helpers.command_result('\n'),
      ['git remote'] = helpers.command_result('origin\nupstream\n'),
      ['git remote get-url origin'] = helpers.command_result('git@github.com:owner/fork.git\n'),
      ['git remote get-url upstream'] = helpers.command_result('git@github.com:owner/repo.git\n'),
    })

    require('forge').create_pr({
      web = true,
      head_branch = 'topic',
      head_scope = repo_scope('fork'),
      base_branch = 'stable',
      base_scope = repo_scope('repo'),
    })

    vim.wait(100, function()
      return vim.tbl_contains(captured.infos, 'opened PR creation in browser')
    end)

    assert.is_true(vim.tbl_contains(captured.systems, 'git diff --quiet upstream/stable..topic'))
    assert.is_true(vim.tbl_contains(captured.systems, 'git push -u origin topic'))
    assert.equals('topic', captured.web_create.head_branch)
    assert.equals('stable', captured.web_create.base_branch)
    assert.equals('owner/repo', captured.web_create.scope.slug)
    assert.equals('owner/fork', captured.web_create.head_scope.slug)
  end)

  it('reports an error when the web PR command fails', function()
    use_system_responses({
      ['pr-for-branch feature'] = helpers.command_result('\n'),
      ['default-branch'] = helpers.command_result('main\n'),
      ['git diff --quiet origin/main..HEAD'] = helpers.command_result('', 1),
      ['create-pr-web'] = helpers.command_result('', 1, 'web failed'),
    })

    require('forge').create_pr({ web = true })

    vim.wait(100, function()
      return #captured.errors > 0
    end)

    assert.same({ 'web failed' }, captured.errors)
    assert.is_false(vim.tbl_contains(captured.infos, 'opened PR creation in browser'))
  end)

  it('reports browser open failures for URL-based web PR flows', function()
    package.preload['forge.backends.github'] = function()
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

  it('keeps forge detection working when shell_error is stale', function()
    old_fn_system('false')
    assert.not_equals(0, vim.v.shell_error)

    require('forge').create_pr()

    vim.wait(100, function()
      return captured.opened_calls ~= nil
    end)

    assert.equals(1, captured.opened_calls)
    assert.is_nil(captured.picker)
    old_fn_system('true')
  end)
end)
