vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose split session', function()
  local captured
  local old_system
  local old_feedkeys
  local old_preload

  local function issue_forge()
    return {
      name = 'github',
      create_issue_cmd = function(_, title, body, labels, ref, metadata)
        captured.issue_args = {
          title = title,
          body = body,
          labels = labels,
          ref = ref,
          metadata = metadata,
        }
        return { 'create-issue', title, body }
      end,
    }
  end

  local function pr_forge()
    return {
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      name = 'github',
      update_pr_cmd = function(_, num, title, body, ref, metadata)
        captured.pr_args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-pr', num, title, body }
      end,
    }
  end

  before_each(function()
    captured = {
      cleared = 0,
      split = 'horizontal',
    }

    old_system = vim.system
    old_feedkeys = vim.api.nvim_feedkeys
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.config'] = package.preload['forge.config'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.system = function(_, _, cb)
      local result = {
        code = 0,
        stdout = 'https://github.com/owner/repo/issues/1\n',
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
        clear_list = function()
          captured.cleared = captured.cleared + 1
        end,
        current_scope = function()
          return {
            kind = 'github',
            host = 'github.com',
            slug = 'owner/repo',
          }
        end,
      }
    end

    package.preload['forge.config'] = function()
      return {
        config = function()
          return { split = captured.split }
        end,
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
    package.loaded['forge.config'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil

    vim.cmd('silent! only')
    vim.cmd('enew!')
  end)

  after_each(function()
    vim.system = old_system
    vim.api.nvim_feedkeys = old_feedkeys

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.config'] = old_preload['forge.config']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.config'] = nil
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
    vim.cmd('silent! only')
    vim.cmd('enew!')
  end)

  it('opens issue compose in a dedicated horizontal split', function()
    local compose = require('forge.compose')
    local base_win = vim.api.nvim_get_current_win()
    local base_buf = vim.api.nvim_get_current_buf()

    compose.open_issue(issue_forge())

    local compose_win = vim.api.nvim_get_current_win()
    local compose_buf = vim.api.nvim_get_current_buf()
    local base_pos = vim.api.nvim_win_get_position(base_win)
    local compose_pos = vim.api.nvim_win_get_position(compose_win)

    assert.is_not.equals(base_win, compose_win)
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(base_buf, vim.api.nvim_win_get_buf(base_win))
    assert.equals(compose_buf, vim.api.nvim_win_get_buf(compose_win))
    assert.equals(base_pos[2], compose_pos[2])
    assert.is_not.equals(base_pos[1], compose_pos[1])
  end)

  it('respects vertical split config for compose buffers', function()
    captured.split = 'vertical'

    local compose = require('forge.compose')
    local base_win = vim.api.nvim_get_current_win()

    compose.open_issue(issue_forge())

    local compose_win = vim.api.nvim_get_current_win()
    local base_pos = vim.api.nvim_win_get_position(base_win)
    local compose_pos = vim.api.nvim_win_get_position(compose_win)

    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(base_pos[1], compose_pos[1])
    assert.is_not.equals(base_pos[2], compose_pos[2])
  end)

  it('closes the issue compose split and returns focus to the prior buffer on success', function()
    local compose = require('forge.compose')
    local base_win = vim.api.nvim_get_current_win()
    local base_buf = vim.api.nvim_get_current_buf()

    compose.open_issue(issue_forge())

    local compose_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(compose_buf, 0, 1, false, { '# split issue' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.issue_args ~= nil and captured.cleared == 1
    end)

    assert.is_false(vim.api.nvim_buf_is_valid(compose_buf))
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(base_win, vim.api.nvim_get_current_win())
    assert.equals(base_buf, vim.api.nvim_get_current_buf())
  end)

  it('closes the PR edit compose split and returns focus to the prior buffer on success', function()
    local compose = require('forge.compose')
    local base_win = vim.api.nvim_get_current_win()
    local base_buf = vim.api.nvim_get_current_buf()

    compose.open_pr_edit(pr_forge(), '23', {
      title = 'PR title',
      body = 'PR body',
      draft = false,
      head_branch = 'feature',
      base_branch = 'main',
      reviewers = {},
      labels = {},
      assignees = {},
      milestone = '',
    }, 'feature')

    local compose_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(compose_buf, 0, -1, false, {
      '# updated pr',
      '',
      'updated body',
      '',
      '<!--',
      '  Draft: false',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.pr_args ~= nil and captured.cleared == 1
    end)

    assert.is_false(vim.api.nvim_buf_is_valid(compose_buf))
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(base_win, vim.api.nvim_get_current_win())
    assert.equals(base_buf, vim.api.nvim_get_current_buf())
  end)
end)
