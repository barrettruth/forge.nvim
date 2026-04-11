vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('command schema', function()
  local cmd = require('forge.cmd')

  it('lists canonical and local command families in order', function()
    assert.same({
      'pr',
      'issue',
      'ci',
      'release',
      'browse',
      'branches',
      'commits',
      'worktrees',
      'review',
      'clear',
    }, cmd.family_names())
  end)

  it('resolves default verbs for implicit family forms', function()
    local pr = cmd.resolve('pr')
    local issue = cmd.resolve('issue')
    local ci = cmd.resolve('ci')
    local browse = cmd.resolve('browse')

    assert.equals('list', pr.name)
    assert.is_true(pr.implicit)
    assert.equals('list', issue.name)
    assert.is_true(issue.implicit)
    assert.equals('list', ci.name)
    assert.is_true(ci.implicit)
    assert.equals('open', browse.name)
    assert.is_true(browse.implicit)
  end)

  it('resolves legacy aliases to canonical verbs', function()
    local diff = cmd.resolve('pr', 'diff')

    assert.equals('review', diff.name)
    assert.equals('diff', diff.alias)
    assert.is_false(diff.implicit)
  end)

  it('parses normalized list and alias forms', function()
    local pr = assert(cmd.parse({ 'pr', '--state=closed' }))
    local review = assert(cmd.parse({ 'pr', 'diff', '42' }))
    local ci = assert(cmd.parse({ 'ci', 'feature' }))

    assert.equals('pr', pr.family)
    assert.equals('list', pr.name)
    assert.same({}, pr.subjects)
    assert.same({ state = 'closed' }, pr.modifiers)

    assert.equals('review', review.name)
    assert.equals('diff', review.alias)
    assert.same({ '42' }, review.subjects)

    assert.equals('list', ci.name)
    assert.same({ 'feature' }, ci.subjects)
  end)

  it('attaches parsed target-bearing modifiers to normalized commands', function()
    local create = assert(cmd.parse({
      'pr',
      'create',
      'base=@main',
      'head=github.com/barrettruth/forge.nvim@topic',
    }))
    local browse = assert(cmd.parse({
      'browse',
      'target=github.com/barrettruth/forge.nvim@main:README.md#L10-L20',
    }))

    assert.equals('main', create.parsed_modifiers.base.rev)
    assert.equals('topic', create.parsed_modifiers.head.rev)
    assert.equals('barrettruth/forge.nvim', create.parsed_modifiers.head.repo.slug)
    assert.equals('README.md', browse.parsed_modifiers.target.path)
    assert.same({ start_line = 10, end_line = 20 }, browse.parsed_modifiers.target.range)
  end)

  it('tracks the intended bang matrix', function()
    assert.is_true(cmd.supports_bang('pr', 'close'))
    assert.is_true(cmd.supports_bang('issue', 'close'))
    assert.is_true(cmd.supports_bang('release', 'delete'))
    assert.is_false(cmd.supports_bang('pr', 'reopen'))
    assert.is_false(cmd.supports_bang('ci', 'watch'))
    assert.is_false(cmd.supports_bang('browse'))
  end)

  it('exposes per-verb modifiers for canonical operations', function()
    assert.same({ 'state', 'repo' }, cmd.modifier_names('pr', 'list'))
    assert.same(
      { 'repo', 'head', 'base', 'draft', 'fill', 'web' },
      cmd.modifier_names('pr', 'create')
    )
    assert.same({ 'repo', 'rev', 'target', 'all' }, cmd.modifier_names('ci', 'list'))
    assert.same({ 'repo', 'method' }, cmd.modifier_names('pr', 'merge'))
  end)

  it('keeps legacy browse modifiers separate from canonical ones', function()
    assert.same({ 'repo', 'rev', 'target' }, cmd.modifier_names('browse'))
    assert.same({ 'root', 'commit' }, cmd.legacy_modifier_names('browse'))
  end)

  it('exposes modifier value metadata where the grammar constrains it', function()
    local pr_list = cmd.resolve('pr', 'list')
    local release_list = cmd.resolve('release', 'list')
    local method = cmd.modifier('method')

    assert.same({ 'open', 'closed', 'all' }, pr_list.modifier_values.state)
    assert.same({ 'all', 'draft', 'prerelease' }, release_list.modifier_values.state)
    assert.same({ 'merge', 'squash', 'rebase' }, method.values)
  end)

  it('rejects unsupported bang before dispatch', function()
    local _, err = cmd.parse({ 'pr', 'review', '42' }, { bang = true })

    assert.equals('E477', err.code)
    assert.equals('E477: No ! allowed', err.message)
  end)

  it('rejects invalid modifiers and duplicate modifiers', function()
    local _, unknown = cmd.parse({ 'pr', 'review', '42', '--wat=1' })
    local _, duplicate = cmd.parse({ 'pr', '--state=open', 'state=closed' })

    assert.equals('unknown modifier: wat', unknown.message)
    assert.equals('duplicate modifier: state', duplicate.message)
  end)

  it('returns nil or empty data for unknown lookups', function()
    assert.is_nil(cmd.family('missing'))
    assert.is_nil(cmd.resolve('pr', 'missing'))
    assert.same({}, cmd.verb_names('missing'))
    assert.same({}, cmd.modifier_names('missing', 'list'))
    assert.is_nil(cmd.modifier('missing'))
  end)
end)
