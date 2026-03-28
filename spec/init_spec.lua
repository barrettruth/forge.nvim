vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

local forge = require('forge')

describe('config', function()
  after_each(function()
    vim.g.forge = nil
  end)

  it('returns defaults when vim.g.forge is nil', function()
    vim.g.forge = nil
    local cfg = forge.config()
    assert.equals(10000, cfg.ci.lines)
    assert.equals(45, cfg.display.widths.title)
    assert.equals(100, cfg.display.limits.pulls)
    assert.equals('+', cfg.display.icons.open)
    assert.equals('<cr>', cfg.keys.pr.checkout)
  end)

  it('deep-merges partial user config', function()
    vim.g.forge = { ci = { lines = 500 }, display = { icons = { open = '>' } } }
    local cfg = forge.config()
    assert.equals(500, cfg.ci.lines)
    assert.equals('>', cfg.display.icons.open)
    assert.equals('m', cfg.display.icons.merged)
    assert.equals(45, cfg.display.widths.title)
  end)

  it('sets keys to false when user requests it', function()
    vim.g.forge = { keys = false }
    local cfg = forge.config()
    assert.is_false(cfg.keys)
  end)
end)

describe('format_pr', function()
  local fields = {
    number = 'number',
    title = 'title',
    state = 'state',
    author = 'login',
    created_at = 'created_at',
  }

  it('formats open PR with state icon', function()
    local entry =
      { number = 42, title = 'fix bug', state = 'OPEN', login = 'alice', created_at = '' }
    local result = forge.format_pr(entry, fields, true)
    assert.truthy(result:find('+'))
    assert.truthy(result:find('#42'))
    assert.truthy(result:find('fix bug'))
  end)

  it('formats merged PR', function()
    local entry =
      { number = 7, title = 'add feature', state = 'MERGED', login = 'bob', created_at = '' }
    local result = forge.format_pr(entry, fields, true)
    assert.truthy(result:find('m'))
    assert.truthy(result:find('#7'))
  end)

  it('formats closed PR', function()
    local entry = { number = 3, title = 'stale', state = 'CLOSED', login = 'eve', created_at = '' }
    local result = forge.format_pr(entry, fields, true)
    assert.truthy(result:find('x'))
  end)

  it('omits state prefix when show_state is false', function()
    local entry = { number = 1, title = 'no state', state = 'OPEN', login = 'dev', created_at = '' }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result:find('#1'))
    assert.falsy(result:match('^+'))
  end)

  it('truncates long titles', function()
    local long_title = string.rep('a', 100)
    local entry = { number = 9, title = long_title, state = 'OPEN', login = 'x', created_at = '' }
    local result = forge.format_pr(entry, fields, false)
    assert.falsy(result:find(long_title))
  end)

  it('extracts author from table with login field', function()
    local entry =
      { number = 5, title = 't', state = 'OPEN', login = { login = 'nested' }, created_at = '' }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result:find('nested'))
  end)
end)

describe('format_issue', function()
  local fields = {
    number = 'number',
    title = 'title',
    state = 'state',
    author = 'author',
    created_at = 'created_at',
  }

  it('formats open issue', function()
    local entry =
      { number = 10, title = 'bug report', state = 'open', author = 'alice', created_at = '' }
    local result = forge.format_issue(entry, fields, true)
    assert.truthy(result:find('+'))
    assert.truthy(result:find('#10'))
  end)

  it('formats closed issue', function()
    local entry = { number = 11, title = 'done', state = 'closed', author = 'bob', created_at = '' }
    local result = forge.format_issue(entry, fields, true)
    assert.truthy(result:find('x'))
  end)

  it('handles opened state (GitLab)', function()
    local entry =
      { number = 12, title = 'mr issue', state = 'opened', author = 'c', created_at = '' }
    local result = forge.format_issue(entry, fields, true)
    assert.truthy(result:find('+'))
  end)
end)

describe('format_check', function()
  it('maps pass bucket', function()
    local result = forge.format_check({ name = 'lint', bucket = 'pass' })
    assert.truthy(result:find('%*'))
    assert.truthy(result:find('lint'))
  end)

  it('maps fail bucket', function()
    local result = forge.format_check({ name = 'build', bucket = 'fail' })
    assert.truthy(result:find('x'))
  end)

  it('maps pending bucket', function()
    local result = forge.format_check({ name = 'test', bucket = 'pending' })
    assert.truthy(result:find('~'))
  end)

  it('maps skipping bucket', function()
    local result = forge.format_check({ name = 'optional', bucket = 'skipping' })
    assert.truthy(result:find('%-'))
  end)

  it('maps cancel bucket', function()
    local result = forge.format_check({ name = 'cancelled', bucket = 'cancel' })
    assert.truthy(result:find('%-'))
  end)

  it('maps unknown bucket', function()
    local result = forge.format_check({ name = 'mystery', bucket = 'something_else' })
    assert.truthy(result:find('%?'))
  end)

  it('defaults to pending when bucket is nil', function()
    local result = forge.format_check({ name = 'none' })
    assert.truthy(result:find('~'))
  end)
end)

describe('format_run', function()
  it('formats successful run with branch', function()
    local run =
      { name = 'CI', branch = 'main', status = 'success', event = 'push', created_at = '' }
    local result = forge.format_run(run)
    assert.truthy(result:find('%*'))
    assert.truthy(result:find('CI'))
    assert.truthy(result:find('main'))
    assert.truthy(result:find('push'))
  end)

  it('formats failed run without branch', function()
    local run = {
      name = 'Deploy',
      branch = '',
      status = 'failure',
      event = 'workflow_dispatch',
      created_at = '',
    }
    local result = forge.format_run(run)
    assert.truthy(result:find('x'))
    assert.truthy(result:find('manual'))
  end)

  it('maps in_progress status', function()
    local run =
      { name = 'Test', branch = '', status = 'in_progress', event = 'push', created_at = '' }
    local result = forge.format_run(run)
    assert.truthy(result:find('~'))
  end)

  it('maps cancelled status', function()
    local run = { name = 'Old', branch = '', status = 'cancelled', event = 'push', created_at = '' }
    local result = forge.format_run(run)
    assert.truthy(result:find('%-'))
  end)
end)

describe('filter_checks', function()
  local checks = {
    { name = 'a', bucket = 'pass' },
    { name = 'b', bucket = 'fail' },
    { name = 'c', bucket = 'pending' },
    { name = 'd', bucket = 'skipping' },
  }

  it('returns all checks sorted by severity when filter is nil', function()
    local result = forge.filter_checks(vim.deepcopy(checks), nil)
    assert.equals(4, #result)
    assert.equals('b', result[1].name)
    assert.equals('c', result[2].name)
    assert.equals('a', result[3].name)
    assert.equals('d', result[4].name)
  end)

  it('returns all checks when filter is "all"', function()
    local result = forge.filter_checks(vim.deepcopy(checks), 'all')
    assert.equals(4, #result)
  end)

  it('filters to specific bucket', function()
    local result = forge.filter_checks(vim.deepcopy(checks), 'fail')
    assert.equals(1, #result)
    assert.equals('b', result[1].name)
  end)

  it('returns empty when no matches', function()
    local result = forge.filter_checks(vim.deepcopy(checks), 'cancel')
    assert.equals(0, #result)
  end)
end)

describe('relative_time via format_pr', function()
  local fields = { number = 'n', title = 't', state = 's', author = 'a', created_at = 'ts' }

  it('shows minutes for recent timestamps', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 120)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result:match('%d+m'))
  end)

  it('shows hours', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 7200)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result:match('%d+h'))
  end)

  it('shows days', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 172800)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result:match('%d+d'))
  end)

  it('returns empty for nil timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = nil }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result)
  end)

  it('returns empty for empty string timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = '' }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result)
  end)

  it('returns empty for garbage timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = 'not-a-date' }
    local result = forge.format_pr(entry, fields, false)
    assert.truthy(result)
  end)
end)

describe('config validation', function()
  after_each(function()
    vim.g.forge = nil
  end)

  it('rejects non-table sources', function()
    vim.g.forge = { sources = 'bad' }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-table display', function()
    vim.g.forge = { display = 42 }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-number ci.lines', function()
    vim.g.forge = { ci = { lines = 'many' } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-string icon', function()
    vim.g.forge = { display = { icons = { open = 123 } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-number width', function()
    vim.g.forge = { display = { widths = { title = 'wide' } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-number limit', function()
    vim.g.forge = { display = { limits = { pulls = true } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-string key binding', function()
    vim.g.forge = { keys = { pr = { checkout = 42 } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('accepts false for individual key binding', function()
    vim.g.forge = { keys = { pr = { checkout = false } } }
    local cfg = forge.config()
    assert.is_false(cfg.keys.pr.checkout)
  end)

  it('rejects keys as a string', function()
    vim.g.forge = { keys = 'none' }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-table source hosts', function()
    vim.g.forge = { sources = { custom = { hosts = 99 } } }
    assert.has_error(function()
      forge.config()
    end)
  end)
end)
