vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local cache
local old_preload
local old_system
local old_cmd
local old_ui_select
local old_ui_input
local old_win_get_width

local field_sep = string.char(31)
local record_sep = string.char(30)

local function record(fields)
  return table.concat(fields, field_sep) .. record_sep
end

describe('git sections', function()
  before_each(function()
    captured = { systems = {}, select_choice = 'Yes', input_value = 'new-tree' }
    cache = {}

    old_system = vim.system
    old_cmd = vim.cmd
    old_ui_select = vim.ui.select
    old_ui_input = vim.ui.input
    old_win_get_width = vim.api.nvim_win_get_width
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
      elseif key == 'git branch --delete topic' then
        result.stdout = 'Deleted branch topic (was 789abcd).\n'
      elseif key == 'git show-ref --verify --quiet refs/heads/new-tree' then
        result.code = 1
      elseif
        key == 'git switch topic'
        or key == 'git worktree add /new-tree -b new-tree'
        or key == 'git worktree remove /repo-feature'
      then
        result.stdout = ''
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

    vim.ui.input = function(opts, cb)
      captured.input_prompt = opts.prompt
      cb(captured.input_value)
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
    vim.ui.input = old_ui_input
    vim.api.nvim_win_get_width = old_win_get_width
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
    assert.equals('add', captured.picker.actions[2].name)
    assert.equals('delete', captured.picker.actions[3].name)
    assert.same({
      { '* ', 'ForgePass' },
      { '/repo        ', 'Directory' },
      { ' main   ', 'ForgeBranchCurrent' },
      { ' abc1234', 'ForgeCommitHash' },
    }, captured.picker.entries[1].display)
    assert.same({
      { '  ', 'ForgeDim' },
      { '/repo-feature', 'Directory' },
      { ' feature', 'ForgeBranch' },
      { ' def5678', 'ForgeCommitHash' },
    }, captured.picker.entries[2].display)

    local entry = captured.picker.entries[2]
    captured.picker.actions[1].fn(entry)

    assert.equals('cd /repo-feature', captured.cmd)
    assert.is_true(captured.cleared)
  end)

  it('adds and deletes worktrees', function()
    local ctx = {
      root = '/repo',
    }

    require('forge.pickers').worktrees(ctx)
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    captured.picker.actions[2].fn(nil)
    assert.equals('Add worktree branch: ', captured.input_prompt)
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git worktree add /new-tree -b new-tree')
    end)
    assert.is_true(vim.tbl_contains(captured.systems, 'git worktree add /new-tree -b new-tree'))

    local entry = captured.picker.entries[2]
    captured.picker.actions[3].fn(entry)
    assert.equals('Delete worktree /repo-feature? ', captured.select_prompt)
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git worktree remove /repo-feature')
    end)
    assert.is_true(vim.tbl_contains(captured.systems, 'git worktree remove /repo-feature'))
  end)

  it('expands worktree branch labels when the picker has space', function()
    vim.api.nvim_win_get_width = function()
      return 120
    end

    local current_system = vim.system
    vim.system = function(cmd, opts, cb)
      local key = table.concat(cmd, ' ')
      if key == 'git worktree list --porcelain' then
        local result = {
          code = 0,
          stdout = table.concat({
            'worktree /repo',
            'HEAD abc123456789',
            'branch refs/heads/feature/some-long-worktree-branch-name',
            '',
          }, '\n'),
          stderr = '',
        }
        captured.last_system = key
        captured.systems[#captured.systems + 1] = key
        if cb then
          cb(result)
        end
        return {
          wait = function()
            return result
          end,
        }
      end
      return current_system(cmd, opts, cb)
    end

    require('forge.pickers').worktrees({ root = '/repo' })
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals(
      ' feature/some-long-worktree-branch-name',
      captured.picker.entries[1].display[3][1]
    )
  end)

  it('renders home paths with ~ and shortens long worktree paths', function()
    local home = vim.env.HOME or '/home/barrett'
    local current_path = home .. '/dev/forge.nvim'
    local nested_path = home .. '/dev/forge.nvim/.claude/worktrees/agent-a43cb846'
    local current_system = vim.system
    vim.system = function(cmd, opts, cb)
      local key = table.concat(cmd, ' ')
      if key == 'git worktree list --porcelain' then
        local result = {
          code = 0,
          stdout = table.concat({
            'worktree ' .. current_path,
            'HEAD abc123456789',
            'branch refs/heads/main',
            '',
            'worktree ' .. nested_path,
            'HEAD 9be38e312345',
            'branch refs/heads/worktree-agent-a43cb846',
            '',
          }, '\n'),
          stderr = '',
        }
        captured.last_system = key
        captured.systems[#captured.systems + 1] = key
        if cb then
          cb(result)
        end
        return {
          wait = function()
            return result
          end,
        }
      end
      return current_system(cmd, opts, cb)
    end

    require('forge.pickers').worktrees({ root = current_path })
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals(
      vim.fn.fnamemodify(current_path, ':~'),
      vim.trim(captured.picker.entries[1].display[2][1])
    )
    assert.equals(
      vim.fn.pathshorten(vim.fn.fnamemodify(nested_path, ':~')),
      vim.trim(captured.picker.entries[2].display[2][1])
    )
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
