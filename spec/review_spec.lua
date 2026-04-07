vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('review session', function()
  local review

  before_each(function()
    package.loaded['forge.review'] = nil
    review = require('forge.review')
    review.stop()
  end)

  after_each(function()
    review.stop()
    package.loaded['forge.review'] = nil
  end)

  it('stores a first-class session in review state', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      mode = 'unified',
      files = {
        { path = 'lua/forge/review.lua' },
      },
      current_file = 'lua/forge/review.lua',
      materialization = 'checkout',
      repo_root = '/repo',
    })

    assert.equals('origin/main', review.state.base)
    assert.equals('unified', review.state.mode)
    assert.equals('pr', review.current().subject.kind)
    assert.equals('42', review.current().subject.id)
    assert.equals('PR #42', review.current().subject.label)
    assert.equals('origin/main', review.current().subject.base_ref)
    assert.equals('pr-42', review.current().subject.head_ref)
    assert.equals('lua/forge/review.lua', review.current().current_file)
    assert.equals('checkout', review.current().materialization)
    assert.equals('/repo', review.current().repo_root)
  end)

  it('keeps the legacy start helper available', function()
    review.start('origin/main')

    assert.equals('origin/main', review.state.base)
    assert.equals('unified', review.state.mode)
    assert.equals('ref', review.current().subject.kind)
    assert.equals('origin/main', review.current().subject.base_ref)
  end)

  it('clears session state on stop', function()
    review.start_session({
      subject = {
        kind = 'pr',
        id = '42',
        label = 'PR #42',
        base_ref = 'origin/main',
        head_ref = 'pr-42',
      },
      repo_root = '/repo',
    })

    review.stop()

    assert.is_nil(review.state.base)
    assert.equals('unified', review.state.mode)
    assert.is_nil(review.current())
  end)
end)
