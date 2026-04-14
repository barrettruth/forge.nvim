vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose abandon behavior', function()
  local old_system
  local old_preload
  local old_feedkeys

  before_each(function()
    old_system = vim.system
    old_feedkeys = vim.api.nvim_feedkeys
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.template'] = package.preload['forge.template'],
    }

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

    vim.api.nvim_feedkeys = function() end

    package.preload['forge'] = function()
      return {
        clear_list = function() end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end,
      }
    end

    package.preload['forge.template'] = function()
      return {
        fill_from_commits = function()
          return 'title', 'body'
        end,
        normalize_body = function(s)
          return vim.trim(s):gsub('%s+', ' ')
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.api.nvim_feedkeys = old_feedkeys

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^forge://') then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    vim.cmd('silent! %bwipeout!')
    vim.cmd('enew!')
  end)

  local function issue_forge()
    return {
      name = 'github',
      create_issue_cmd = function()
        return { 'create-issue' }
      end,
    }
  end

  local function pr_forge()
    return {
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      name = 'github',
    }
  end

  local function open_issue_buffer()
    local compose = require('forge.compose')
    compose.open_issue(issue_forge())
    return vim.api.nvim_get_current_buf()
  end

  local function open_modified_issue_window()
    vim.cmd('enew')
    local base = vim.api.nvim_get_current_buf()
    local buf = open_issue_buffer()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# changed title' })
    return base, buf
  end

  local function contains_line(lines, target)
    for _, line in ipairs(lines) do
      if line == target then
        return true
      end
    end
    return false
  end

  it('shows native discard guidance in issue compose buffers', function()
    open_issue_buffer()

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    assert.is_true(contains_line(lines, '  Writing (:w) submits this buffer.'))
    assert.is_true(
      contains_line(lines, '  Quitting or deleting without ! preserves modified-buffer protection.')
    )
    assert.is_true(contains_line(lines, '  Use :q!, :bd!, or :bwipeout! to discard it.'))
  end)

  it('shows native discard guidance in PR edit buffers', function()
    local compose = require('forge.compose')

    compose.open_pr_edit(pr_forge(), '23', {
      title = 'PR title',
      body = 'PR body',
      head_branch = 'feature',
      base_branch = 'main',
    }, 'feature')

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    assert.is_true(contains_line(lines, '  Writing (:w) submits this buffer.'))
    assert.is_true(
      contains_line(lines, '  Quitting or deleting without ! preserves modified-buffer protection.')
    )
    assert.is_true(contains_line(lines, '  Use :q!, :bd!, or :bwipeout! to discard it.'))
  end)

  it('keeps modified-buffer protection for :q', function()
    local _, buf = open_modified_issue_window()

    local ok, err = pcall(vim.cmd, 'q')

    assert.is_false(ok)
    assert.is_truthy(tostring(err):match('E37'))
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
  end)

  it('discards a modified compose buffer with :q!', function()
    local base, buf = open_modified_issue_window()

    vim.cmd('q!')

    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals(base, vim.api.nvim_get_current_buf())
  end)

  it('keeps modified-buffer protection for :bd and :bwipeout', function()
    local _, buf = open_modified_issue_window()

    local ok_bd, err_bd = pcall(vim.cmd, 'bd')
    assert.is_false(ok_bd)
    assert.is_truthy(tostring(err_bd):match('E89'))
    assert.is_true(vim.api.nvim_buf_is_valid(buf))

    local ok_bw, err_bw = pcall(vim.cmd, 'bwipeout')
    assert.is_false(ok_bw)
    assert.is_truthy(tostring(err_bw):match('E89'))
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
  end)

  it('discards a modified compose buffer with :bd! and :bwipeout!', function()
    local base, buf = open_modified_issue_window()

    vim.cmd('bd!')

    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals(base, vim.api.nvim_get_current_buf())

    local second_base, second_buf = open_modified_issue_window()

    vim.cmd('bwipeout!')

    assert.is_false(vim.api.nvim_buf_is_valid(second_buf))
    assert.equals(second_base, vim.api.nvim_get_current_buf())
  end)
end)
