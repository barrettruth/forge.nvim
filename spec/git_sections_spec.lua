vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local cache
local old_preload
local old_system
local old_cmd
local old_ui_input
local old_win_get_width

local field_sep = string.char(31)
local record_sep = string.char(30)

local function record(fields)
  return table.concat(fields, field_sep) .. record_sep
end

describe('git sections', function()
  before_each(function()
    captured = { systems = {}, input_value = 'new-tree' }
    cache = {}
    local now = os.time()

    old_system = vim.system
    old_cmd = vim.cmd
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

      if key == 'git for-each-ref --format=%(upstream:short) refs/heads/main' then
        result.stdout = 'origin/main\n'
      elseif key == 'git for-each-ref --format=%(upstream:short) refs/heads/topic' then
        result.stdout = '\n'
      elseif key:match('^git for%-each%-ref ') then
        result.stdout = table.concat({
          '*\tmain\torigin/main\tabc1234\tMain branch',
          ' \tfeature\torigin/feature\tdef5678\tFeature branch',
          ' \ttopic\t\t789abcd\tTopic branch',
        }, '\n')
      elseif key:match('^git log ') then
        result.stdout = record({
          'abc123456789',
          'abc1234',
          'Add routes',
          'Barrett',
          tostring(now - 7200),
        }) .. record({
          'def567890123',
          'def5678',
          'Add sections',
          'B',
          tostring(now - 3600),
        })
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
      local picker = dofile(vim.fn.getcwd() .. '/lua/forge/picker/init.lua')
      return vim.tbl_extend('force', picker, {
        backend = function()
          return 'fzf-lua'
        end,
        pick = function(opts)
          captured.picker = opts
        end,
      })
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
        config = require('forge.config').config,
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

    assert.equals('Branches (3)> ', captured.picker.prompt)
    assert.equals('default', captured.picker.actions[1].name)
    assert.equals('switch', captured.picker.actions[1].label)
    assert.equals('browse', captured.picker.actions[2].name)
    assert.equals('review', captured.picker.actions[3].name)
    assert.equals('delete', captured.picker.actions[4].name)
    assert.equals('yank', captured.picker.actions[5].name)
    assert.same({ '* ', 'ForgePass' }, captured.picker.entries[1].display[1])
    assert.same({ 'main   ', 'ForgeBranchCurrent' }, captured.picker.entries[1].display[2])
    assert.equals('[origin/main]', vim.trim(captured.picker.entries[1].display[3][1]))
    assert.equals('Directory', captured.picker.entries[1].display[3][2])
    assert.equals('Main branch', vim.trim(captured.picker.entries[1].display[4][1]))
    assert.equals('ForgeDim', captured.picker.entries[1].display[4][2])

    assert.same({ '+ ', 'ForgeBranch' }, captured.picker.entries[2].display[1])
    assert.same({ 'feature', 'ForgeBranch' }, captured.picker.entries[2].display[2])
    assert.equals('[origin/feature]', vim.trim(captured.picker.entries[2].display[3][1]))
    assert.equals('Directory', captured.picker.entries[2].display[3][2])
    assert.equals('Feature branch', vim.trim(captured.picker.entries[2].display[4][1]))
    assert.equals('ForgeDim', captured.picker.entries[2].display[4][2])

    assert.same({ '  ', 'ForgeDim' }, captured.picker.entries[3].display[1])
    assert.same({ 'topic  ' }, captured.picker.entries[3].display[2])
    assert.equals('', vim.trim(captured.picker.entries[3].display[3][1]))
    assert.equals('Topic branch', vim.trim(captured.picker.entries[3].display[4][1]))
    assert.equals('ForgeDim', captured.picker.entries[3].display[4][2])
    assert.equals('main', require('forge.picker').search_key('branch', captured.picker.entries[1]))
    assert.equals(
      'feature',
      require('forge.picker').search_key('branch', captured.picker.entries[2])
    )
    assert.equals('topic', require('forge.picker').search_key('branch', captured.picker.entries[3]))

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

    assert.equals('Commits on main (2)> ', captured.picker.prompt)
    assert.equals('show', captured.picker.actions[1].label)
    assert.equals('web', captured.picker.actions[2].label)
    assert.equals('review', captured.picker.actions[3].label)
    assert.equals(
      'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main',
      captured.last_system
    )
    assert.same({
      { 'abc1234', 'ForgeCommitHash' },
      { ' Add routes  ' },
      { ' Barrett ', 'ForgeCommitAuthor' },
      { ' 2h', 'ForgeCommitTime' },
    }, captured.picker.entries[1].display)
    assert.same({
      { 'def5678', 'ForgeCommitHash' },
      { ' Add sections' },
      { ' B       ', 'ForgeCommitAuthor' },
      { ' 1h', 'ForgeCommitTime' },
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

  it('falls back to the local branch when no upstream is configured', function()
    require('forge.pickers').commits({}, 'topic')
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('Commits on topic (2)> ', captured.picker.prompt)
    assert.equals(
      'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e topic',
      captured.last_system
    )
  end)

  it('falls back to the local branch when the upstream log fetch fails and trims commit fields', function()
    local ctx = {
      forge = {
        browse_commit = function(_, sha)
          captured.browse_commit = sha
        end,
      },
    }
    local current_system = vim.system
    vim.system = function(cmd, _, cb)
      local key = table.concat(cmd, ' ')
      captured.last_system = key
      captured.systems[#captured.systems + 1] = key
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }

      if key == 'git for-each-ref --format=%(upstream:short) refs/heads/main' then
        result.stdout = 'origin/main\n'
      elseif key == 'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main' then
        result.code = 128
        result.stderr = 'fatal: bad revision origin/main'
      elseif key == 'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e main' then
        local now = os.time()
        result.stdout = record({
          'abc123456789',
          'abc1234',
          'Add routes',
          'Barrett',
          tostring(now - 7200),
        }) .. '\n' .. record({
          'def567890123',
          'def5678',
          'Add sections',
          'B',
          tostring(now - 3600),
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

    require('forge.pickers').commits(ctx, 'main')
    vim.wait(100, function()
      return captured.picker ~= nil and captured.last_system == 'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e main'
    end)
    vim.system = current_system

    assert.equals(
      'git log --max-count=101 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e main',
      captured.last_system
    )
    assert.same({
      { 'def5678', 'ForgeCommitHash' },
      { ' Add sections' },
      { ' B       ', 'ForgeCommitAuthor' },
      { ' 1h', 'ForgeCommitTime' },
    }, captured.picker.entries[2].display)

    captured.picker.actions[2].fn(captured.picker.entries[2])
    assert.equals('def567890123', captured.browse_commit)
  end)

  it('adds a load more row when the commit list exceeds the configured limit', function()
    vim.g.forge = {
      display = {
        limits = {
          commits = 2,
        },
      },
    }

    local current_system = vim.system
    vim.system = function(cmd, _, cb)
      local key = table.concat(cmd, ' ')
      captured.last_system = key
      captured.systems[#captured.systems + 1] = key
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }

      if key == 'git for-each-ref --format=%(upstream:short) refs/heads/main' then
        result.stdout = 'origin/main\n'
      elseif
        key == 'git log --max-count=3 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main'
      then
        local now = os.time()
        result.stdout = record({
          'abc123456789',
          'abc1234',
          'Add routes',
          'Barrett',
          tostring(now - 7200),
        }) .. record({
          'def567890123',
          'def5678',
          'Add sections',
          'B',
          tostring(now - 3600),
        }) .. record({
          'fedcba987654',
          'fedcba9',
          'Add tests',
          'C',
          tostring(now - 1800),
        })
      elseif
        key == 'git log --max-count=5 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main'
      then
        local now = os.time()
        result.stdout = record({
          'abc123456789',
          'abc1234',
          'Add routes',
          'Barrett',
          tostring(now - 7200),
        }) .. record({
          'def567890123',
          'def5678',
          'Add sections',
          'B',
          tostring(now - 3600),
        }) .. record({
          'fedcba987654',
          'fedcba9',
          'Add tests',
          'C',
          tostring(now - 1800),
        }) .. record({
          '0123456789ab',
          '0123456',
          'Add docs',
          'D',
          tostring(now - 900),
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

    require('forge.pickers').commits({}, 'main')
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals(
      'git log --max-count=3 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main',
      captured.last_system
    )
    assert.equals('Load more...', captured.picker.entries[3].display[1][1])
    assert.is_true(captured.picker.entries[3].load_more)

    captured.picker.actions[1].fn(captured.picker.entries[3])
    vim.wait(100, function()
      return captured.picker and captured.picker.prompt == 'Commits on main (4)> '
    end)
    vim.system = current_system

    assert.equals(
      'git log --max-count=5 --format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1e origin/main',
      captured.last_system
    )
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
    assert.equals('switch cwd', captured.picker.actions[1].label)
    assert.equals('add', captured.picker.actions[2].name)
    assert.equals('delete', captured.picker.actions[3].name)
    assert.same({ '* ', 'ForgePass' }, captured.picker.entries[1].display[1])
    assert.equals('main', vim.trim(captured.picker.entries[1].display[2][1]))
    assert.equals('ForgeBranchCurrent', captured.picker.entries[1].display[2][2])
    assert.equals('/repo', vim.trim(captured.picker.entries[1].display[3][1]))
    assert.equals('Directory', captured.picker.entries[1].display[3][2])
    assert.same({ ' abc1234', 'ForgeCommitHash' }, captured.picker.entries[1].display[4])

    assert.same({ '  ', 'ForgeDim' }, captured.picker.entries[2].display[1])
    assert.equals('feature', vim.trim(captured.picker.entries[2].display[2][1]))
    assert.equals(
      'main',
      require('forge.picker').search_key('worktree', captured.picker.entries[1])
    )
    assert.equals(
      'feature',
      require('forge.picker').search_key('worktree', captured.picker.entries[2])
    )
    assert.equals('ForgeBranch', captured.picker.entries[2].display[2][2])
    assert.equals('/repo-feature', vim.trim(captured.picker.entries[2].display[3][1]))
    assert.equals('Directory', captured.picker.entries[2].display[3][2])
    assert.same({ ' def5678', 'ForgeCommitHash' }, captured.picker.entries[2].display[4])

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
    captured.input_value = 'y'
    captured.picker.actions[3].fn(entry)
    assert.equals('Delete worktree /repo-feature? [y/N] ', captured.input_prompt)
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
      'feature/some-long-worktree-branch-name',
      vim.trim(captured.picker.entries[1].display[2][1])
    )
  end)

  it('expands outlier worktree branch labels when the picker has spare width', function()
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
            'branch refs/heads/main',
            '',
            'worktree /repo-issue-117',
            'HEAD 1c6fe7612345',
            'branch refs/heads/fix/yaml-parser-requirement',
            '',
            'worktree /repo-issue-74',
            'HEAD a73818212345',
            'branch refs/heads/fix/github-ci-refresh-ux',
            '',
            'worktree /repo-issue-75',
            'HEAD 3a4198412345',
            'branch refs/heads/fix/commit-picker-yank-state',
            '',
            'worktree /repo-issues-119-113',
            'HEAD 861293612345',
            'branch refs/heads/fix/commit-picker-upstream-load-more',
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
      'fix/commit-picker-upstream-load-more',
      vim.trim(captured.picker.entries[5].display[2][1])
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
      vim.trim(captured.picker.entries[1].display[3][1])
    )
    assert.equals(
      vim.fn.pathshorten(vim.fn.fnamemodify(nested_path, ':~')),
      vim.trim(captured.picker.entries[2].display[3][1])
    )
  end)

  it('expands worktree paths beyond the default name width when space is available', function()
    local home = vim.env.HOME or '/home/barrett'
    local current_path = home .. '/dev/forge.nvim'
    local yaml_path = home .. '/dev/forge.nvim-yaml-template-failure'
    local nested_path = home .. '/dev/forge.nvim/.claude/worktrees/agent-a43cb846'

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
            'worktree ' .. current_path,
            'HEAD 73eb02012345',
            'branch refs/heads/main',
            '',
            'worktree ' .. (home .. '/dev/forge.nvim-issue-117'),
            'HEAD 1c6fe7612345',
            'branch refs/heads/fix/yaml-parser-requirement',
            '',
            'worktree ' .. (home .. '/dev/forge.nvim-picker-search-keys'),
            'HEAD a2fef9a12345',
            'branch refs/heads/fix/picker-search-keys',
            '',
            'worktree ' .. yaml_path,
            'HEAD e566fa912345',
            'branch refs/heads/fix/yaml-template-parser-failure',
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
      vim.fn.fnamemodify(yaml_path, ':~'),
      vim.trim(captured.picker.entries[4].display[3][1])
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
    captured.input_value = 'y'
    delete_action.fn(delete_entry)
    assert.equals('Delete branch topic? [y/N] ', captured.input_prompt)
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git branch --delete topic')
    end)
    assert.is_true(vim.tbl_contains(captured.systems, 'git branch --delete topic'))
  end)


  it('skips branch and worktree delete prompts when confirmation is disabled', function()
    vim.g.forge = {
      confirm = {
        branch_delete = false,
        worktree_delete = false,
      },
    }

    require('forge.pickers').branches({
      id = 'current',
      root = '/repo',
    })
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    local branch_delete
    for _, action in ipairs(captured.picker.actions) do
      if action.name == 'delete' then
        branch_delete = action
        break
      end
    end

    branch_delete.fn(captured.picker.entries[3])
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git branch --delete topic')
    end)
    assert.is_nil(captured.input_prompt)

    captured.picker = nil
    require('forge.pickers').worktrees({ root = '/repo' })
    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    captured.picker.actions[3].fn(captured.picker.entries[2])
    vim.wait(100, function()
      return vim.tbl_contains(captured.systems, 'git worktree remove /repo-feature')
    end)
    assert.is_nil(captured.input_prompt)
  end)
end)
