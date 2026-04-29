vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function extmark_groups_for_line(buf, target)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line_num
  for i, line in ipairs(lines) do
    if line == target then
      line_num = i
      break
    end
  end
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

describe('compose issue create', function()
  local captured
  local old_system
  local old_preload
  local old_wrap
  local old_conceallevel

  before_each(function()
    captured = {
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
    }

    old_system = vim.system
    old_wrap = vim.o.wrap
    old_conceallevel = vim.o.conceallevel
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.state'] = package.preload['forge.state'],
      ['forge.compose.template'] = package.preload['forge.compose.template'],
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
        current_scope = function()
          return {
            kind = 'github',
            host = 'github.com',
            slug = 'owner/repo',
          }
        end,
      }
    end
    package.preload['forge.state'] = function()
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

    package.preload['forge.compose.template'] = function()
      return {
        normalize_body = function(s)
          return vim.trim(s):gsub('%s+', ' ')
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.state'] = nil
    package.loaded['forge.compose.template'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.o.wrap = old_wrap
    vim.o.conceallevel = old_conceallevel

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.state'] = old_preload['forge.state']
    package.preload['forge.compose.template'] = old_preload['forge.compose.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.state'] = nil
    package.loaded['forge.compose.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf) == 'forge://github.com/owner/repo/issue/new'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('leaves issue create buffers at the default cursor and mode state', function()
    local compose = require('forge.compose')
    local old_set_cursor = vim.api.nvim_win_set_cursor
    local old_startinsert = vim.cmd.startinsert
    local cursor_calls = {}
    local startinsert_calls = {}

    vim.api.nvim_win_set_cursor = function(win, pos)
      cursor_calls[#cursor_calls + 1] = { win = win, pos = { pos[1], pos[2] } }
      return old_set_cursor(win, pos)
    end
    vim.cmd.startinsert = function(opts)
      startinsert_calls[#startinsert_calls + 1] = opts
    end

    local ok, err = pcall(function()
      compose.open_issue({
        name = 'github',
        create_issue_cmd = function()
          return { 'create-issue' }
        end,
      })
    end)

    vim.api.nvim_win_set_cursor = old_set_cursor
    vim.cmd.startinsert = old_startinsert

    if not ok then
      error(err)
    end

    assert.same({}, cursor_calls)
    assert.same({}, startinsert_calls)
    assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
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

  it('exposes public forge buffer metadata for issue compose buffers', function()
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

    compose.open_issue({
      name = 'github',
      create_issue_cmd = function()
        return { 'create-issue' }
      end,
    }, nil, ref)

    assert.same({
      version = 1,
      kind = 'issue',
      url = 'https://github.com/owner/repo',
    }, vim.b.forge)
  end)

  it(
    'keeps a single blank line between the forge line and instructions when metadata is empty',
    function()
      local compose = require('forge.compose')
      compose.open_issue({
        name = 'github',
        create_issue_cmd = function()
          return { 'create-issue' }
        end,
      })

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local creating_line
      for i, line in ipairs(lines) do
        if line == '  Creating issue via github.' then
          creating_line = i
          break
        end
      end

      assert.is_not_nil(creating_line)
      assert.equals('', lines[creating_line + 1])
      assert.equals('  Writing (:w) submits this buffer.', lines[creating_line + 2])
    end
  )

  it(
    'keeps compose extmarks selective instead of painting the whole scaffold as a comment',
    function()
      local compose = require('forge.compose')
      compose.open_issue({
        name = 'github',
        create_issue_cmd = function()
          return { 'create-issue' }
        end,
      })

      local ns = vim.api.nvim_get_namespaces().forge_compose
      local extmarks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      local saw_forge = false
      for _, extmark in ipairs(extmarks) do
        local details = extmark[4]
        if details.hl_group == 'ForgeComposeForge' then
          saw_forge = true
        end
        assert.is_not.equals('ForgeComposeComment', details.hl_group)
        assert.is_not.equals('ForgeComposeComment', details.line_hl_group)
      end

      assert.is_true(saw_forge)
    end
  )

  it('only accents the forge name on the issue create action line', function()
    local compose = require('forge.compose')
    compose.open_issue({
      name = 'github',
      create_issue_cmd = function()
        return { 'create-issue' }
      end,
    })

    assert.same({ 'ForgeComposeForge' }, extmark_groups_for_line(0, '  Creating issue via github.'))
  end)

  it('uses forgecompose and pinned compose window options for issue create', function()
    vim.o.wrap = true
    vim.o.conceallevel = 3

    local compose = require('forge.compose')
    compose.open_issue({
      name = 'github',
      create_issue_cmd = function()
        return { 'create-issue' }
      end,
    })

    assert.equals('forgecompose', vim.bo[0].filetype)
    assert.is_false(vim.wo[0].wrap)
    assert.equals(0, vim.wo[0].conceallevel)
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
  local old_wrap
  local old_conceallevel

  before_each(function()
    captured = {
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
    }

    old_system = vim.system
    old_wrap = vim.o.wrap
    old_conceallevel = vim.o.conceallevel
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.state'] = package.preload['forge.state'],
      ['forge.compose.template'] = package.preload['forge.compose.template'],
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
        current_scope = function()
          return {
            kind = 'github',
            host = 'github.com',
            slug = 'owner/repo',
          }
        end,
      }
    end
    package.preload['forge.state'] = function()
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

    package.preload['forge.compose.template'] = function()
      return {
        normalize_body = function(s)
          return vim.trim(s):gsub('%s+', ' ')
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.state'] = nil
    package.loaded['forge.compose.template'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.o.wrap = old_wrap
    vim.o.conceallevel = old_conceallevel

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.state'] = old_preload['forge.state']
    package.preload['forge.compose.template'] = old_preload['forge.compose.template']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.state'] = nil
    package.loaded['forge.compose.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf) == 'forge://github.com/owner/repo/issue/42/edit'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('leaves issue edit buffers at the default cursor and mode state', function()
    local compose = require('forge.compose')
    local old_set_cursor = vim.api.nvim_win_set_cursor
    local old_feedkeys = vim.api.nvim_feedkeys
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
      compose.open_issue_edit(
        {
          name = 'github',
          update_issue_cmd = function()
            return { 'update-issue' }
          end,
        },
        '42',
        {
          title = 'existing issue',
          body = 'body',
          labels = {},
          assignees = {},
          milestone = '',
        }
      )
    end)

    vim.api.nvim_win_set_cursor = old_set_cursor
    vim.api.nvim_feedkeys = old_feedkeys
    vim.cmd = old_cmd

    if not ok then
      error(err)
    end

    assert.same({}, cursor_calls)
    assert.same({}, feedkeys_calls)
    assert.is_false(vim.tbl_contains(cmd_calls, 'normal! v$h'))
    assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('only accents the forge name on the issue edit action line', function()
    local compose = require('forge.compose')
    compose.open_issue_edit(
      {
        name = 'github',
        update_issue_cmd = function()
          return { 'update-issue' }
        end,
      },
      '42',
      {
        title = 'existing issue',
        body = 'body',
        labels = {},
        assignees = {},
        milestone = '',
      }
    )

    assert.same(
      { 'ForgeComposeForge' },
      extmark_groups_for_line(0, '  Editing issue #42 via github.')
    )
  end)

  it('uses forgecompose and pinned compose window options for issue edit', function()
    vim.o.wrap = true
    vim.o.conceallevel = 3

    local compose = require('forge.compose')
    compose.open_issue_edit(
      {
        name = 'github',
        update_issue_cmd = function()
          return { 'update-issue' }
        end,
      },
      '42',
      {
        title = 'existing issue',
        body = 'body',
        labels = {},
        assignees = {},
        milestone = '',
      }
    )

    assert.equals('forgecompose', vim.bo[0].filetype)
    assert.is_false(vim.wo[0].wrap)
    assert.equals(0, vim.wo[0].conceallevel)
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
      '  Writing (:w) submits this buffer.',
      '  Quitting or deleting without ! preserves modified-buffer protection.',
      '  Use :q!, :bd!, or :bwipeout! to discard it.',
      '  Editing is aborted if the title is empty.',
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
