vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('term', function()
  local old_termopen
  local old_cmd
  local old_ui_open

  before_each(function()
    old_termopen = vim.fn.termopen
    old_cmd = vim.cmd
    old_ui_open = vim.ui.open
  end)

  after_each(function()
    vim.fn.termopen = old_termopen
    vim.cmd = old_cmd
    vim.ui.open = old_ui_open
    vim.cmd('silent! %bwipeout!')
    vim.cmd('enew!')
    package.loaded['forge.term'] = nil
  end)

  it('supports normal-mode terminal browse and enter callbacks', function()
    local started = {}
    local opened = {}
    local entered = 0

    vim.fn.termopen = function(cmd)
      started[#started + 1] = cmd
      return 1
    end
    vim.cmd = function(cmd)
      if cmd == 'startinsert' then
        error('startinsert should not run')
      end
      old_cmd(cmd)
    end
    vim.ui.open = function(url)
      opened[#opened + 1] = url
      return true
    end

    require('forge.term').open({ 'gh', 'run', 'view', '1' }, {
      url = 'https://example.com/runs/1',
      browse_fn = function()
        if #opened == 0 then
          return 'https://example.com/runs/1/job/2'
        end
        return nil
      end,
      enter_fn = function()
        entered = entered + 1
      end,
    })

    assert.same({ { 'gh', 'run', 'view', '1' } }, started)

    local browse = vim.fn.maparg('gx', 'n', false, true).callback
    local enter = vim.fn.maparg('<cr>', 'n', false, true).callback

    browse()
    browse()
    enter()

    assert.same({
      'https://example.com/runs/1/job/2',
      'https://example.com/runs/1',
    }, opened)
    assert.equals(1, entered)
  end)

  it('does not enter insert mode by default', function()
    local insert_count = 0

    vim.fn.termopen = function()
      return 1
    end
    vim.cmd = function(cmd)
      if cmd == 'startinsert' then
        insert_count = insert_count + 1
      end
      old_cmd(cmd)
    end

    require('forge.term').open({ 'gh', 'run', 'watch', '1' }, {})

    assert.equals(0, insert_count)
  end)

  it('enters insert mode when startinsert is explicitly true', function()
    local insert_count = 0

    vim.fn.termopen = function()
      return 1
    end
    vim.cmd = function(cmd)
      if cmd == 'startinsert' then
        insert_count = insert_count + 1
        return
      end
      old_cmd(cmd)
    end

    require('forge.term').open({ 'gh', 'run', 'watch', '1' }, {
      startinsert = true,
    })

    assert.equals(1, insert_count)
  end)

  it('maps q to close the terminal buffer in normal mode', function()
    vim.fn.termopen = function()
      return 1
    end

    require('forge.term').open({ 'gh', 'run', 'watch', '1' }, {})

    local buf = vim.api.nvim_get_current_buf()
    local close = vim.fn.maparg('q', 'n', false, true).callback
    assert.is_function(close)

    close()

    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)
end)
