vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local cache
local old_preload
local old_system
local old_cmd

local field_sep = string.char(31)
local record_sep = string.char(30)

local function record(fields)
  return table.concat(fields, field_sep) .. record_sep
end

describe('git sections', function()
  before_each(function()
    captured = {}
    cache = {}

    old_system = vim.system
    old_cmd = vim.cmd
    vim.system = function(cmd, _, cb)
      local key = table.concat(cmd, ' ')
      captured.last_system = key
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }

      if key:match('^git for%-each%-ref ') then
        result.stdout = record({ '*', 'main', 'origin/main', 'abc1234', 'Main branch' })
          .. record({ ' ', 'feature', 'origin/feature', 'def5678', 'Feature branch' })
      elseif key:match('^git log ') then
        result.stdout = record({ 'abc123456789', 'abc1234', 'Add routes', 'Barrett', '2 hours ago' })
          .. record({ 'def567890123', 'def5678', 'Add sections', 'Barrett', '1 hour ago' })
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
      elseif key == 'git switch feature' then
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

    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['forge.term'] = package.preload['forge.term'],
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
    package.loaded['forge.pickers'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.cmd = old_cmd
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['forge.term'] = old_preload['forge.term']
    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.term'] = nil
    package.loaded['forge.pickers'] = nil
  end)

  it('lists local branches and supports checkout and browse actions', function()
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

    assert.equals('Branches (local · 2)> ', captured.picker.prompt)
    assert.equals('default', captured.picker.actions[1].name)
    assert.equals('browse', captured.picker.actions[2].name)
    assert.equals('yank', captured.picker.actions[3].name)

    local entry = captured.picker.entries[2]
    captured.picker.actions[1].fn(entry)
    vim.wait(100, function()
      return captured.info == 'checked out branch feature'
    end)
    assert.equals('checked out branch feature', captured.info)
    assert.equals('git switch feature', captured.last_system)

    captured.picker.actions[2].fn(entry)
    assert.equals('feature', captured.browse_branch)
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

    assert.equals('Commits (main · 2)> ', captured.picker.prompt)
    assert.equals('show', captured.picker.actions[1].label)

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
  end)

  it('lists worktrees and switches directories', function()
    local ctx = {
      root = '/repo',
    }

    require('forge.pickers').worktrees(ctx)
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('Worktrees (2)> ', captured.picker.prompt)

    local entry = captured.picker.entries[2]
    captured.picker.actions[1].fn(entry)

    assert.equals('cd /repo-feature', captured.cmd)
    assert.is_true(captured.cleared)
  end)
end)
