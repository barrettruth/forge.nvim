vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose pr create', function()
  local captured
  local old_fn_system
  local old_system
  local old_feedkeys
  local old_preload

  local function line_index(lines, target)
    for i, line in ipairs(lines) do
      if line == target then
        return i
      end
    end
    return nil
  end

  local function extmark_groups_for_line(buf, target)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_num = line_index(lines, target)
    assert.is_not_nil(line_num)
    local ns = vim.api.nvim_get_namespaces().forge_compose
    local extmarks = vim.api.nvim_buf_get_extmarks(
      buf,
      ns,
      { line_num - 1, 0 },
      { line_num - 1, -1 },
      { details = true }
    )
    local groups = {}
    for _, extmark in ipairs(extmarks) do
      table.insert(groups, extmark[4].hl_group)
    end
    table.sort(groups)
    return groups
  end

  before_each(function()
    captured = {
      diff_stat = '',
      remote_url = 'git@github.com:barrettruth/forge.nvim.git',
    }

    old_fn_system = vim.fn.system
    old_system = vim.system
    old_feedkeys = vim.api.nvim_feedkeys
    old_preload = {
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.api.nvim_feedkeys = function() end
    vim.fn.system = function(cmd)
      if cmd == 'git diff --stat origin/main..HEAD' then
        return captured.diff_stat
      end
      if cmd == 'git remote get-url origin' then
        return captured.remote_url
      end
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo'
      end
      return ''
    end
    vim.system = function(_, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    package.preload['forge.template'] = function()
      return {
        fill_from_commits = function()
          return 'test', '## Problem\n\n## Solution'
        end,
        normalize_body = function(s)
          return vim.trim(s):gsub('%s+', ' ')
        end,
      }
    end

    package.loaded['forge.compose'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_system
    vim.api.nvim_feedkeys = old_feedkeys

    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge.compose'] = nil
    package.loaded['forge.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf) == 'forge://github.com/barrettruth/forge.nvim/pr/new'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('pre-selects the PR title on create', function()
    local compose = require('forge.compose')
    local old_set_cursor = vim.api.nvim_win_set_cursor
    local old_feedkeys_local = vim.api.nvim_feedkeys
    local old_cmd = vim.cmd
    local cursor_calls = {}
    local feedkeys_calls = {}
    local cmd_calls = {}

    vim.api.nvim_win_set_cursor = function(win, pos)
      cursor_calls[#cursor_calls + 1] = { win = win, pos = { pos[1], pos[2] } }
      return old_set_cursor(win, pos)
    end
    vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
      feedkeys_calls[#feedkeys_calls + 1] = { keys = keys, mode = mode, escape_ks = escape_ks }
    end
    vim.cmd = function(cmd)
      cmd_calls[#cmd_calls + 1] = cmd
      return old_cmd(cmd)
    end

    local ok, err = pcall(function()
      compose.open_pr({
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        capabilities = { draft = true, reviewers = false },
        name = 'github',
      }, 'new', 'main', false, nil, nil, 'origin', 'origin/main', 'HEAD')
    end)

    vim.api.nvim_win_set_cursor = old_set_cursor
    vim.api.nvim_feedkeys = old_feedkeys_local
    vim.cmd = old_cmd

    if not ok then
      error(err)
    end

    assert.same({ { win = 0, pos = { 1, 2 } } }, cursor_calls)
    assert.is_true(vim.tbl_contains(cmd_calls, 'normal! v$h'))
    assert.equals(1, #feedkeys_calls)
  end)

  it(
    'orders the create footer from action to branch to metadata to diff stat to instructions',
    function()
      captured.diff_stat = ' lua/forge/pickers.lua | 1 +\n 1 file changed, 1 insertion(+)\n'

      local compose = require('forge.compose')
      compose.open_pr({
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        capabilities = { draft = true, reviewers = false },
        name = 'github',
      }, 'new', 'main', false, nil, nil, 'origin', 'origin/main', 'HEAD')

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local creating_line = line_index(lines, '  Creating Pull Request via github.')

      assert.is_not_nil(creating_line)
      assert.equals('  On branch new against main.', lines[creating_line + 1])
      assert.equals('', lines[creating_line + 2])
      assert.equals('  Draft: false', lines[creating_line + 3])
      assert.equals('', lines[creating_line + 4])
      assert.equals('  Changes not in origin/main:', lines[creating_line + 5])
      assert.equals('', lines[creating_line + 6])
      assert.equals('   lua/forge/pickers.lua | 1 +', lines[creating_line + 7])
      assert.equals('   1 file changed, 1 insertion(+)', lines[creating_line + 8])
      assert.equals('', lines[creating_line + 9])
      assert.equals('  Writing (:w) submits this buffer.', lines[creating_line + 10])
    end
  )

  it('keeps PR create accents narrow and splits mixed diff-stat runs', function()
    captured.diff_stat =
      ' lua/forge/pickers.lua | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)\n'

    local compose = require('forge.compose')
    compose.open_pr({
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      capabilities = { draft = true, reviewers = false },
      name = 'github',
    }, 'new', 'main', false, nil, nil, 'origin', 'origin/main', 'HEAD')

    assert.same(
      { 'ForgeComposeForge' },
      extmark_groups_for_line(0, '  Creating Pull Request via github.')
    )
    assert.same(
      { 'ForgeComposeBranch' },
      extmark_groups_for_line(0, '  Changes not in origin/main:')
    )
    assert.same(
      { 'ForgeComposeAdded', 'ForgeComposeFile', 'ForgeComposeRemoved' },
      extmark_groups_for_line(0, '   lua/forge/pickers.lua | 2 +-')
    )
    assert.same({}, extmark_groups_for_line(0, '   1 file changed, 1 insertion(+), 1 deletion(-)'))
  end)

  it('exposes public forge buffer metadata for PR compose buffers', function()
    local compose = require('forge.compose')
    local ref = {
      kind = 'github',
      host = 'github.com',
      slug = 'owner/repo',
      repo_arg = 'owner/repo',
      web_url = 'https://github.com/owner/repo',
      owner = 'owner',
      namespace = 'owner',
      repo = 'repo',
    }

    compose.open_pr({
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      capabilities = { draft = true, reviewers = false },
      name = 'github',
    }, 'new', 'main', false, nil, ref, 'origin', 'origin/main', 'HEAD')

    assert.same({
      version = 1,
      kind = 'pr',
      url = 'https://github.com/owner/repo',
    }, vim.b.forge)
  end)

  it('derives the public forge buffer URL from origin when scope is absent', function()
    local compose = require('forge.compose')

    compose.open_pr({
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      capabilities = { draft = true, reviewers = false },
      name = 'github',
    }, 'new', 'main', false, nil, nil, 'origin', 'origin/main', 'HEAD')

    assert.same({
      version = 1,
      kind = 'pr',
      url = 'https://github.com/barrettruth/forge.nvim',
    }, vim.b.forge)
  end)
end)
