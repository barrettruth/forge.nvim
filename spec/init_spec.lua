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

  it('returns defaults when vim.g.forge is nil', function()
    vim.g.forge = nil
    local cfg = forge.config()
    assert.equals(1000, cfg.ci.lines)
    assert.equals('horizontal', cfg.split)
    assert.is_true(cfg.confirm.branch_delete)
    assert.is_true(cfg.confirm.worktree_delete)
    assert.same({}, cfg.targets.aliases)
    assert.equals('current', cfg.targets.ci.repo)
    assert.equals(45, cfg.display.widths.title)
    assert.equals(100, cfg.display.limits.pulls)
    assert.equals(100, cfg.display.limits.commits)
    assert.equals('o', cfg.display.icons.open)
    assert.equals('m', cfg.display.icons.merged)
    assert.equals('c', cfg.display.icons.closed)
    assert.equals('p', cfg.display.icons.pass)
    assert.equals('f', cfg.display.icons.fail)
    assert.equals('~', cfg.display.icons.pending)
    assert.equals('s', cfg.display.icons.skip)
    assert.equals('?', cfg.display.icons.unknown)
    assert.equals('<c-e>', cfg.keys.pr.edit)
    assert.equals('<c-a>', cfg.keys.pr.approve)
    assert.equals('<c-g>', cfg.keys.pr.merge)
    assert.equals('<c-n>', cfg.keys.pr.create)
    assert.equals('<c-s>', cfg.keys.pr.close)
    assert.equals('<c-d>', cfg.keys.pr.draft)
    assert.equals('<c-o>', cfg.keys.back)
    assert.equals('<tab>', cfg.keys.pr.filter)
    assert.equals('<c-e>', cfg.keys.issue.edit)
    assert.equals('<tab>', cfg.keys.issue.filter)
    assert.equals('<c-w>', cfg.keys.ci.watch)
    assert.equals('<tab>', cfg.keys.ci.filter)
    assert.is_nil(cfg.keys.ci.failed)
    assert.is_nil(cfg.keys.ci.passed)
    assert.is_nil(cfg.keys.ci.running)
    assert.is_nil(cfg.keys.ci.all)
    assert.equals('<c-s>', cfg.keys.branch.delete)
    assert.equals('<c-x>', cfg.keys.branch.browse)
    assert.equals('<c-y>', cfg.keys.branch.yank)
    assert.equals('<c-r>', cfg.keys.branch.refresh)
    assert.equals('<c-x>', cfg.keys.commit.browse)
    assert.equals('<c-y>', cfg.keys.commit.yank)
    assert.equals('<c-r>', cfg.keys.commit.refresh)
    assert.equals('<c-a>', cfg.keys.worktree.add)
    assert.equals('<c-s>', cfg.keys.worktree.delete)
    assert.equals('<c-y>', cfg.keys.worktree.yank)
    assert.equals('<c-r>', cfg.keys.worktree.refresh)
    assert.equals('<tab>', cfg.keys.release.filter)
  end)

  it('deep-merges partial user config', function()
    vim.g.forge = {
      ci = { lines = 500 },
      confirm = { branch_delete = false },
      display = { icons = { open = '>' } },
    }
    local cfg = forge.config()
    assert.equals(500, cfg.ci.lines)
    assert.is_false(cfg.confirm.branch_delete)
    assert.is_true(cfg.confirm.worktree_delete)
    assert.equals('>', cfg.display.icons.open)
    assert.equals('m', cfg.display.icons.merged)
    assert.equals(45, cfg.display.widths.title)
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

  it('deep-merges git section key bindings', function()
    vim.g.forge = {
      keys = {
        back = false,
        branch = { browse = '<c-b>' },
        commit = { yank = false },
        worktree = { refresh = '<c-f>' },
      },
    }
    local cfg = forge.config()
    assert.is_false(cfg.keys.back)
    assert.equals('<c-s>', cfg.keys.branch.delete)
    assert.equals('<c-b>', cfg.keys.branch.browse)
    assert.equals('<c-y>', cfg.keys.branch.yank)
    assert.equals('<c-r>', cfg.keys.branch.refresh)
    assert.equals('<c-x>', cfg.keys.commit.browse)
    assert.is_false(cfg.keys.commit.yank)
    assert.equals('<c-r>', cfg.keys.commit.refresh)
    assert.equals('<c-a>', cfg.keys.worktree.add)
    assert.equals('<c-s>', cfg.keys.worktree.delete)
    assert.equals('<c-y>', cfg.keys.worktree.yank)
    assert.equals('<c-f>', cfg.keys.worktree.refresh)
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
  it('maps pass bucket', function()
    local result = flatten(forge.format_check({ name = 'lint', bucket = 'pass' }))
    assert.truthy(result:find('p'))
    assert.truthy(result:find('lint'))
  end)

  it('maps fail bucket', function()
    local result = flatten(forge.format_check({ name = 'build', bucket = 'fail' }))
    assert.truthy(result:find('f'))
  end)

  it('maps pending bucket', function()
    local result = flatten(forge.format_check({ name = 'test', bucket = 'pending' }))
    assert.truthy(result:find('~'))
  end)

  it('maps skipping bucket', function()
    local result = flatten(forge.format_check({ name = 'optional', bucket = 'skipping' }))
    assert.truthy(result:find('s'))
  end)

  it('maps cancel bucket', function()
    local result = flatten(forge.format_check({ name = 'cancelled', bucket = 'cancel' }))
    assert.truthy(result:find('s'))
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
    assert.truthy(result:find('p'))
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
    assert.truthy(result:find('f'))
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
    assert.truthy(result:find('s'))
  end)
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
    vim.g.forge = { keys = { pr = { edit = 42 } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects non-table targets', function()
    vim.g.forge = { targets = 'bad' }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects invalid target alias values', function()
    vim.g.forge = { targets = { aliases = { upstream = false } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('rejects invalid ci repo policy', function()
    vim.g.forge = { targets = { ci = { repo = 'fork' } } }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('accepts target alias and collaboration defaults', function()
    vim.g.forge = {
      targets = {
        default_repo = 'upstream',
        aliases = {
          work = 'github.com/owner/repo',
        },
        ci = {
          repo = 'collaboration',
        },
      },
    }
    local cfg = forge.config()
    assert.equals('upstream', cfg.targets.default_repo)
    assert.equals('github.com/owner/repo', cfg.targets.aliases.work)
    assert.equals('collaboration', cfg.targets.ci.repo)
  end)

  it('accepts false for individual key binding', function()
    vim.g.forge = { keys = { pr = { edit = false } } }
    local cfg = forge.config()
    assert.is_false(cfg.keys.pr.edit)
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
    assert.is_true(cfg.confirm.branch_delete)
    assert.is_true(cfg.confirm.worktree_delete)
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
    assert.is_true(cfg.confirm.branch_delete)
    assert.is_true(cfg.confirm.worktree_delete)
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

  it('rejects invalid delete confirmation config', function()
    vim.g.forge = { confirm = { branch_delete = 'nope' } }
    assert.has_error(function()
      forge.config()
    end)
  end)
end)
