vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cache_mod = require('forge.cache')

describe('forge.cache', function()
  it('returns nil for missing keys', function()
    local c = cache_mod.new(60)
    assert.is_nil(c.get('missing'))
  end)

  it('returns the stored value while fresh', function()
    local c = cache_mod.new(60)
    c.set('k', 'v')
    assert.equals('v', c.get('k'))
  end)

  it('expires entries after ttl_seconds', function()
    local now = 0
    local c = cache_mod.new(60, function()
      return now
    end)
    c.set('k', 'v')
    now = 30
    assert.equals('v', c.get('k'))
    now = 60
    assert.is_nil(c.get('k'))
  end)

  it('evicts expired entries on read', function()
    local now = 0
    local c = cache_mod.new(5, function()
      return now
    end)
    c.set('k', 'v')
    now = 10
    c.get('k')
    now = 0
    assert.is_nil(c.get('k'))
  end)

  it('treats set as ttl reset', function()
    local now = 0
    local c = cache_mod.new(60, function()
      return now
    end)
    c.set('k', 'v1')
    now = 50
    c.set('k', 'v2')
    now = 70
    assert.equals('v2', c.get('k'))
    now = 120
    assert.is_nil(c.get('k'))
  end)

  it('clear(key) removes only that entry', function()
    local c = cache_mod.new(60)
    c.set('a', 1)
    c.set('b', 2)
    c.clear('a')
    assert.is_nil(c.get('a'))
    assert.equals(2, c.get('b'))
  end)

  it('clear() without key removes all entries', function()
    local c = cache_mod.new(60)
    c.set('a', 1)
    c.set('b', 2)
    c.clear()
    assert.is_nil(c.get('a'))
    assert.is_nil(c.get('b'))
  end)

  it('clear_prefix removes matching keys and preserves others', function()
    local c = cache_mod.new(60)
    c.set('root:pr:open', 1)
    c.set('root:pr:closed', 2)
    c.set('root:issue:open', 3)
    c.clear_prefix('root:pr:')
    assert.is_nil(c.get('root:pr:open'))
    assert.is_nil(c.get('root:pr:closed'))
    assert.equals(3, c.get('root:issue:open'))
  end)

  it('allows false values without treating them as missing', function()
    local c = cache_mod.new(60)
    c.set('k', false)
    assert.equals(false, c.get('k'))
  end)
end)
