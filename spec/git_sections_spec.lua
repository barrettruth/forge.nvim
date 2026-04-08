vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local cache
local old_preload
local old_system
local old_cmd
local old_ui_select

local field_sep = string.char(31)
local record_sep = string.char(30)

local function record(fields)
  return table.concat(fields, field_sep) .. record_sep
end

describe('git sections', function()
  before_each(function()
    captured = { systems = {}, select_choice = 'Yes' }
    cache = {}

    old_system = vim.system
    old_cmd = vim.cmd
    old_ui_select = vim.ui.select
    vim.system = function(cmd, _, cb)
      local key = table.concat(cmd, ' ')
      captured.last_system = key
      captured.systems[#captured.systems + 1] = key
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }

      if key:match('^git for%-each%-ref ') then
        result.stdout = table.concat({
          '*\tmain\torigin/main\tabc1234\tMain branch',
          ' \tfeature\torigin/feature\tdef5678\tFeature branch',
          ' \ttopic\t\t789abcd\tTopic branch',
        }, '\n')
      elseif key:match('^git log ') then
        result.stdout = record({ 'abc123456789', 'abc1234', 'Add routes', 'Barrett', '2 hours ago' })
          .. record({ 'def567890123', 'def5678', 'Add sections', 'B', '1 hour ago' })
      elseif key == 'git worktree list --porcelain' then
        result.stdout = table.concat({
          'worktree /repo',
          'HEAD abc123456789',
          'branch refs/heads/main',
          '',
          'worktree /repo-feature',
          'HEAD def567890123',
          'branch refs/heads/feature',
          '',
        }, '\n')
      elseif key == 'git switch topic' then
        result.stdout = ''
      elseif key == 'git branch --delete topic' then
        result.stdout = 'Deleted branch topic (was 789abcd).\n'
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

    vim.cmd = function(cmd)
      captured.cmd = cmd
    end

    vim.ui.select = function(_, opts, cb)
      captured.select_prompt = opts.prompt
      cb(captured.select_choice)
    end

    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['forge.term'] = package.preload['forge.term'],
      ['forge.review'] = package.preload['forge.review'],
    }

    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          captured.info = msg
        end,
        error = function(msg)
          captured.error = msg
        end,
        debug = function() end,
        warn = function(msg)
          captured.warn = msg
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

    package.preload['forge.term'] = function()
      return {
        open = function(cmd)
          captured.term = cmd
        end,
      }
    end

    package.preload['forge.review'] = function()
      return {
        start_branch = function(_, name)
          captured.review_branch = name
        end,
        start_commit = function(_, sha)
          captured.review_commit = sha
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          return cache[key]
        end,
        set_list = function(key, value)
          cache[key] = value
        end,
        clear_list = function(key)
          cache[key] = nil
        end,
        clear_cache = function()
          captured.cleared = true
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.term'] = nil
    package.loaded['forge.review'] = nil
    package.loaded['forge.pickers'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.cmd = old_cmd
    vim.ui.select = old_ui_select
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['forge.term'] = old_preload['forge.term']
    package.preload['forge.review'] = old_preload['forge.review']
    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.term'] = nil
    package.loaded['forge.review'] = nil
    package.loaded['forge.pickers'] = nil
  end)

  it('lists local branches and supports switch and browse actions', function()
    local ctx = {
      id = 'current',
      root = '/repo',
      forge = {
        browse_branch = function(_, branch)
          captured.browse_branch = branch
        end,
      },
    }

    require('forge.pickers').branches(ctx)
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('Branches (local refs · switch/review · 3)> ', captured.picker.prompt)
    assert.equals('default', captured.picker.actions[1].name)
    assert.equals('switch', captured.picker.actions[1].label)
    assert.equals('browse', captured.picker.actions[2].name)
    assert.equals('review', captured.picker.actions[3].name)
    assert.equals('delete', captured.picker.actions[4].name)
    assert.equals('yank', captured.picker.actions[5].name)
    assert.same({
      { '* ', 'ForgePass' },
      { 'main   ', 'ForgeBranchCurrent' },
      { ' [origin/main]   ', 'Directory' },
      { ' Main branch', 'ForgeDim' },
    }, captured.picker.entries[1].display)
    assert.same({
      { '+ ', 'ForgeBranch' },
      { 'feature', 'ForgeBranch' },
      { ' [origin/feature]', 'Directory' },
      { ' Feature branch', 'ForgeDim' },
    }, captured.picker.entries[2].display)
    assert.same({
      { '  ', 'ForgeDim' },
      { 'topic  ' },
      { '                 ' },
      { ' Topic branch', 'ForgeDim' },
    }, captured.picker.entries[3].display)

    local worktree_entry = captured.picker.entries[2]
    captured.picker.actions[1].fn(worktree_entry)
    assert.equals('cd /repo-feature', captured.cmd)
    assert.is_true(captured.cleared)
    assert.equals('changed directory to /repo-feature', captured.info)

    local switch_entry = captured.picker.entries[3]
    captured.picker.actions[1].fn(switch_entry)
    vim.wait(100, function()
      return captured.info == 'switched to branch topic'
    end)
    assert.equals('switched to branch topic', captured.info)
    assert.equals('git switch topic', captured.last_system)

    captured.picker.actions[2].fn(worktree_entry)
    assert.equals('feature', captured.browse_branch)

    captured.picker.actions[3].fn(worktree_entry)
    assert.equals('feature', captured.review_branch)
  end)

  it('lists current branch commits and shows commit output', function()
    local ctx = {
      forge = {
        browse_commit = function(_, sha)
          captured.browse_commit = sha
        end,
      },
    }

    require('forge.pickers').commits(ctx, 'main')
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('Commits (main history · git show/review · 2)> ', captured.picker.prompt)
    assert.equals('show', captured.picker.actions[1].label)
    assert.equals('web', captured.picker.actions[2].label)
    assert.equals('review', captured.picker.actions[3].label)
    assert.same({
      { 'abc1234', 'ForgeCommitHash' },
      { ' (2 hours ago)', 'ForgeCommitTime' },
      { ' Add routes  ' },
      { ' <Barrett>', 'ForgeCommitAuthor' },
    }, captured.picker.entries[1].display)
    assert.same({
      { 'def5678', 'ForgeCommitHash' },
      { ' (1 hour ago) ', 'ForgeCommitTime' },
      { ' Add sections' },
      { ' <B>      ', 'ForgeCommitAuthor' },
    }, captured.picker.entries[2].display)

    local entry = captured.picker.entries[1]
    captured.picker.actions[1].fn(entry)
    assert.same({
      'git',
      'show',
      '--stat',
      '--patch',
      '--decorate=short',
      'abc123456789',
    }, captured.term)

    captured.picker.actions[2].fn(entry)
    assert.equals('abc123456789', captured.browse_commit)

    captured.picker.actions[3].fn(entry)
    assert.equals('abc123456789', captured.review_commit)
  end)

  it('lists worktrees and switches directories', function()
    local ctx = {
      root = '/repo',
    }

    require('forge.pickers').worktrees(ctx)
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('Worktrees (repo worktrees · switch cwd · 2)> ', captured.picker.prompt)
    assert.equals('switch cwd', captured.picker.actions[1].label)
    assert.same({
      { '* ', 'Identifier' },
      { 'main', 'ForgeBranch' },
      { ' · current · abc1234', 'ForgeDim' },
      { ' /repo', 'ForgeDim' },
    }, captured.picker.entries[1].display)
    assert.same({
      { '  ', 'ForgeDim' },
      { 'feature', 'ForgeBranch' },
      { ' · def5678', 'ForgeDim' },
      { ' /repo-feature', 'ForgeDim' },
    }, captured.picker.entries[2].display)

    local entry = captured.picker.entries[2]
    captured.picker.actions[1].fn(entry)

    assert.equals('cd /repo-feature', captured.cmd)
    assert.is_true(captured.cleared)
  end)

  it('warns for worktree-backed branch deletion and deletes ordinary branches', function()
    local ctx = {
      id = 'current',
      root = '/repo',
    }

    require('forge.pickers').branches(ctx)
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    local delete_action
    for _, action in ipairs(captured.picker.actions) do
      if action.name == 'delete' then
        delete_action = action
        break
      end
    end
    assert.is_not_nil(delete_action)

    local worktree_entry = captured.picker.entries[2]
    delete_action.fn(worktree_entry)
    assert.equals(
      'branch feature is checked out in worktree /repo-feature; use Worktrees to remove it first',
      captured.warn
    )

    local delete_entry = captured.picker.entries[3]
    delete_action.fn(delete_entry)
    assert.equals('Delete branch topic? ', captured.select_prompt)
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git branch --delete topic')
    end)
    assert.is_true(vim.tbl_contains(captured.systems, 'git branch --delete topic'))
  end)
end)
