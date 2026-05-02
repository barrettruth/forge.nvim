vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('detect', function()
  local detect = require('forge.detect')
  local old_executable
  local old_fn_system
  local old_system

  before_each(function()
    old_executable = vim.fn.executable
    old_fn_system = vim.fn.system
    old_system = vim.system
  end)

  after_each(function()
    vim.fn.executable = old_executable
    vim.fn.system = old_fn_system
    vim.system = old_system
    vim.g.forge = nil
    detect.clear_cache()
  end)

  it('detects and caches the current forge', function()
    local calls = {}
    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return old_executable(bin)
    end
    vim.fn.system = function(cmd)
      calls[#calls + 1] = cmd
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@github.com:owner/current.git\n'
      end
      return ''
    end
    vim.system = helpers.system_router({
      calls = calls,
      default = helpers.command_result('', 1),
    })

    local first = detect.detect()
    local second = detect.detect()

    assert.equals('github', first and first.name)
    assert.same(first, second)
    assert.same({
      'git rev-parse --show-toplevel',
      'git remote get-url origin',
    }, calls)
  end)

  it('detects a forge at an explicit root', function()
    vim.fn.executable = function(bin)
      if bin == 'gh' then
        return 1
      end
      return old_executable(bin)
    end
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      return ''
    end
    vim.system = helpers.system_router({
      responses = {
        ['git -C /repo remote get-url origin'] = helpers.command_result(
          'git@github.com:owner/current.git\n'
        ),
      },
      default = helpers.command_result('', 1),
    })

    local forge = detect.detect_at_root('/repo')

    assert.equals('github', forge and forge.name)
    assert.equals('github', detect.forge_name())
  end)

  it('detects Forgejo-family hosts from built-in source aliases', function()
    vim.fn.executable = function(bin)
      if bin == 'tea' then
        return 1
      end
      return old_executable(bin)
    end
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'git@codeberg.org:owner/current.git\n'
      end
      return ''
    end
    vim.system = helpers.system_router({
      default = helpers.command_result('', 1),
    })

    assert.equals('forgejo', detect.detect().name)

    detect.clear_cache()
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'https://gitea.example.com/owner/current.git\n'
      end
      return ''
    end

    assert.equals('forgejo', detect.detect().name)
  end)

  it('merges custom Forgejo source hosts with built-ins', function()
    vim.g.forge = {
      sources = {
        forgejo = {
          hosts = { 'git.example.com' },
        },
      },
    }
    vim.fn.executable = function(bin)
      if bin == 'tea' then
        return 1
      end
      return old_executable(bin)
    end
    vim.fn.system = function(cmd)
      if cmd == 'git rev-parse --show-toplevel' then
        return '/repo\n'
      end
      if cmd == 'git remote get-url origin' then
        return 'ssh://git@git.example.com/owner/current.git\n'
      end
      return ''
    end
    vim.system = helpers.system_router({
      default = helpers.command_result('', 1),
    })

    assert.equals('forgejo', detect.detect().name)
  end)
end)
