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
      'review',
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
    local review = cmd.resolve('review')
    local browse = cmd.resolve('browse')
    local clear = cmd.resolve('clear')

    assert.is_nil(pr)
    assert.is_nil(issue)
    assert.is_nil(ci)
    assert.is_nil(release)
    assert.equals('open', review.name)
    assert.is_true(review.implicit)
    assert.equals('open', browse.name)
    assert.is_true(browse.implicit)
    assert.equals('run', clear.name)
    assert.is_true(clear.implicit)
  end)

  it('rejects implicit picker forms and parses explicit direct actions', function()
    local create = assert(cmd.parse({ 'pr', 'create', 'draft' }))
    local open = assert(cmd.parse({ 'ci', 'open', '123' }))
    local review = assert(cmd.parse({ 'review', '42' }))
    local _, pr_missing = cmd.parse({ 'pr' })
    local _, ci_missing = cmd.parse({ 'ci' })
    local _, review_missing = cmd.parse({ 'review' })
    local _, pr_checkout = cmd.parse({ 'pr', 'checkout', '42' })
    local _, pr_worktree = cmd.parse({ 'pr', 'worktree', '42' })
    local _, pr_browse = cmd.parse({ 'pr', 'browse' })
    local _, pr_list = cmd.parse({ 'pr', 'list' })
    local _, pr_ci = cmd.parse({ 'pr', 'ci', '42' })
    local _, ci_log = cmd.parse({ 'ci', 'log', '123' })
    local _, ci_watch = cmd.parse({ 'ci', 'watch', '123' })

    assert.equals('pr', create.family)
    assert.equals('create', create.name)
    assert.same({ draft = true }, create.modifiers)

    assert.equals('ci', open.family)
    assert.equals('open', open.name)
    assert.same({ '123' }, open.subjects)

    assert.equals('review', review.family)
    assert.equals('open', review.name)
    assert.same({ '42' }, review.subjects)

    assert.equals('missing action', pr_missing.message)
    assert.equals('missing action', ci_missing.message)
    assert.equals('missing PR number', review_missing.message)
    assert.equals('unknown pr action: checkout', pr_checkout.message)
    assert.equals('unknown pr action: worktree', pr_worktree.message)
    assert.equals('unknown pr action: browse', pr_browse.message)
    assert.equals('unknown pr action: list', pr_list.message)
    assert.equals('unknown pr action: ci', pr_ci.message)
    assert.equals('unknown action: log', ci_log.message)
    assert.equals('unknown action: watch', ci_watch.message)
  end)

  it('accepts argless browse for kind families that have a list landing page', function()
    local issue = assert(cmd.parse({ 'issue', 'browse' }))
    local ci = assert(cmd.parse({ 'ci', 'browse' }))
    local release = assert(cmd.parse({ 'release', 'browse' }))

    assert.equals('browse', issue.name)
    assert.same({}, issue.subjects)
    assert.equals('browse', ci.name)
    assert.same({}, ci.subjects)
    assert.equals('browse', release.name)
    assert.same({}, release.subjects)

    local ci_with = assert(cmd.parse({ 'ci', 'browse', '123' }))
    local release_with = assert(cmd.parse({ 'release', 'browse', 'v1.2.3' }))
    assert.same({ '123' }, ci_with.subjects)
    assert.same({ 'v1.2.3' }, release_with.subjects)
  end)

  it('attaches parsed target-bearing modifiers to normalized commands', function()
    local create = assert(cmd.parse({
      'pr',
      'create',
      'base=@main',
      'head=github.com/barrettruth/forge.nvim@topic',
    }))
    local browse_branch = assert(cmd.parse({ 'browse', 'branch=main' }))
    local browse_commit = assert(cmd.parse({ 'browse', 'commit=abc1234' }))
    local browse_target = assert(cmd.parse({
      'browse',
      'target=upstream@main:lua/forge/init.lua#L10-L20',
    }))

    assert.equals('main', create.parsed_modifiers.base.rev)
    assert.equals('topic', create.parsed_modifiers.head.rev)
    assert.equals('barrettruth/forge.nvim', create.parsed_modifiers.head.repo.slug)
    assert.equals('main', browse_branch.parsed_modifiers.branch.branch)
    assert.equals('abc1234', browse_commit.parsed_modifiers.commit.commit)
    assert.equals('main', browse_target.parsed_modifiers.target.rev.rev)
    assert.equals('owner/upstream', browse_target.parsed_modifiers.target.rev.repo.slug)
    assert.equals('lua/forge/init.lua', browse_target.parsed_modifiers.target.path)
    assert.same({ start_line = 10, end_line = 20 }, browse_target.parsed_modifiers.target.range)
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

  it('exposes per-verb modifiers for canonical operations', function()
    assert.same(
      { 'repo', 'head', 'base', 'draft', 'fill', 'web' },
      cmd.modifier_names('pr', 'create')
    )
    assert.same({ 'repo' }, cmd.modifier_names('ci', 'open'))
    assert.same({ 'repo' }, cmd.modifier_names('ci', 'browse'))
    assert.same({ 'repo', 'web', 'blank', 'template' }, cmd.modifier_names('issue', 'create'))
    assert.same({ 'repo', 'method' }, cmd.modifier_names('pr', 'merge'))
    assert.same({ 'repo', 'adapter' }, cmd.modifier_names('review'))
  end)

  it('keeps direct forge verbs aligned with canonical non-list operations', function()
    assert.same({
      'close',
      'reopen',
      'create',
      'edit',
      'approve',
      'merge',
      'draft',
      'ready',
      'refresh',
    }, cmd.verb_names('pr'))

    assert.same({ 'open' }, cmd.verb_names('review'))
    assert.same(
      { 'browse', 'close', 'reopen', 'create', 'edit', 'refresh' },
      cmd.verb_names('issue')
    )
    assert.same({ 'open', 'browse', 'refresh' }, cmd.verb_names('ci'))
    assert.same({ 'browse', 'delete', 'refresh' }, cmd.verb_names('release'))
  end)

  it('parses argless refresh verbs for all list families', function()
    local pr = assert(cmd.parse({ 'pr', 'refresh' }))
    local issue = assert(cmd.parse({ 'issue', 'refresh' }))
    local ci = assert(cmd.parse({ 'ci', 'refresh' }))
    local release = assert(cmd.parse({ 'release', 'refresh' }))

    assert.equals('pr', pr.family)
    assert.equals('refresh', pr.name)
    assert.same({}, pr.subjects)

    assert.equals('issue', issue.family)
    assert.equals('refresh', issue.name)
    assert.same({}, issue.subjects)

    assert.equals('ci', ci.family)
    assert.equals('refresh', ci.name)
    assert.same({}, ci.subjects)

    assert.equals('release', release.family)
    assert.equals('refresh', release.name)
    assert.same({}, release.subjects)
  end)

  it('rejects subjects on refresh verbs', function()
    local _, pr = cmd.parse({ 'pr', 'refresh', '42' })
    assert.is_not_nil(pr)
  end)

  it('keeps legacy browse modifiers separate from canonical ones', function()
    assert.same({ 'branch', 'commit', 'target' }, cmd.modifier_names('browse'))
    assert.same({}, cmd.legacy_modifier_names('browse'))
  end)

  it('exposes modifier value metadata where the grammar constrains it', function()
    local method = cmd.modifier('method')

    assert.same({ 'merge', 'squash', 'rebase' }, method.values)
  end)

  it('rejects invalid modifiers and duplicate modifiers', function()
    local _, unknown = cmd.parse({ 'review', '42', '--wat=1' })
    local _, duplicate = cmd.parse({ 'pr', 'create', 'repo=origin', 'repo=upstream' })

    assert.equals('unknown modifier: wat', unknown.message)
    assert.equals('duplicate modifier: repo', duplicate.message)
  end)

  it('rejects obsolete browse modifiers and malformed browse target syntax', function()
    local _, target_err = cmd.parse({ 'browse', 'target=README.md#L10' })
    local _, repo_err = cmd.parse({ 'browse', 'repo=upstream' })
    local _, rev_err = cmd.parse({ 'browse', 'rev=main' })
    local _, branch_err = cmd.parse({ 'browse', 'branch=@main' })
    local _, commit_err = cmd.parse({ 'browse', 'commit=abc:def' })

    assert.equals('invalid location address: README.md#L10', target_err.message)
    assert.equals('unknown modifier: repo', repo_err.message)
    assert.equals('unknown modifier: rev', rev_err.message)
    assert.equals('invalid branch: @main', branch_err.message)
    assert.equals('invalid commit: abc:def', commit_err.message)
  end)

  it('returns nil or empty data for unknown lookups', function()
    assert.is_nil(cmd.family('missing'))
    assert.is_nil(cmd.resolve('pr', 'missing'))
    assert.same({}, cmd.verb_names('missing'))
    assert.same({}, cmd.modifier_names('missing', 'list'))
    assert.is_nil(cmd.modifier('missing'))
  end)
end)
