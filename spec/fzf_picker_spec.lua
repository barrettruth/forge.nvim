vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(group, text)
      if group == 'FzfLuaHeaderBind' or group == 'FzfLuaHeaderText' then
        return ('[%s:%s]'):format(group, text)
      end
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
  local selected

  before_each(function()
    captured = nil
    selected = false
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

  it('renders headers with <cr> and ^X style key labels without to text', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = {
            { '#42', 'ForgeNumber' },
            { ' fix api drift ' },
          },
          value = '42',
        },
      },
      actions = {
        { name = 'checkout', label = 'checkout', fn = function() end },
        { name = 'browse', label = 'browse', fn = function() end },
        { name = 'filter', label = 'filter', fn = function() end },
      },
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: [FzfLuaHeaderBind:<cr>] [FzfLuaHeaderText:checkout]|[FzfLuaHeaderBind:^X] [FzfLuaHeaderText:browse]|[FzfLuaHeaderBind:^O] [FzfLuaHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
    assert.is_nil(captured.opts.fzf_opts['--header']:match(' to '))
  end)

  it('suppresses headers for single-action pickers', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issue template> ',
      entries = {
        {
          display = { { 'Bug report' } },
          value = 'bug',
        },
      },
      actions = {
        { name = 'default', label = 'use', fn = function() end },
      },
      picker_name = '_menu',
    })

    assert.is_not_nil(captured)
    assert.is_nil(captured.opts.fzf_opts['--header'])
  end)

  it('treats placeholder rows as no selection', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs (open · 0)> ',
      entries = {
        {
          display = { { 'No open PRs', 'ForgeDim' } },
          value = nil,
          placeholder = true,
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function(entry)
            selected = entry
          end,
        },
      },
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    captured.opts.actions.default({ '1\tNo open PRs' })
    assert.is_nil(selected)
  end)
end)
