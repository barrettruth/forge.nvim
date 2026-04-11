vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('shared operations', function()
  local captured
  local old_system
  local old_fn_system
  local old_ui_select
  local old_preload

  before_each(function()
    captured = {
      commands = {},
      infos = {},
      errors = {},
      sessions = {},
      opened = 0,
    }

    old_system = vim.system
    old_fn_system = vim.fn.system
    old_ui_select = vim.ui.select
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.review'] = package.preload['forge.review'],
    }

    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git branch --show-current' then
        return 'feature\n'
      end
      return ''
    end

    vim.system = function(cmd, _, cb)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      local key = table.concat(cmd, ' ')
      captured.commands[#captured.commands + 1] = key
      if key == 'pr-base 42' then
        result.stdout = 'main\n'
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

    vim.ui.select = function(_, _, cb)
      cb('Yes')
    end

    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          captured.infos[#captured.infos + 1] = msg
        end,
        error = function(msg)
          captured.errors[#captured.errors + 1] = msg
        end,
        debug = function() end,
        warn = function() end,
      }
    end

    package.preload['forge'] = function()
      return {
        remote_ref = function(_, branch)
          return 'origin/' .. branch
        end,
        open = function() end,
      }
    end

    package.preload['forge.review'] = function()
      return {
        start_session = function(session)
          captured.sessions[#captured.sessions + 1] = session
        end,
        open_index = function()
          captured.opened = captured.opened + 1
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.review'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.system = old_fn_system
    vim.ui.select = old_ui_select

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.review'] = old_preload['forge.review']

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.ops'] = nil
    package.loaded['forge.review'] = nil
  end)

  it('starts PR review sessions through the shared operation', function()
    local ops = require('forge.ops')
    ops.pr_review({
      labels = { pr_one = 'PR' },
      checkout_cmd = function(_, num)
        return { 'checkout', num }
      end,
      pr_base_cmd = function(_, num)
        return { 'pr-base', num }
      end,
    }, { num = '42' })

    vim.wait(100, function()
      return captured.opened == 1
    end)

    assert.same({ 'checkout 42', 'pr-base 42' }, captured.commands)
    assert.equals('origin/main', captured.sessions[1].subject.base_ref)
    assert.equals('feature', captured.sessions[1].subject.head_ref)
    assert.equals('/repo', captured.sessions[1].repo_root)
    assert.equals(1, captured.opened)
  end)

  it('runs PR close commands and success callbacks through the shared operation', function()
    local done = 0
    local ops = require('forge.ops')
    ops.pr_close({
      labels = { pr_one = 'PR' },
      close_cmd = function(_, num)
        return { 'close', num }
      end,
    }, { num = '42' }, {
      on_success = function()
        done = done + 1
      end,
    })

    vim.wait(100, function()
      return done == 1
    end)

    assert.same({ 'close 42' }, captured.commands)
    assert.equals(1, done)
  end)

  it('confirms release deletion before running the shared delete operation', function()
    local done = 0
    local ops = require('forge.ops')
    ops.release_delete({
      delete_release_cmd = function(_, tag)
        return { 'delete', tag }
      end,
    }, { tag = 'v1.2.3' }, {
      on_success = function()
        done = done + 1
      end,
    })

    vim.wait(100, function()
      return done == 1
    end)

    assert.same({ 'delete v1.2.3' }, captured.commands)
    assert.equals(1, done)
  end)
end)
