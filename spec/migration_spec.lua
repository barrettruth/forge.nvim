local migration = require('forge.migration')

local github = 'https://github.com/barrettruth/forge.nvim'
local message = table.concat({
  '[forge.nvim] This repository will be removed from GitHub on October 31, 2026.',
  'Install from Forgejo: https://forge.barrettruth.com/barrettruth/forge.nvim.',
  'See :help forge-migration.',
}, ' ')

describe('migration origins', function()
  it('matches each supported GitHub URL and suffix', function()
    for _, origin in ipairs({
      github,
      'http://github.com/barrettruth/forge.nvim',
      'git://github.com/barrettruth/forge.nvim',
      'ssh://git@github.com/barrettruth/forge.nvim',
      'git@github.com:barrettruth/forge.nvim',
    }) do
      for _, suffix in ipairs({ '', '/', '.git', '.git///' }) do
        assert.is_true(migration.is_github_origin(origin .. suffix))
      end
    end
  end)

  it('rejects other repositories, hosts, and non-string values', function()
    for _, origin in ipairs({
      'https://forge.barrettruth.com/barrettruth/forge.nvim',
      'https://github.com/other/forge.nvim',
      'https://github.com/barrettruth/other.nvim',
      'https://github.com.evil/barrettruth/forge.nvim',
      github .. '/issues',
      '',
      false,
      1,
      {},
    }) do
      assert.is_false(migration.is_github_origin(origin))
    end
    assert.is_false(migration.is_github_origin(nil))
  end)
end)

describe('the migration check', function()
  local sent, scheduled, notices, on_exit
  local system, sync, executable, schedule, notify

  before_each(function()
    sent, scheduled, notices, on_exit = {}, {}, {}, nil
    system = stub(vim, 'system', function(cmd, opts, callback)
      sent[#sent + 1] = { cmd = cmd, opts = opts }
      on_exit = callback
      return {
        wait = function()
          error('unexpected wait')
        end,
      }
    end)
    sync = stub(vim.fn, 'system', function()
      error('unexpected synchronous process')
    end)
    executable = stub(vim.fn, 'executable', function(cmd)
      assert.equals('git', cmd)
      return 1
    end)
    schedule = stub(vim, 'schedule', function(callback)
      scheduled[#scheduled + 1] = callback
    end)
    notify = stub(vim, 'notify_once', function(text, level)
      notices[#notices + 1] = { text = text, level = level }
    end)
  end)

  after_each(function()
    system:revert()
    sync:revert()
    executable:revert()
    schedule:revert()
    notify:revert()
  end)

  it('starts Git with a callback and returns before the result', function()
    migration.warn_if_github_source('/plugin with spaces')
    assert.same({
      {
        cmd = { 'git', '-C', '/plugin with spaces', 'config', '--get', 'remote.origin.url' },
        opts = { text = true },
      },
    }, sent)
    assert.equals('function', type(on_exit))
    assert.same({}, scheduled)
    assert.same({}, notices)
    assert.stub(sync).was_not_called()
  end)

  it('uses the plugin directory when no root is specified', function()
    migration.warn_if_github_source()
    assert.equals(migration.plugin_root(), sent[1].cmd[3])
  end)

  it('schedules the unchanged warning after trimming Git output', function()
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 0, stdout = '  ' .. github .. '.git\n' })
    assert.same({}, notices)
    assert.equals(1, #scheduled)
    scheduled[1]()
    assert.same({ { text = message, level = vim.log.levels.WARN } }, notices)
  end)

  it('does not warn for a Forgejo origin', function()
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 0, stdout = 'https://forge.barrettruth.com/barrettruth/forge.nvim\n' })
    scheduled[1]()
    assert.same({}, notices)
  end)

  it('ignores empty output', function()
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 0, stdout = '' })
    scheduled[1]()
    assert.same({}, notices)
  end)

  it('ignores missing output', function()
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 0 })
    assert.same({}, scheduled)
    assert.same({}, notices)
  end)

  it('ignores unsuccessful Git commands even with matching output', function()
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 1, stdout = github, stderr = 'git failed' })
    assert.same({}, scheduled)
    assert.same({}, notices)
  end)

  it('does not start a process when Git is absent', function()
    executable:revert()
    executable = stub(vim.fn, 'executable', function()
      return 0
    end)
    migration.warn_if_github_source('/plugin')
    assert.same({}, sent)
    assert.same({}, scheduled)
    assert.same({}, notices)
  end)

  it('ignores process startup errors', function()
    system:revert()
    system = stub(vim, 'system', function()
      error('cannot start git')
    end)
    assert.has_no.errors(function()
      migration.warn_if_github_source('/plugin')
    end)
    assert.same({}, scheduled)
    assert.same({}, notices)
  end)

  it('does not raise from a notification callback', function()
    notify:revert()
    notify = stub(vim, 'notify_once', function()
      error('notification failed')
    end)
    migration.warn_if_github_source('/plugin')
    on_exit({ code = 0, stdout = github })
    assert.has_no.errors(scheduled[1])
  end)
end)
