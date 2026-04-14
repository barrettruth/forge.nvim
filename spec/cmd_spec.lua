vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('command schema', function()
  local cmd = require('forge.cmd')
  local old_system
  local old_preload

  before_each(function()
    old_system = vim.system
    old_preload = package.preload['forge']

    vim.system = function(cmdline)
      local key = table.concat(cmdline, ' ')
      local result = {
        code = 1,
        stdout = '',
      }
      if key == 'git remote get-url origin' then
        result = { code = 0, stdout = 'git@github.com:owner/current.git\n' }
      elseif key == 'git remote get-url upstream' then
        result = { code = 0, stdout = 'git@github.com:owner/upstream.git\n' }
      elseif key == 'git remote' then
        result = { code = 0, stdout = 'origin\nupstream\n' }
      elseif key == 'git branch --show-current' then
        result = { code = 0, stdout = 'feature\n' }
      elseif key == 'git config branch.feature.pushRemote' then
        result = { code = 0, stdout = 'origin\n' }
      elseif key == 'git config remote.pushDefault' then
        result = { code = 1, stdout = '' }
      elseif key == 'git rev-parse --abbrev-ref feature@{upstream}' then
        result = { code = 0, stdout = 'origin/feature\n' }
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return {
            targets = {
              default_repo = 'collab',
              aliases = {
                collab = 'remote:upstream',
              },
              ci = {
                repo = 'collaboration',
              },
            },
          }
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.target'] = nil
  end)

  after_each(function()
    vim.system = old_system
    package.preload['forge'] = old_preload
    package.loaded['forge'] = nil
    package.loaded['forge.target'] = nil
  end)

  it('lists canonical and local command families in order', function()
    assert.same({
      'pr',
      'issue',
      'ci',
      'release',
      'browse',
      'clear',
    }, cmd.family_names())
  end)

  it('only resolves implicit verbs for direct command families', function()
    local pr = cmd.resolve('pr')
    local issue = cmd.resolve('issue')
    local ci = cmd.resolve('ci')
    local release = cmd.resolve('release')
    local browse = cmd.resolve('browse')
    local clear = cmd.resolve('clear')

    assert.is_nil(pr)
    assert.is_nil(issue)
    assert.is_nil(ci)
    assert.is_nil(release)
    assert.equals('open', browse.name)
    assert.is_true(browse.implicit)
    assert.equals('run', clear.name)
    assert.is_true(clear.implicit)
  end)

  it('rejects implicit picker forms and parses explicit direct actions', function()
    local create = assert(cmd.parse({ 'pr', 'create', 'draft' }))
    local ci = assert(cmd.parse({ 'ci', 'log', '123' }))
    local _, pr_missing = cmd.parse({ 'pr' })
    local _, ci_missing = cmd.parse({ 'ci' })
    local _, pr_list = cmd.parse({ 'pr', 'list' })
    local _, pr_ci = cmd.parse({ 'pr', 'ci', '42' })

    assert.equals('pr', create.family)
    assert.equals('create', create.name)
    assert.same({ draft = true }, create.modifiers)

    assert.equals('ci', ci.family)
    assert.equals('log', ci.name)
    assert.same({ '123' }, ci.subjects)

    assert.equals('missing action', pr_missing.message)
    assert.equals('missing action', ci_missing.message)
    assert.equals('unknown pr action: list', pr_list.message)
    assert.equals('unknown pr action: ci', pr_ci.message)
  end)

  it('attaches parsed target-bearing modifiers to normalized commands', function()
    local create = assert(cmd.parse({
      'pr',
      'create',
      'base=@main',
      'head=github.com/barrettruth/forge.nvim@topic',
    }))
    local browse = assert(cmd.parse({ 'browse', 'rev=main' }))

    assert.equals('main', create.parsed_modifiers.base.rev)
    assert.equals('topic', create.parsed_modifiers.head.rev)
    assert.equals('barrettruth/forge.nvim', create.parsed_modifiers.head.repo.slug)
    assert.equals('main', browse.parsed_modifiers.rev.rev)
  end)

  it('attaches default target policy for omitted direct-action addresses', function()
    local create = assert(cmd.parse({ 'pr', 'create' }))

    assert.same({
      repo = 'collaboration',
      head = 'current_push_context',
      base = 'collaboration_default_branch',
    }, create.default_policy)
    assert.equals('feature', create.default_targets.head.rev)
    assert.equals('owner/current', create.default_targets.head.repo.slug)
    assert.is_true(create.default_targets.base.default_branch)
    assert.equals('owner/upstream', create.default_targets.base.repo.slug)
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
    assert.same(
      { 'repo', 'head', 'base', 'draft', 'fill', 'web' },
      cmd.modifier_names('pr', 'create')
    )
    assert.same({ 'repo' }, cmd.modifier_names('ci', 'log'))
    assert.same({ 'repo', 'web', 'blank', 'template' }, cmd.modifier_names('issue', 'create'))
    assert.same({ 'repo', 'method' }, cmd.modifier_names('pr', 'merge'))
  end)

  it('keeps direct forge verbs aligned with non-list picker actions', function()
    assert.same({
      'checkout',
      'worktree',
      'browse',
      'close',
      'reopen',
      'create',
      'edit',
      'approve',
      'merge',
      'draft',
      'ready',
    }, cmd.verb_names('pr'))

    assert.same({ 'browse', 'close', 'reopen', 'create', 'edit' }, cmd.verb_names('issue'))
    assert.same({ 'log', 'watch' }, cmd.verb_names('ci'))
    assert.same({ 'browse', 'delete' }, cmd.verb_names('release'))
  end)

  it('keeps legacy browse modifiers separate from canonical ones', function()
    assert.same({ 'rev' }, cmd.modifier_names('browse'))
    assert.same({}, cmd.legacy_modifier_names('browse'))
  end)

  it('exposes modifier value metadata where the grammar constrains it', function()
    local method = cmd.modifier('method')

    assert.same({ 'merge', 'squash', 'rebase' }, method.values)
  end)

  it('rejects unsupported bang before dispatch', function()
    local _, err = cmd.parse({ 'pr', 'checkout', '42' }, { bang = true })

    assert.equals('E477', err.code)
    assert.equals('E477: No ! allowed', err.message)
  end)

  it('rejects invalid modifiers and duplicate modifiers', function()
    local _, unknown = cmd.parse({ 'pr', 'checkout', '42', '--wat=1' })
    local _, duplicate = cmd.parse({ 'pr', 'create', 'repo=origin', 'repo=upstream' })

    assert.equals('unknown modifier: wat', unknown.message)
    assert.equals('duplicate modifier: repo', duplicate.message)
  end)

  it('rejects removed browse modifiers and old revision syntax', function()
    local _, target_err = cmd.parse({ 'browse', 'target=README.md#L10' })
    local _, repo_err = cmd.parse({ 'browse', 'repo=upstream' })
    local _, rev_err = cmd.parse({ 'browse', 'rev=@main' })

    assert.equals('unknown modifier: target', target_err.message)
    assert.equals('unknown modifier: repo', repo_err.message)
    assert.equals('invalid revision: @main', rev_err.message)
  end)

  it('returns nil or empty data for unknown lookups', function()
    assert.is_nil(cmd.family('missing'))
    assert.is_nil(cmd.resolve('pr', 'missing'))
    assert.same({}, cmd.verb_names('missing'))
    assert.same({}, cmd.modifier_names('missing', 'list'))
    assert.is_nil(cmd.modifier('missing'))
  end)
end)
