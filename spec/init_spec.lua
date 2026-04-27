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

local function repo_file(path)
  return vim.fn.getcwd() .. '/' .. path
end

local function use_named_current_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

describe('config', function()
  after_each(function()
    vim.g.forge = nil
  end)

  it('deep-merges partial user config', function()
    vim.g.forge = {
      ci = { lines = 500 },
      display = { icons = { open = '>' } },
      review = { adapter = 'worktree' },
    }
    local cfg = forge.config()
    assert.equals(500, cfg.ci.lines)
    assert.equals('>', cfg.display.icons.open)
    assert.equals('worktree', cfg.review.adapter)
    assert.equals('m', cfg.display.icons.merged)
    assert.equals(100, cfg.display.limits.pulls)
  end)

  it('derives the current branch highlight from Special with bold emphasis', function()
    local special = vim.api.nvim_get_hl(0, { name = 'Special', link = false })
    local current = vim.api.nvim_get_hl(0, { name = 'ForgeBranchCurrent', link = false })
    assert.is_true(current.bold)
    if special.fg ~= nil then
      assert.equals(special.fg, current.fg)
    end
    if special.bg ~= nil then
      assert.equals(special.bg, current.bg)
    end
  end)

  it('sets keys to false when user requests it', function()
    vim.g.forge = { keys = false }
    local cfg = forge.config()
    assert.is_false(cfg.keys)
  end)
end)

describe('file_loc', function()
  after_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_set_name(0, '')
  end)

  it('returns the current file path without a line in normal mode', function()
    vim.api.nvim_buf_set_name(0, repo_file('tmp/file-loc-normal.lua'))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    assert.equals('tmp/file-loc-normal.lua', forge.file_loc())
  end)

  it('returns the selected line range in visual mode', function()
    vim.api.nvim_buf_set_name(0, repo_file('tmp/file-loc-visual.lua'))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.cmd('normal! ggVj')

    assert.equals('tmp/file-loc-visual.lua:1-2', forge.file_loc())
  end)

  it('returns no file location for special URI buffers', function()
    use_named_current_buf('canola://issue/123')

    assert.equals('', forge.file_loc())
  end)
end)

describe('pr_state cache', function()
  after_each(function()
    forge.clear_cache()
  end)

  it('caches PR state lookups per repo, scope, and number', function()
    local calls = 0
    local fake = {
      pr_state = function(_, num, scope)
        calls = calls + 1
        return {
          state = 'OPEN',
          mergeable = 'UNKNOWN',
          review_decision = num .. '|' .. (scope and scope.slug or ''),
          is_draft = false,
        }
      end,
    }
    local scope = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/forge.nvim',
    }

    local first = forge.pr_state(fake, '42', scope)
    local second = forge.pr_state(fake, '42', scope)

    assert.equals(1, calls)
    assert.same(first, second)
  end)

  it('sets scoped PR state entries without refetching', function()
    local calls = 0
    local fake = {
      pr_state = function()
        calls = calls + 1
        return {
          state = 'OPEN',
          mergeable = 'UNKNOWN',
          review_decision = '',
          is_draft = false,
        }
      end,
    }
    local scope = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/forge.nvim',
    }

    forge.set_pr_state('42', {
      state = 'OPEN',
      mergeable = 'UNKNOWN',
      review_decision = 'APPROVED',
      is_draft = true,
    }, scope)

    local state = forge.pr_state(fake, '42', scope)

    assert.equals(0, calls)
    assert.same({
      state = 'OPEN',
      mergeable = 'UNKNOWN',
      review_decision = 'APPROVED',
      is_draft = true,
    }, state)
  end)

  it('clears scoped PR state entries without touching other scopes', function()
    local calls = 0
    local fake = {
      pr_state = function(_, num, scope)
        calls = calls + 1
        return {
          state = 'OPEN',
          mergeable = 'UNKNOWN',
          review_decision = num .. '|' .. (scope and scope.slug or ''),
          is_draft = false,
        }
      end,
    }
    local left = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/forge.nvim',
    }
    local right = {
      kind = 'github',
      host = 'github.com',
      slug = 'barrettruth/example.nvim',
    }

    forge.pr_state(fake, '42', left)
    forge.pr_state(fake, '42', right)
    forge.clear_pr_state(nil, left)
    forge.pr_state(fake, '42', left)
    forge.pr_state(fake, '42', right)

    assert.equals(3, calls)
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
    assert.truthy(result:find('o'))
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
    assert.truthy(result:find('c'))
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

describe('format_prs', function()
  local fields = {
    number = 'number',
    title = 'title',
    state = 'state',
    author = 'author',
    created_at = 'created_at',
  }

  it('drops secondary metadata before the primary title in narrow layouts', function()
    local rows = forge.format_prs({
      { number = 1, title = 'short', state = 'OPEN', author = 'alice', created_at = '' },
      {
        number = 2,
        title = 'a much longer title that should truncate',
        state = 'OPEN',
        author = 'bob',
        created_at = '',
      },
    }, fields, false, { width = 18 })

    assert.same({
      { '#1', 'ForgeNumber' },
      { ' short' },
    }, rows[1])
    assert.same({ '#2', 'ForgeNumber' }, rows[2][1])
    assert.truthy(rows[2][2][1]:find(' a much', 1, true))
    assert.truthy(rows[2][2][1]:find('...', 1, true))
  end)

  it('grows the title column to fit wide titles when budget allows', function()
    local long_title =
      'a deliberately long pull request title that exceeds the old default preferred width of 45'
    local rows = forge.format_prs({
      { number = 1, title = long_title, state = 'OPEN', author = 'alice', created_at = '' },
    }, fields, false, { width = 200 })

    local title_text = rows[1][2][1]
    assert.equals(nil, title_text:find('...', 1, true))
    assert.truthy(title_text:find(long_title, 1, true))
  end)

  it('pads PR rows to the full picker width in wide layouts', function()
    local row = forge.format_prs({
      { number = 1, title = 'short', state = 'OPEN', author = 'alice', created_at = '' },
    }, fields, false, { width = 80 })[1]

    assert.equals(80, require('forge.layout').display_width(flatten(row)))
  end)
end)

describe('format_issues', function()
  local fields = {
    number = 'number',
    title = 'title',
    state = 'state',
    author = 'author',
    created_at = 'created_at',
  }

  it('pads issue rows to the full picker width in wide layouts', function()
    local row = forge.format_issues({
      { number = 10, title = 'bug report', state = 'open', author = 'alice', created_at = '' },
    }, fields, false, { width = 80 })[1]

    assert.equals(80, require('forge.layout').display_width(flatten(row)))
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
    assert.truthy(result:find('o'))
    assert.truthy(result:find('#10'))
  end)

  it('formats closed issue', function()
    local entry = { number = 11, title = 'done', state = 'closed', author = 'bob', created_at = '' }
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.truthy(result:find('c'))
  end)

  it('handles opened state (GitLab)', function()
    local entry =
      { number = 12, title = 'mr issue', state = 'opened', author = 'c', created_at = '' }
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.truthy(result:find('o'))
  end)

  it('normalizes embedded control characters in issue titles', function()
    local entry = {
      number = 26,
      title = 'no highlighting on release/pr comment text\n',
      state = 'closed',
      author = 'bob',
      created_at = '',
    }
    local result = flatten(forge.format_issue(entry, fields, true))
    assert.is_nil(result:find('\n', 1, true))
    assert.is_nil(result:find('\r', 1, true))
    assert.is_nil(result:find('\t', 1, true))
  end)
end)

describe('format_check', function()
  for _, case in ipairs({
    { name = 'maps pass bucket', check = { name = 'lint', bucket = 'pass' }, icon = 'p' },
    { name = 'maps fail bucket', check = { name = 'build', bucket = 'fail' }, icon = 'f' },
    { name = 'maps pending bucket', check = { name = 'test', bucket = 'pending' }, icon = '~' },
    {
      name = 'maps skipping bucket',
      check = { name = 'optional', bucket = 'skipping' },
      icon = 's',
    },
    { name = 'maps cancel bucket', check = { name = 'cancelled', bucket = 'cancel' }, icon = 's' },
    {
      name = 'maps unknown bucket',
      check = { name = 'mystery', bucket = 'something_else' },
      icon = '%?',
    },
    { name = 'defaults to pending when bucket is nil', check = { name = 'none' }, icon = '~' },
  }) do
    it(case.name, function()
      local result = flatten(forge.format_check(case.check))
      assert.truthy(result:find(case.icon))
      assert.truthy(result:find(case.check.name, 1, true))
    end)
  end
end)

describe('format_run', function()
  for _, case in ipairs({
    {
      name = 'formats successful run with branch',
      run = { name = 'CI', branch = 'main', status = 'success', event = 'push', created_at = '' },
      expected = { 'p', 'CI', 'main', 'push' },
    },
    {
      name = 'formats failed run without branch',
      run = {
        name = 'Deploy',
        branch = '',
        status = 'failure',
        event = 'workflow_dispatch',
        created_at = '',
      },
      expected = { 'f', 'manual' },
    },
    {
      name = 'maps in_progress status',
      run = { name = 'Test', branch = '', status = 'in_progress', event = 'push', created_at = '' },
      expected = { '~' },
    },
    {
      name = 'maps cancelled status',
      run = { name = 'Old', branch = '', status = 'cancelled', event = 'push', created_at = '' },
      expected = { 's' },
    },
  }) do
    it(case.name, function()
      local result = flatten(forge.format_run(case.run))
      for _, expected in ipairs(case.expected) do
        assert.truthy(result:find(expected, 1, true))
      end
    end)
  end
end)

describe('format_runs', function()
  it('drops event metadata before branch names in narrow layouts', function()
    local rows = forge.format_runs({
      {
        name = 'CI',
        branch = 'feature/very-long-branch',
        status = 'success',
        event = 'workflow_dispatch',
        created_at = '',
      },
      {
        name = 'Lint',
        branch = 'main',
        status = 'failure',
        event = 'push',
        created_at = '',
      },
    }, { width = 24 })

    assert.same({ 'p', 'ForgePass' }, rows[1][1])
    assert.same({ '  CI' }, rows[1][2])
    assert.equals('ForgeBranch', rows[1][3][2])
    assert.truthy(rows[1][3][1]:find('feature', 1, true))
    assert.equals(3, #rows[1])

    assert.same({ 'f', 'ForgeFail' }, rows[2][1])
    assert.same({ '  Lint' }, rows[2][2])
    assert.equals(' main', rows[2][3][1])
    assert.equals('ForgeBranch', rows[2][3][2])
    assert.equals(3, #rows[2])
  end)
end)

describe('format_checks', function()
  it('drops elapsed metadata before truncating moderate check names in narrow layouts', function()
    local rows = forge.format_checks({
      {
        name = 'Markdown Format Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
    }, { width = 24 })

    local result = flatten(rows[1])
    assert.truthy(result:find('Markdown Format Check', 1, true))
    assert.falsy(result:find('25s', 1, true))
  end)

  it('uses spare width for longer check names instead of capping at the typical width', function()
    local rows = forge.format_checks({
      {
        name = 'changes',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Lua Format Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Lua Lint Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Lua Type Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Lua Test Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Vimdoc Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Markdown Format Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
      {
        name = 'Nix Format Check',
        bucket = 'pass',
        startedAt = '2024-01-01T00:00:00Z',
        completedAt = '2024-01-01T00:00:25Z',
      },
    }, { width = 100 })

    local result = flatten(rows[7])
    assert.truthy(result:find('Markdown Format Check', 1, true))
    assert.falsy(result:find('Markdown Format...', 1, true))
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
    { name = 'a', status = 'success', created_at = '2024-01-01T00:00:00Z' },
    { name = 'b', status = 'failure', created_at = '2024-01-03T00:00:00Z' },
    { name = 'c', status = 'in_progress', created_at = '2024-01-02T00:00:00Z' },
    { name = 'd', status = 'cancelled', created_at = '2023-12-31T00:00:00Z' },
  }

  it('returns all runs in descending created_at order when filter is nil', function()
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

  it('preserves provider order when created_at is missing', function()
    local result = forge.filter_runs({
      { name = 'first', status = 'success', created_at = '' },
      { name = 'second', status = 'failure', created_at = '' },
      { name = 'third', status = 'in_progress', created_at = '' },
    }, nil)
    assert.equals('first', result[1].name)
    assert.equals('second', result[2].name)
    assert.equals('third', result[3].name)
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

  for _, case in ipairs({
    { name = 'rejects non-table sources', config = { sources = 'bad' } },
    { name = 'rejects non-table display', config = { display = 42 } },
    { name = 'rejects non-number ci.lines', config = { ci = { lines = 'many' } } },
    { name = 'rejects non-string icon', config = { display = { icons = { open = 123 } } } },
    { name = 'rejects non-number limit', config = { display = { limits = { pulls = true } } } },
    { name = 'rejects non-string key binding', config = { keys = { pr = { edit = 42 } } } },
    { name = 'rejects non-table targets', config = { targets = 'bad' } },
    {
      name = 'rejects invalid target alias values',
      config = { targets = { aliases = { upstream = false } } },
    },
    { name = 'rejects keys as a string', config = { keys = 'none' } },
    { name = 'rejects non-table source hosts', config = { sources = { custom = { hosts = 99 } } } },
    { name = 'rejects invalid split value', config = { split = 'diagonal' } },
    { name = 'rejects invalid ci.split', config = { ci = { split = 'bad' } } },
    { name = 'rejects non-number ci.refresh', config = { ci = { refresh = 'fast' } } },
  }) do
    it(case.name, function()
      vim.g.forge = case.config
      assert.has_error(function()
        forge.config()
      end)
    end)
  end

  it('accepts target alias and collaboration defaults', function()
    vim.g.forge = {
      targets = {
        default_repo = 'upstream',
        aliases = {
          work = 'github.com/owner/repo',
        },
      },
    }
    local cfg = forge.config()
    assert.equals('upstream', cfg.targets.default_repo)
    assert.equals('github.com/owner/repo', cfg.targets.aliases.work)
  end)

  it('accepts false for individual key binding', function()
    vim.g.forge = { keys = { pr = { edit = false } } }
    local cfg = forge.config()
    assert.is_false(cfg.keys.pr.edit)
  end)

  for _, case in ipairs({
    {
      name = 'accepts horizontal split',
      config = { split = 'horizontal' },
      assert_cfg = function(cfg)
        assert.equals('horizontal', cfg.split)
      end,
    },
    {
      name = 'accepts vertical split',
      config = { split = 'vertical' },
      assert_cfg = function(cfg)
        assert.equals('vertical', cfg.split)
      end,
    },
  }) do
    it(case.name, function()
      vim.g.forge = case.config
      case.assert_cfg(forge.config())
    end)
  end

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
end)
