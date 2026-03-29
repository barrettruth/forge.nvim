vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text, '\27[38;2;1;2;3m'
    end,
  }
end

local captured

package.preload['fzf-lua'] = function()
  return {
    fzf_exec = function(lines, opts)
      captured = { lines = lines, opts = opts }
    end,
  }
end

describe('fzf picker', function()
  before_each(function()
    captured = nil
    package.loaded['forge'] = nil
    package.loaded['forge.picker.fzf'] = nil
    vim.g.forge = nil
  end)

  it('renders highlighted segments when ansi_from_hl returns extra values', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = {
            { '#42', 'ForgeNumber' },
            { ' fix api drift ' },
            { 'alice  1h', 'ForgeDim' },
          },
          value = '42',
        },
      },
      actions = {},
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.same({ '1\t#42 fix api drift alice  1h' }, captured.lines)
    assert.equals('PRs> ', captured.opts.prompt)
  end)
end)
