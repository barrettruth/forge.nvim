vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('review session', function()
  local review

  before_each(function()
    package.loaded['forge.review'] = nil
    review = require('forge.review')
    review.stop()
  end)

  after_each(function()
    review.stop()
    package.loaded['forge.review'] = nil
  end)

  it('stores a first-class session in review state', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      mode = 'patch',
      files = {
        { path = 'lua/forge/review.lua' },
      },
      current_file = 'lua/forge/review.lua',
      materialization = 'checkout',
      repo_root = '/repo',
    })

    assert.equals('origin/main', review.state.base)
    assert.equals('unified', review.state.mode)
    assert.equals('pr', review.current().subject.kind)
    assert.equals('42', review.current().subject.id)
    assert.equals('PR #42', review.current().subject.label)
    assert.equals('origin/main', review.current().subject.base_ref)
    assert.equals('pr-42', review.current().subject.head_ref)
    assert.equals('patch', review.current().mode)
    assert.equals('lua/forge/review.lua', review.current().current_file)
    assert.equals('checkout', review.current().materialization)
    assert.equals('/repo', review.current().repo_root)
  end)

  it('keeps the legacy start helper available', function()
    review.start('origin/main')

    assert.equals('origin/main', review.state.base)
    assert.equals('unified', review.state.mode)
    assert.equals('ref', review.current().subject.kind)
    assert.equals('origin/main', review.current().subject.base_ref)
    assert.equals('patch', review.current().mode)
  end)

  it('clears session state on stop', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      repo_root = '/repo',
    })

    review.stop()

    assert.is_nil(review.state.base)
    assert.equals('unified', review.state.mode)
    assert.is_nil(review.current())
  end)
end)

describe('review index', function()
  local captured
  local review
  local old_system
  local old_cmd
  local old_filereadable
  local old_tempname
  local old_preload

  before_each(function()
    captured = { systems = {} }
    old_system = vim.system
    old_cmd = vim.cmd
    old_filereadable = vim.fn.filereadable
    old_tempname = vim.fn.tempname
    old_preload = {
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
      ['diffs.commands'] = package.preload['diffs.commands'],
    }

    vim.system = function(cmd, _, cb)
      captured.system = cmd
      captured.systems[#captured.systems + 1] = cmd
      local key = table.concat(cmd, ' ')
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      if
        key
        == 'git -C /repo diff --name-status --find-renames --find-copies --no-ext-diff origin/main'
      then
        result.stdout = table.concat({
          'M\tlua/forge/review.lua',
          'R100\tlua/forge/old.lua\tlua/forge/new.lua',
        }, '\n')
      elseif key == 'sh -c echo main' then
        result.stdout = 'main\n'
      elseif
        key
        == 'git -C /tmp/forge-review diff --name-status --find-renames --find-copies --no-ext-diff def456'
      then
        result.stdout = 'M\tlua/forge/review.lua\n'
      elseif key == 'git -C /repo rev-list --parents -n 1 abc123' then
        result.stdout = 'abc123 def456\n'
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
      captured.cmds = captured.cmds or {}
      captured.cmds[#captured.cmds + 1] = cmd
    end

    vim.fn.filereadable = function()
      return 1
    end

    vim.fn.tempname = function()
      return '/tmp/forge-review'
    end

    package.preload['forge.logger'] = function()
      return {
        error = function(msg)
          captured.error = msg
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

    package.preload['diffs.commands'] = function()
      return {
        gdiff = function(base)
          captured.gdiff = base
        end,
      }
    end

    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['diffs.commands'] = nil
    package.loaded['forge.review'] = nil
    review = require('forge.review')
    review.stop()
  end)

  after_each(function()
    vim.system = old_system
    vim.cmd = old_cmd
    vim.fn.filereadable = old_filereadable
    vim.fn.tempname = old_tempname
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.preload['diffs.commands'] = old_preload['diffs.commands']
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['diffs.commands'] = nil
    package.loaded['forge.review'] = nil
  end)

  it('opens a picker-backed changed-files review index', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      repo_root = '/repo',
    })

    review.open_index()

    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    local found = false
    local expected = {
      'git',
      '-C',
      '/repo',
      'diff',
      '--name-status',
      '--find-renames',
      '--find-copies',
      '--no-ext-diff',
      'origin/main',
    }
    for _, cmd in ipairs(captured.systems) do
      if vim.deep_equal(expected, cmd) then
        found = true
        break
      end
    end
    assert.is_true(found)
    assert.equals('Review Files: Patch (2)> ', captured.picker.prompt)
    assert.equals('M', captured.picker.entries[1].display[1][1])
    assert.equals('lua/forge/review.lua', captured.picker.entries[1].value.path)
    assert.equals('lua/forge/new.lua', captured.picker.entries[2].value.path)
    assert.equals('lua/forge/old.lua', captured.picker.entries[2].value.old_path)

    captured.picker.actions[1].fn(captured.picker.entries[1])

    assert.equals('diffoff!', captured.cmds[1])
    assert.equals('edit /repo/lua/forge/review.lua', captured.cmds[2])
    assert.equals('origin/main', captured.gdiff)
  end)

  it('preserves back callbacks on the review files picker', function()
    local back_calls = 0

    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      repo_root = '/repo',
      back = function()
        back_calls = back_calls + 1
      end,
    })

    review.open_index()

    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.is_function(captured.picker.back)

    captured.picker.back()

    assert.equals(1, back_calls)
  end)

  it('toggles the active file between patch and context modes', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      mode = 'patch',
      current_file = 'lua/forge/review.lua',
      repo_root = '/repo',
    })

    review.toggle()

    assert.equals('split', review.state.mode)
    assert.equals('context', review.current().mode)
    assert.equals('diffoff!', captured.cmds[1])
    assert.equals('edit /repo/lua/forge/review.lua', captured.cmds[2])
    assert.equals('Gvdiffsplit origin/main', captured.cmds[3])
  end)

  it('moves to the next review file in session order', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      mode = 'patch',
      files = {
        { path = 'lua/forge/review.lua' },
        { path = 'lua/forge/new.lua' },
      },
      current_file = 'lua/forge/review.lua',
      repo_root = '/repo',
    })

    review.next_file()

    assert.equals('lua/forge/new.lua', review.current().current_file)
    assert.equals('edit /repo/lua/forge/new.lua', captured.cmds[2])
  end)

  it('wraps patch hunk navigation inside the current diff buffer', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      mode = 'patch',
      repo_root = '/repo',
    })

    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'diff --git a/file b/file',
      '@@ -1,1 +1,1 @@',
      '-old',
      '+new',
      '@@ -10,1 +10,1 @@',
      '-old2',
      '+new2',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    review.next_hunk()
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

    review.next_hunk()
    assert.same({ 5, 0 }, vim.api.nvim_win_get_cursor(0))

    review.next_hunk()
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('starts branch review against the detected default base', function()
    review.start_branch({
      root = '/repo',
      branch = 'feature',
      forge = {
        default_branch_cmd = function()
          return { 'sh', '-c', 'echo main' }
        end,
      },
    }, 'feature')

    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('branch', review.current().subject.kind)
    assert.equals('origin/main', review.current().subject.base_ref)
    assert.equals('current', review.current().materialization)
    assert.equals('Review Files: Patch (2)> ', captured.picker.prompt)
  end)

  it('starts commit review in a detached worktree and cleans it up on stop', function()
    review.start_commit({
      root = '/repo',
      head = 'abc123',
    }, 'abc123')

    vim.wait(100, function()
      return captured.picker ~= nil
    end)

    assert.equals('commit', review.current().subject.kind)
    assert.equals('def456', review.current().subject.base_ref)
    assert.equals('worktree', review.current().materialization)
    assert.equals('/tmp/forge-review', review.current().worktree_path)

    review.stop()

    assert.same(
      { 'git', '-C', '/repo', 'worktree', 'remove', '--force', '/tmp/forge-review' },
      captured.systems[#captured.systems]
    )
  end)
end)
