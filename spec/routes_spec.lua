vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local current_config
local old_preload
local old_system

local function fake_forge()
  return {
    name = 'github',
    labels = {
      pr_full = 'PRs',
      issue = 'Issues',
      ci = 'CI',
    },
    browse = function(_, loc, branch)
      captured.browse = {
        loc = loc,
        branch = branch,
      }
    end,
    browse_branch = function(_, branch)
      captured.browse_branch = branch
    end,
    browse_commit = function(_, sha)
      captured.browse_commit = sha
    end,
  }
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
          return 'lua/forge/init.lua:10'
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
      return {
        pick = function(opts)
          captured.root = opts
        end,
      }
    end

    package.preload['forge.pickers'] = function()
      return {
        pr = function(state)
          captured.pr = state
        end,
        issue = function(state)
          captured.issue = state
        end,
        ci = function(_, branch)
          captured.ci = branch
        end,
        branches = function(ctx)
          captured.branches = ctx.id
        end,
        commits = function(_, branch)
          captured.commits = branch
        end,
        worktrees = function(ctx)
          captured.worktrees = ctx.id
        end,
        release = function(state)
          captured.release = state
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

  it('opens the configured root sections through the picker client', function()
    require('forge.routes').open()

    assert.is_not_nil(captured.root)
    assert.equals('Github workflow (main)> ', captured.root.prompt)

    local labels = {}
    for _, entry in ipairs(captured.root.entries) do
      labels[#labels + 1] = entry.display[1][1]
    end

    assert.same(
      { 'PRs', 'Issues', 'CI', 'Branches', 'Commits', 'Worktrees', 'Browse', 'Releases' },
      labels
    )
    assert.equals(
      ' · forge · open reviews · review, worktree, ci',
      captured.root.entries[1].display[2][1]
    )
    assert.equals(
      ' · git · local refs · switch, review, browse',
      captured.root.entries[4].display[2][1]
    )
    assert.equals(
      ' · git · main history · git show, review, browse',
      captured.root.entries[5].display[2][1]
    )
    assert.equals(
      ' · git · repo worktrees · switch cwd, copy path',
      captured.root.entries[6].display[2][1]
    )

    captured.root.actions[1].fn(captured.root.entries[2])

    assert.equals('open', captured.issue)
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

  it('uses branch browsing for contextual browse without a file buffer', function()
    require('forge.routes').open('browse.contextual')

    assert.equals('main', captured.browse_branch)
    assert.is_nil(captured.browse)
  end)

  it('uses the current commit for commit browsing', function()
    require('forge.routes').open('browse.commit')

    assert.equals('abc123', captured.browse_commit)
  end)
end)
