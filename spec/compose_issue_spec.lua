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
      create_issue_cmd = function(_, title, body, labels, ref, metadata)
        captured.args = {
          title = title,
          body = body,
          labels = labels,
          ref = ref,
          metadata = metadata,
        }
        return { 'create-issue', title, body }
      end,
    }

    compose.open_issue(f)

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_false(vim.tbl_contains(lines, '  Labels: '))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: '))
    assert.is_false(vim.tbl_contains(lines, '  Milestone: '))
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# test issue' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      title = 'test issue',
      body = '',
      labels = {},
      ref = nil,
      metadata = {
        labels = {},
        assignees = {},
        milestone = '',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.warns)
    assert.same({}, captured.errors)
  end)

  it('keeps template labels without rendering editable metadata', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      create_issue_cmd = function(_, title, body, labels, ref, metadata)
        captured.args = {
          title = title,
          body = body,
          labels = labels,
          ref = ref,
          metadata = metadata,
        }
        return { 'create-issue', title, body }
      end,
    }

    compose.open_issue(f, {
      title = 'template issue',
      body = '',
      labels = { 'bug' },
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_true(vim.tbl_contains(lines, '  Labels: bug'))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: '))
    assert.is_false(vim.tbl_contains(lines, '  Milestone: '))
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# template issue done' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      title = 'template issue done',
      body = '',
      labels = { 'bug' },
      ref = nil,
      metadata = {
        labels = { 'bug' },
        assignees = {},
        milestone = '',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
  end)

  it('renders template assignees into the metadata block and extracts them on write', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      create_issue_cmd = function(_, title, body, labels, ref, metadata)
        captured.args = {
          title = title,
          body = body,
          labels = labels,
          ref = ref,
          metadata = metadata,
        }
        return { 'create-issue', title, body }
      end,
    }

    compose.open_issue(f, {
      title = 'template issue',
      body = '',
      labels = { 'bug' },
      assignees = { 'alice' },
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_true(vim.tbl_contains(lines, '  Assignees: alice'))
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# template issue done' })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      title = 'template issue done',
      body = '',
      labels = { 'bug' },
      ref = nil,
      metadata = {
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = '',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
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

  it('extracts issue metadata from the comment block on write', function()
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
      update_issue_cmd = function(_, num, title, body, ref, metadata)
        captured.args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-issue', num, title, body }
      end,
    }

    compose.open_issue_edit(f, '42', original)

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_true(vim.tbl_contains(lines, '  Labels: bug'))
    assert.is_true(vim.tbl_contains(lines, '  Assignees: alice'))
    assert.is_true(vim.tbl_contains(lines, '  Milestone: v1'))
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
      '  Write (:w) submits this buffer.',
      '  Quit or delete without ! keeps modified-buffer protection.',
      '  Use :q!, :bd!, or :bwipeout! to discard it.',
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
      ref = nil,
      metadata = {
        labels = { 'bug', 'docs' },
        assignees = { 'alice', 'bob' },
        milestone = 'v2',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.warns)
    assert.same({}, captured.errors)
  end)

  it('omits empty issue metadata lines in the comment block', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      update_issue_cmd = function(_, num, title, body, ref, metadata)
        captured.args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-issue', num, title, body }
      end,
    }

    compose.open_issue_edit(f, '42', {
      title = 'existing issue',
      body = 'body',
      labels = {},
      assignees = {},
      milestone = '',
    })

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is_false(vim.tbl_contains(lines, '  Labels: '))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: '))
    assert.is_false(vim.tbl_contains(lines, '  Milestone: '))
  end)

  it('treats a broken comment opener as body text on write', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      update_issue_cmd = function(_, num, title, body, ref, metadata)
        captured.args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-issue', num, title, body }
      end,
    }

    compose.open_issue_edit(f, '42', {
      title = 'existing issue',
      body = '',
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated issue',
      '',
      '<! --',
      '  Labels: docs',
      '  Assignees: bob',
      '  Milestone: v2',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      num = '42',
      title = 'updated issue',
      body = '<! --\n  Labels: docs\n  Assignees: bob\n  Milestone: v2\n-->',
      ref = nil,
      metadata = {
        labels = {},
        assignees = {},
        milestone = '',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
  end)

  it('parses metadata to end of buffer when the closer is removed', function()
    local compose = require('forge.compose')
    local f = {
      name = 'github',
      update_issue_cmd = function(_, num, title, body, ref, metadata)
        captured.args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-issue', num, title, body }
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
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated issue',
      '',
      '',
      '<!--',
      '  Labels: docs',
      '  Assignees: bob',
      '  Milestone: v2',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      num = '42',
      title = 'updated issue',
      body = '',
      ref = nil,
      metadata = {
        labels = { 'docs' },
        assignees = { 'bob' },
        milestone = 'v2',
        draft = false,
        reviewers = {},
      },
    }, captured.args)
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
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '#' })
    vim.cmd('write')

    assert.same({ 'aborting: empty title' }, captured.warns)
    assert.equals(0, captured.cleared)
    assert.is_nil(captured.args)
  end)
end)
