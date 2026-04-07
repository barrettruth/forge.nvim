vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

local forge = require('forge')

describe('extensibility', function()
  local client_name = 'custom-test-client'
  local context_name = 'workspace-test-context'
  local action_name = 'custom-test-action'
  local captured

  before_each(function()
    captured = nil
  end)

  after_each(function()
    vim.g.forge = nil
  end)

  it('exposes the public extensibility helpers', function()
    assert.is_function(forge.register_client)
    assert.is_function(forge.register_context_provider)
    assert.is_function(forge.register_action)
    assert.is_function(forge.run_action)
  end)

  it('uses a registered custom client for the root picker', function()
    forge.register_context_provider(context_name, function()
      return {
        id = context_name,
        branch = 'main',
        head = 'abc123',
        forge = {
          name = 'github',
          labels = {
            pr_full = 'PRs',
            issue = 'Issues',
            ci = 'CI',
          },
        },
      }
    end)

    forge.register_client(client_name, function(opts)
      captured = opts
    end)

    vim.g.forge = {
      client = client_name,
      context = context_name,
      contexts = {
        current = true,
        [context_name] = true,
      },
    }

    forge.open()

    assert.is_not_nil(captured)
    assert.equals('Github workflow (main)> ', captured.prompt)
    assert.equals('default', captured.actions[1].name)
    assert.is_true(#captured.entries > 0)
  end)

  it('runs registered custom actions through the public API', function()
    forge.register_action(action_name, function(entry, opts)
      captured = {
        entry = entry,
        opts = opts,
      }
    end)

    local ok = forge.run_action(action_name, { value = 'route' }, { context = 'current' })

    assert.is_true(ok)
    assert.equals('route', captured.entry.value)
    assert.equals('current', captured.opts.context)
  end)
end)
