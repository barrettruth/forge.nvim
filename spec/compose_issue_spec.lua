vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose issue create', function()
  local captured
  local old_system
  local old_preload

  before_each(function()
    captured = {
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
    }

    old_system = vim.system
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
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

    package.preload['forge'] = function()
      return {
        clear_list = function()
          captured.cleared = captured.cleared + 1
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
        warn = function(msg)
          table.insert(captured.warns, msg)
        end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
      }
    end

    package.preload['forge.template'] = function()
      return {
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

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == 'forge://issue/new'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('submits issues with an empty body', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      create_issue_cmd = function(_, title, body, labels, assignees, milestone, ref)
        captured.args = {
          title = title,
          body = body,
          labels = labels,
          assignees = assignees,
          milestone = milestone,
          ref = ref,
        }
        return { 'create-issue', title, body }
      end,
    }

    compose.open_issue(f)

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# test issue' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      title = 'test issue',
      body = '',
      labels = {},
      assignees = {},
      milestone = '',
      ref = nil,
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.warns)
    assert.same({}, captured.errors)
  end)

  it('submits issues when the clipboard register is unavailable', function()
    local old_setreg = vim.fn.setreg
    vim.fn.setreg = function()
      error('clipboard unavailable')
    end

    local compose = require('forge.compose')
    local f = {
      name = 'github',
      create_issue_cmd = function(_, title, body)
        captured.args = {
          title = title,
          body = body,
        }
        return { 'create-issue', title, body }
      end,
    }

    compose.open_issue(f)

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# clipboard fallback' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    vim.fn.setreg = old_setreg

    assert.same({
      title = 'clipboard fallback',
      body = '',
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.errors)
  end)
end)

describe('compose issue edit', function()
  local captured
  local old_system
  local old_preload

  before_each(function()
    captured = {
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
    }

    old_system = vim.system
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
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

    package.preload['forge'] = function()
      return {
        clear_list = function()
          captured.cleared = captured.cleared + 1
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
        warn = function(msg)
          table.insert(captured.warns, msg)
        end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
      }
    end

    package.preload['forge.template'] = function()
      return {
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

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf) == 'forge://issue/42/edit'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('submits issue edits with updated metadata and an empty body', function()
    local compose = require('forge.compose')
    local original = {
      title = 'existing issue',
      body = 'body',
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    }
    local f = {
      name = 'github',
      update_issue_cmd = function(_, num, title, body, labels, assignees, milestone, details, ref)
        captured.args = {
          num = num,
          title = title,
          body = body,
          labels = labels,
          assignees = assignees,
          milestone = milestone,
          details = details,
          ref = ref,
        }
        return { 'update-issue', num, title, body }
      end,
    }

    compose.open_issue_edit(f, '42', original)

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated issue',
      '',
      '',
      '<!--',
      '  Editing issue #42 via github.',
      '',
      '  Labels: bug, docs',
      '  Assignees: alice, bob',
      '  Milestone: v2',
      '',
      '  An empty title aborts editing.',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      num = '42',
      title = 'updated issue',
      body = '',
      labels = { 'bug', 'docs' },
      assignees = { 'alice', 'bob' },
      milestone = 'v2',
      details = original,
      ref = nil,
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.warns)
    assert.same({}, captured.errors)
  end)

  it('aborts issue editing when the title is empty', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      update_issue_cmd = function()
        return { 'update-issue' }
      end,
    }

    compose.open_issue_edit(f, '42', {
      title = 'existing issue',
      body = '',
      labels = {},
      assignees = {},
      milestone = '',
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '#' })
    vim.cmd('write')

    assert.same({ 'aborting: empty title' }, captured.warns)
    assert.equals(0, captured.cleared)
    assert.is_nil(captured.args)
  end)
end)
