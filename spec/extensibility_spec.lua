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
  local action_name = 'custom-test-action'
  local captured

  before_each(function()
    captured = nil
  end)

  after_each(function()
    vim.g.forge = nil
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

  it('registers review adapters through the public API', function()
    forge.register_review_adapter('custom-test-review', {
      label = 'custom',
      open = function(ctx)
        captured = ctx
      end,
    })

    assert.is_true(vim.tbl_contains(forge.review_adapter_names(), 'codediff'))
    assert.is_true(vim.tbl_contains(forge.review_adapter_names(), 'diffs'))
    assert.is_true(vim.tbl_contains(forge.review_adapter_names(), 'diffview'))
    assert.is_true(vim.tbl_contains(forge.review_adapter_names(), 'custom-test-review'))
  end)
end)
