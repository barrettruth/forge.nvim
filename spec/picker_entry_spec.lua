vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('forge.picker.entry.value', function()
  local picker_entry

  before_each(function()
    package.loaded['forge.picker.entry'] = nil
    picker_entry = require('forge.picker.entry')
  end)

  it('returns a table value for actionable entries', function()
    local value = { num = '1', state = 'OPEN' }

    assert.same(value, picker_entry.value({ value = value }))
  end)

  it('returns nil for placeholder and load-more rows', function()
    assert.is_nil(picker_entry.value({ placeholder = true, value = { state = 'OPEN' } }))
    assert.is_nil(picker_entry.value({ load_more = true, value = { state = 'OPEN' } }))
  end)

  it('returns nil when the entry or value is not a table', function()
    assert.is_nil(picker_entry.value(nil))
    assert.is_nil(picker_entry.value({ value = 'not-a-table' }))
  end)

  it('uses rawget so metatable-backed picker flags do not masquerade as row flags', function()
    local entry = setmetatable({ value = { state = 'OPEN' } }, {
      __index = function(_, key)
        if key == 'placeholder' then
          return true
        end
      end,
    })

    assert.same({ state = 'OPEN' }, picker_entry.value(entry))
  end)
end)
