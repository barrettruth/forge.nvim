vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('layout', function()
  before_each(function()
    package.loaded['forge.layout'] = nil
  end)

  it(
    'uses exact maxima for small samples while ignoring isolated outliers in larger ones',
    function()
      local layout = require('forge.layout')

      local small = layout.measure({ 'aa', 'bbbbbbbb' })
      assert.equals(8, small.max)

      local large = layout.measure({ 'aa', 'aa', 'aa', 'aa', string.rep('x', 20) })
      assert.equals(2, large.max)
    end
  )

  it('drops optional columns when the budget is too small', function()
    local layout = require('forge.layout')
    local plan = layout.plan({
      width = 8,
      columns = {
        { key = 'id', fixed = 2 },
        {
          key = 'title',
          gap = ' ',
          min = 4,
          preferred = 6,
          max = 6,
          shrink = 2,
        },
        {
          key = 'meta',
          gap = ' ',
          min = 3,
          preferred = 5,
          max = 5,
          optional = true,
          drop = 1,
          shrink = 1,
        },
      },
    })

    assert.equals('narrow', plan.mode)
    assert.equals(0, plan.widths.meta)
    assert.is_true(plan.used <= 8)
  end)

  it('packs compact columns instead of padding them', function()
    local layout = require('forge.layout')
    local columns = {
      {
        key = 'left',
        min = 4,
        preferred = 6,
        max = 6,
        shrink = 2,
        pack_on = 'compact',
      },
      { key = 'right', gap = ' ', fixed = 2 },
    }

    local compact = layout.plan({ width = 8, columns = columns })
    assert.equals('compact', compact.mode)
    assert.same({ { 'ab' }, { ' xy' } }, layout.render(compact, { left = 'ab', right = 'xy' }))

    local wide = layout.plan({ width = 9, columns = columns })
    assert.equals('wide', wide.mode)
    assert.same({ { 'ab    ' }, { ' xy' } }, layout.render(wide, { left = 'ab', right = 'xy' }))
  end)
end)
