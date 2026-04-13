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

  before_each(function()
    captured = {
      diff_stat = '',
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
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == 'forge://pr/new' then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
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
      assert.equals('  Write (:w) submits this buffer.', lines[creating_line + 10])
    end
  )
end)
