vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local current_config
local old_preload
local old_system
local old_ui_open

local function fake_forge()
  return {
    name = 'github',
    labels = {
      pr_full = 'PRs',
      issue = 'Issues',
      ci = 'CI',
    },
    browse = function(_, loc, branch, scope)
      captured.browse = {
        loc = loc,
        branch = branch,
        scope = scope,
      }
    end,
    browse_branch = function(_, branch, scope)
      captured.browse_branch = {
        branch = branch,
        scope = scope,
      }
    end,
    browse_commit = function(_, sha, scope)
      captured.browse_commit = {
        sha = sha,
        scope = scope,
      }
    end,
  }
end

local function use_named_current_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

describe('routes', function()
  before_each(function()
    captured = {}
    current_config = {
      client = 'picker',
      context = 'current',
      sections = {
        prs = true,
        issues = true,
        ci = true,
        branches = true,
        commits = true,
        worktrees = true,
        browse = true,
        releases = true,
      },
      routes = {
        prs = 'prs.open',
        issues = 'issues.open',
        ci = 'ci.current_branch',
        branches = 'branches.local',
        commits = 'commits.current_branch',
        worktrees = 'worktrees.list',
        browse = 'browse.contextual',
        releases = 'releases.all',
      },
      contexts = {
        current = true,
      },
    }

    old_system = vim.system
    old_ui_open = vim.ui.open
    vim.system = function(cmd)
      local key = table.concat(cmd, ' ')
      local result = {
        code = 1,
        stdout = '',
      }
      if key == 'git rev-parse --show-toplevel' then
        result = { code = 0, stdout = '/repo\n' }
      elseif key == 'git branch --show-current' then
        result = { code = 0, stdout = 'main\n' }
      elseif key == 'git rev-parse HEAD' then
        result = { code = 0, stdout = 'abc123\n' }
      end
      return {
        wait = function()
          return result
        end,
      }
    end
    vim.ui.open = function(url)
      captured.opened_url = url
      return true
    end

    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['forge.pickers'] = package.preload['forge.pickers'],
    }

    package.preload['forge'] = function()
      return {
        config = function()
          return current_config
        end,
        detect = function()
          return fake_forge()
        end,
        file_loc = function()
          local name = vim.api.nvim_buf_get_name(0)
          if name:match('^%w[%w+.-]*://') then
            return ''
          end
          return 'lua/forge/init.lua'
        end,
        remote_web_url = function(scope)
          return scope and scope.web_url or 'https://github.com/owner/current'
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        warn = function(msg)
          captured.warn = msg
        end,
        error = function(msg)
          captured.error = msg
        end,
        info = function() end,
        debug = function() end,
      }
    end

    package.preload['forge.picker'] = function()
      local picker = dofile(vim.fn.getcwd() .. '/lua/forge/picker/init.lua')
      return vim.tbl_extend('force', picker, {
        backend = function()
          return 'fzf-lua'
        end,
        pick = function(opts)
          captured.root = opts
        end,
      })
    end

    package.preload['forge.pickers'] = function()
      return {
        pr = function(state, _, opts)
          captured.pr = state
          captured.pr_back = opts and opts.back or nil
          captured.pr_scope = opts and opts.scope or nil
        end,
        issue = function(state, _, opts)
          captured.issue = state
          captured.issue_back = opts and opts.back or nil
          captured.issue_scope = opts and opts.scope or nil
        end,
        ci = function(_, branch, _, opts)
          captured.ci = branch
          captured.ci_back = opts and opts.back or nil
          captured.ci_scope = opts and opts.scope or nil
        end,
        branches = function(ctx, opts)
          captured.branches = ctx.id
          captured.branches_back = opts and opts.back or nil
        end,
        commits = function(_, branch, opts)
          captured.commits = branch
          captured.commits_back = opts and opts.back or nil
        end,
        worktrees = function(ctx, opts)
          captured.worktrees = ctx.id
          captured.worktrees_back = opts and opts.back or nil
        end,
        release = function(state, _, opts)
          captured.release = state
          captured.release_back = opts and opts.back or nil
          captured.release_scope = opts and opts.scope or nil
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.routes'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['forge.pickers'] = old_preload['forge.pickers']

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.routes'] = nil
  end)

  it('resolves section aliases through route defaults', function()
    current_config.routes.prs = 'prs.closed'

    require('forge.routes').open('prs')

    assert.equals('closed', captured.pr)
  end)

  it('passes scoped route options through picker handlers', function()
    local scope = {
      kind = 'github',
      host = 'github.com',
      owner = 'owner',
      repo = 'repo',
      slug = 'owner/repo',
      repo_arg = 'owner/repo',
      web_url = 'https://github.com/owner/repo',
    }

    require('forge.routes').open('prs', { scope = scope })
    require('forge.routes').open('ci.current_branch', { scope = scope })

    assert.same(scope, captured.pr_scope)
    assert.same(scope, captured.ci_scope)
  end)

  it('opens the configured root sections through the picker client', function()
    require('forge.routes').open()

    assert.is_not_nil(captured.root)
    assert.equals('Forge (main)> ', captured.root.prompt)

    local labels = {}
    for _, entry in ipairs(captured.root.entries) do
      labels[#labels + 1] = entry.display[1][1]
    end

    assert.same(
      { 'PRs', 'Issues', 'CI', 'Branches', 'Commits', 'Worktrees', 'Browse', 'Releases' },
      labels
    )
    assert.equals(
      'PRs prs pull requests reviews',
      require('forge.picker').search_key('_menu', captured.root.entries[1])
    )
    assert.equals(
      'CI ci checks runs actions',
      require('forge.picker').search_key('_menu', captured.root.entries[3])
    )
    assert.equals(
      'Branches branches refs',
      require('forge.picker').search_key('_menu', captured.root.entries[4])
    )
    assert.is_nil(captured.root.entries[1].display[2])
    assert.is_nil(captured.root.entries[4].display[2])

    captured.root.actions[1].fn(captured.root.entries[2])

    assert.equals('open', captured.issue)
    assert.is_function(captured.issue_back)
  end)

  it('opens branch, commit, and worktree routes through the route aliases', function()
    local routes = require('forge.routes')

    routes.open('branches')
    routes.open('commits')
    routes.open('worktrees')

    assert.equals('current', captured.branches)
    assert.equals('main', captured.commits)
    assert.equals('current', captured.worktrees)
  end)

  it('uses repo browsing for contextual browse without a file buffer', function()
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))

    require('forge.routes').open('browse.contextual')

    assert.equals('https://github.com/owner/current', captured.opened_url)
    assert.is_nil(captured.browse)
  end)

  it('treats special URI buffers as non-file context for contextual browse', function()
    use_named_current_buf('canola://issue/123')

    require('forge.routes').open('browse.contextual')

    assert.equals('https://github.com/owner/current', captured.opened_url)
    assert.is_nil(captured.browse)
  end)

  it('uses file browsing for contextual browse with a file buffer', function()
    use_named_current_buf('/repo/lua/forge/init.lua')

    require('forge.routes').open('browse.contextual')

    assert.same({ loc = 'lua/forge/init.lua', branch = 'main', scope = nil }, captured.browse)
    assert.is_nil(captured.browse_branch)
  end)

  it('uses the current commit for commit browsing', function()
    require('forge.routes').open('browse.commit')

    assert.same({ sha = 'abc123', scope = nil }, captured.browse_commit)
  end)
end)
