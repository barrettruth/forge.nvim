vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('surface', function()
  before_each(function()
    package.loaded['forge.surface'] = nil
    package.loaded['forge.cmd'] = nil
    package.loaded['forge.picker'] = nil
  end)

  it('exposes gitlab command aliases separately from canonical families', function()
    local surface = require('forge.surface')

    assert.same({ 'mr' }, surface.family_aliases('pr', 'gitlab'))
    assert.same({ 'pipeline' }, surface.family_aliases('ci', 'gitlab'))
    assert.same(
      { canonical = 'pr', invoked = 'mr', alias = 'mr' },
      surface.resolve_family('mr', 'gitlab')
    )
    assert.same(
      { canonical = 'ci', invoked = 'pipeline', alias = 'pipeline' },
      surface.resolve_family('pipeline', 'gitlab')
    )
    assert.is_nil(surface.resolve_family('mr'))
    assert.is_nil(surface.resolve_family('pipeline'))
  end)

  it('exposes gitlab section and route aliases separately from canonical values', function()
    local surface = require('forge.surface')

    assert.same(
      { 'prs', 'mrs', 'issues', 'ci', 'pipelines', 'browse', 'releases' },
      surface.section_names({
        include_aliases = true,
        forge_name = 'gitlab',
      })
    )
    assert.same(
      { 'prs', 'mrs', 'issues', 'ci', 'pipelines', 'browse', 'releases' },
      surface.section_names({
        include_aliases = true,
        include_all_aliases = true,
      })
    )
    assert.same({ 'mrs.open' }, surface.route_aliases('prs.open', 'gitlab'))
    assert.is_true(vim.tbl_contains(
      surface.route_names({
        include_aliases = true,
        include_all_aliases = true,
      }),
      'mrs.open'
    ))
    assert.is_true(vim.tbl_contains(
      surface.route_names({
        include_aliases = true,
        include_all_aliases = true,
      }),
      'pipelines.current_branch'
    ))
    assert.same(
      { canonical = 'prs', invoked = 'mrs', alias = 'mrs' },
      surface.resolve_section('mrs', 'gitlab')
    )
    assert.same({
      canonical = 'ci.current_branch',
      invoked = 'pipelines.current_branch',
      alias = 'pipelines.current_branch',
    }, surface.resolve_route('pipelines.current_branch', 'gitlab'))
    assert.is_nil(surface.resolve_section('mrs'))
    assert.is_nil(surface.resolve_route('pipelines.current_branch'))
  end)

  it('lets cmd parse preserve invoked family aliases when the forge is known', function()
    local cmd = require('forge.cmd')
    local command, err = cmd.parse({ 'mr', 'edit', '42' }, { forge_name = 'gitlab' })

    assert.is_nil(err)
    assert.equals('pr', command.family)
    assert.equals('mr', command.invoked_family)
    assert.equals('mr', command.family_alias)
    assert.equals('edit', command.name)
    assert.same({ '42' }, command.subjects)
  end)

  it('keeps provider aliases unavailable without an explicit forge surface', function()
    local cmd = require('forge.cmd')
    local command, err = cmd.parse({ 'mr', 'edit', '42' })

    assert.is_nil(command)
    assert.same({ message = 'unknown command: mr' }, {
      message = err.message,
    })
  end)
end)
