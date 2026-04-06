vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

local forge = require('forge')

local function flatten(segments)
  local parts = {}
  for _, seg in ipairs(segments) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

describe('config', function()
  after_each(function()
    vim.g.forge = nil
  end)

  it('returns defaults when vim.g.forge is nil', function()
    vim.g.forge = nil
    local cfg = forge.config()
    assert.equals(1000, cfg.ci.lines)
    assert.equals('horizontal', cfg.split)
    assert.equals(45, cfg.display.widths.title)
    assert.equals(100, cfg.display.limits.pulls)
    assert.equals('+', cfg.display.icons.open)
    assert.is_nil(cfg.keys.pr.checkout)
    assert.is_nil(cfg.keys.pr.manage)
    assert.is_nil(cfg.keys.pr.edit)
    assert.is_nil(cfg.keys.pr.close)
    assert.equals('<c-w>', cfg.keys.ci.watch)
    assert.equals('<c-o>', cfg.keys.ci.filter)
    assert.is_nil(cfg.keys.ci.failed)
    assert.is_nil(cfg.keys.ci.passed)
    assert.is_nil(cfg.keys.ci.running)
    assert.is_nil(cfg.keys.ci.all)
    assert.equals('<c-x>', cfg.keys.branch.browse)
    assert.equals('<c-y>', cfg.keys.branch.yank)
    assert.equals('<c-r>', cfg.keys.branch.refresh)
    assert.equals('<c-x>', cfg.keys.commit.browse)
    assert.equals('<c-y>', cfg.keys.commit.yank)
    assert.equals('<c-r>', cfg.keys.commit.refresh)
    assert.equals('<c-y>', cfg.keys.worktree.yank)
    assert.equals('<c-r>', cfg.keys.worktree.refresh)
  end)

  it('deep-merges partial user config', function()
    vim.g.forge = { ci = { lines = 500 }, display = { icons = { open = '>' } } }
    local cfg = forge.config()
    assert.equals(500, cfg.ci.lines)
    assert.equals('>', cfg.display.icons.open)
    assert.equals('m', cfg.display.icons.merged)
    assert.equals(45, cfg.display.widths.title)
  end)

  it('deep-merges git section key bindings', function()
    vim.g.forge = {
      keys = {
        branch = { browse = '<c-b>' },
        commit = { yank = false },
        worktree = { refresh = '<c-f>' },
      },
    }
    local cfg = forge.config()
    assert.equals('<c-b>', cfg.keys.branch.browse)
    assert.equals('<c-y>', cfg.keys.branch.yank)
    assert.equals('<c-r>', cfg.keys.branch.refresh)
    assert.equals('<c-x>', cfg.keys.commit.browse)
    assert.is_false(cfg.keys.commit.yank)
    assert.equals('<c-r>', cfg.keys.commit.refresh)
    assert.equals('<c-y>', cfg.keys.worktree.yank)
    assert.equals('<c-f>', cfg.keys.worktree.refresh)
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
    local result = flatten(forge.format_pr(entry, fields, true))
    assert.truthy(result:find('+'))
    assert.truthy(result:find('#42'))
    assert.truthy(result:find('fix bug'))
  end)

  it('formats merged PR', function()
    local entry =
      { number = 7, title = 'add feature', state = 'MERGED', login = 'bob', created_at = '' }
    local result = flatten(forge.format_pr(entry, fields, true))
    assert.truthy(result:find('m'))
    assert.truthy(result:find('#7'))
  end)

  it('formats closed PR', function()
    local entry = { number = 3, title = 'stale', state = 'CLOSED', login = 'eve', created_at = '' }
    local result = flatten(forge.format_pr(entry, fields, true))
    assert.truthy(result:find('x'))
  end)

  it('omits state prefix when show_state is false', function()
    local entry = { number = 1, title = 'no state', state = 'OPEN', login = 'dev', created_at = '' }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result:find('#1'))
    assert.falsy(result:match('^+'))
  end)

  it('truncates long titles', function()
    local long_title = string.rep('a', 100)
    local entry = { number = 9, title = long_title, state = 'OPEN', login = 'x', created_at = '' }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.falsy(result:find(long_title))
  end)

  it('extracts author from table with login field', function()
    local entry =
      { number = 5, title = 't', state = 'OPEN', login = { login = 'nested' }, created_at = '' }
    local result = flatten(forge.format_pr(entry, fields, false))
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
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.truthy(result:find('+'))
    assert.truthy(result:find('#10'))
  end)

  it('formats closed issue', function()
    local entry = { number = 11, title = 'done', state = 'closed', author = 'bob', created_at = '' }
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.truthy(result:find('x'))
  end)

  it('handles opened state (GitLab)', function()
    local entry =
      { number = 12, title = 'mr issue', state = 'opened', author = 'c', created_at = '' }
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.truthy(result:find('+'))
  end)
end)

describe('format_check', function()
  it('maps pass bucket', function()
    local result = flatten(forge.format_check({ name = 'lint', bucket = 'pass' }))
    assert.truthy(result:find('%*'))
    assert.truthy(result:find('lint'))
  end)

  it('maps fail bucket', function()
    local result = flatten(forge.format_check({ name = 'build', bucket = 'fail' }))
    assert.truthy(result:find('x'))
  end)

  it('maps pending bucket', function()
    local result = flatten(forge.format_check({ name = 'test', bucket = 'pending' }))
    assert.truthy(result:find('~'))
  end)

  it('maps skipping bucket', function()
    local result = flatten(forge.format_check({ name = 'optional', bucket = 'skipping' }))
    assert.truthy(result:find('%-'))
  end)

  it('maps cancel bucket', function()
    local result = flatten(forge.format_check({ name = 'cancelled', bucket = 'cancel' }))
    assert.truthy(result:find('%-'))
  end)

  it('maps unknown bucket', function()
    local result = flatten(forge.format_check({ name = 'mystery', bucket = 'something_else' }))
    assert.truthy(result:find('%?'))
  end)

  it('defaults to pending when bucket is nil', function()
    local result = flatten(forge.format_check({ name = 'none' }))
    assert.truthy(result:find('~'))
  end)
end)

describe('format_run', function()
  it('formats successful run with branch', function()
    local run =
      { name = 'CI', branch = 'main', status = 'success', event = 'push', created_at = '' }
    local result = flatten(forge.format_run(run))
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
    local result = flatten(forge.format_run(run))
    assert.truthy(result:find('x'))
    assert.truthy(result:find('manual'))
  end)

  it('maps in_progress status', function()
    local run =
      { name = 'Test', branch = '', status = 'in_progress', event = 'push', created_at = '' }
    local result = flatten(forge.format_run(run))
    assert.truthy(result:find('~'))
  end)

  it('maps cancelled status', function()
    local run = { name = 'Old', branch = '', status = 'cancelled', event = 'push', created_at = '' }
    local result = flatten(forge.format_run(run))
    assert.truthy(result:find('%-'))
  end)
end)

describe('format_release', function()
  local fields = {
    tag = 'tagName',
    title = 'name',
    is_draft = 'isDraft',
    is_prerelease = 'isPrerelease',
    is_latest = 'isLatest',
    published_at = 'publishedAt',
  }

  it('formats a regular release', function()
    local entry = {
      tagName = 'v1.0.0',
      name = 'Initial release',
      isDraft = false,
      isPrerelease = false,
      isLatest = false,
      publishedAt = '',
    }
    local result = flatten(forge.format_release(entry, fields))
    assert.truthy(result:find('v1.0.0'))
    assert.truthy(result:find('Initial release'))
  end)

  it('formats latest release with pass icon', function()
    local entry = {
      tagName = 'v2.0.0',
      name = 'Latest',
      isDraft = false,
      isPrerelease = false,
      isLatest = true,
      publishedAt = '',
    }
    local segs = forge.format_release(entry, fields)
    assert.equals('ForgePass', segs[1][2])
  end)

  it('formats draft release with pending icon', function()
    local entry = {
      tagName = 'v3.0.0-draft',
      name = 'Draft',
      isDraft = true,
      isPrerelease = false,
      isLatest = false,
      publishedAt = '',
    }
    local segs = forge.format_release(entry, fields)
    assert.equals('ForgePending', segs[1][2])
  end)

  it('formats prerelease with skip icon', function()
    local entry = {
      tagName = 'v4.0.0-rc1',
      name = 'Release candidate',
      isDraft = false,
      isPrerelease = true,
      isLatest = false,
      publishedAt = '',
    }
    local segs = forge.format_release(entry, fields)
    assert.equals('ForgeSkip', segs[1][2])
  end)

  it('omits title when same as tag', function()
    local entry = {
      tagName = 'v5.0.0',
      name = 'v5.0.0',
      isDraft = false,
      isPrerelease = false,
      isLatest = false,
      publishedAt = '',
    }
    local result = flatten(forge.format_release(entry, fields))
    local first = result:find('v5.0.0')
    local second = result:find('v5.0.0', first + 1)
    assert.falsy(second)
  end)

  it('handles missing optional fields', function()
    local no_draft_fields = {
      tag = 'tag_name',
      title = 'name',
      published_at = 'released_at',
    }
    local entry = {
      tag_name = 'v1.0',
      name = 'Release',
      released_at = '',
    }
    local result = flatten(forge.format_release(entry, no_draft_fields))
    assert.truthy(result:find('v1.0'))
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

describe('filter_runs', function()
  local runs = {
    { name = 'a', status = 'success' },
    { name = 'b', status = 'failure' },
    { name = 'c', status = 'in_progress' },
    { name = 'd', status = 'cancelled' },
  }

  it('returns all runs sorted by severity when filter is nil', function()
    local result = forge.filter_runs(vim.deepcopy(runs), nil)
    assert.equals(4, #result)
    assert.equals('b', result[1].name)
    assert.equals('c', result[2].name)
    assert.equals('a', result[3].name)
    assert.equals('d', result[4].name)
  end)

  it('filters to failed runs', function()
    local result = forge.filter_runs(vim.deepcopy(runs), 'fail')
    assert.equals(1, #result)
    assert.equals('b', result[1].name)
  end)

  it('filters to running runs', function()
    local result = forge.filter_runs(vim.deepcopy(runs), 'pending')
    assert.equals(1, #result)
    assert.equals('c', result[1].name)
  end)
end)

describe('relative_time via format_pr', function()
  local fields = { number = 'n', title = 't', state = 's', author = 'a', created_at = 'ts' }

  it('shows minutes for recent timestamps', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 120)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result:match('%d+m'))
  end)

  it('shows hours', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 7200)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result:match('%d+h'))
  end)

  it('shows days', function()
    local ts = os.date('%Y-%m-%dT%H:%M:%SZ', os.time() - 172800)
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = ts }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result:match('%d+d'))
  end)

  it('returns empty for nil timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = nil }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result)
  end)

  it('returns empty for empty string timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = '' }
    local result = flatten(forge.format_pr(entry, fields, false))
    assert.truthy(result)
  end)

  it('returns empty for garbage timestamp', function()
    local entry = { n = 1, t = 'x', s = 'open', a = 'u', ts = 'not-a-date' }
    local result = flatten(forge.format_pr(entry, fields, false))
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

  it('rejects invalid split value', function()
    vim.g.forge = { split = 'diagonal' }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('accepts horizontal split', function()
    vim.g.forge = { split = 'horizontal' }
    local cfg = forge.config()
    assert.equals('horizontal', cfg.split)
  end)

  it('accepts vertical split', function()
    vim.g.forge = { split = 'vertical' }
    local cfg = forge.config()
    assert.equals('vertical', cfg.split)
  end)

  it('accepts ci.split override', function()
    vim.g.forge = { split = 'horizontal', ci = { split = 'vertical' } }
    local cfg = forge.config()
    assert.equals('horizontal', cfg.split)
    assert.equals('vertical', cfg.ci.split)
  end)

  it('rejects invalid ci.split', function()
    vim.g.forge = { ci = { split = 'bad' } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('defaults ci.refresh to 5', function()
    vim.g.forge = nil
    local cfg = forge.config()
    assert.equals(5, cfg.ci.refresh)
  end)

  it('accepts ci.refresh = 0 to disable', function()
    vim.g.forge = { ci = { refresh = 0 } }
    local cfg = forge.config()
    assert.equals(0, cfg.ci.refresh)
  end)

  it('rejects non-number ci.refresh', function()
    vim.g.forge = { ci = { refresh = 'fast' } }
    assert.has_error(function()
      forge.config()
    end)
  end)
end)
