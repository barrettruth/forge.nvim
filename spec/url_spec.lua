vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('url helpers', function()
  it('normalizes forge remote URLs into https repo URLs', function()
    local url = require('forge.url')

    assert.equals('https://github.com/owner/repo', url.normalize('git@github.com:owner/repo.git'))
    assert.equals(
      'https://gitlab.com/group/project',
      url.normalize('  ssh://git@gitlab.com/group/project.git  ')
    )
    assert.equals(
      'https://gitlab.com/group/project',
      url.normalize('https://gitlab.com/group/project?foo=1#frag')
    )
  end)

  it('splits normalized forge URLs into host and path', function()
    local url = require('forge.url')

    assert.same({ 'codeberg.org', 'owner/repo' }, { url.split('git@codeberg.org:owner/repo.git') })
  end)

  it('drops gitlab subject suffixes when splitting forge URLs', function()
    local url = require('forge.url')

    assert.same(
      { 'gitlab.com', 'group/subgroup/project' },
      { url.split('https://gitlab.com/group/subgroup/project/-/merge_requests/42') }
    )
  end)

  it('returns nil for unsupported or empty URLs', function()
    local url = require('forge.url')

    assert.is_nil(url.normalize('   '))
    assert.is_nil(url.split('owner/repo'))
  end)
end)
