vim.opt.runtimepath:prepend(vim.fn.getcwd())

local close_calls = 0
local ctx_clears = 0

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(group, text)
      if group == 'FzfLuaHeaderBind' or group == 'FzfLuaHeaderText' then
        return ('[%s:%s]'):format(group, text)
      end
      if group == 'ForgeBranch' or group == 'ForgeBranchCurrent' then
        return ('\27[48;2;255;255;255m\27[38;2;1;2;3m%s\27[0m'):format(text)
      end
      return text, '\27[38;2;1;2;3m'
    end,
    fzf_winobj = function()
      return {
        close = function()
          close_calls = close_calls + 1
        end,
      }
    end,
    clear_CTX = function()
      ctx_clears = ctx_clears + 1
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
    close_calls = 0
    ctx_clears = 0
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
          ordinal = '42 fix api drift alice',
        },
      },
      actions = {},
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.same({ '1\t42 fix api drift alice\t#42 fix api drift alice  1h' }, captured.lines)
    assert.equals('PRs> ', captured.opts.prompt)
    assert.equals('3..', captured.opts.fzf_opts['--with-nth'])
    assert.equals('2', captured.opts.fzf_opts['--nth'])
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
        { name = 'default', label = 'more', fn = function() end },
        { name = 'browse', label = 'browse', fn = function() end },
        { name = 'filter', label = 'filter', fn = function() end },
      },
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.equals(
      '[FzfLuaHeaderBind:<cr>] [FzfLuaHeaderText:more]|[FzfLuaHeaderBind:^X] [FzfLuaHeaderText:browse]|[FzfLuaHeaderBind:^O] [FzfLuaHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
    assert.is_nil(captured.opts.fzf_opts['--header']:match(' to '))
  end)

  it('suppresses headers for single-action pickers', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issue Template> ',
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

  it('renders headers for git-local pickers without the legacy prefix', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Branches> ',
      entries = {
        {
          display = { { 'main' } },
          value = 'main',
        },
      },
      actions = {
        { name = 'default', label = 'switch', fn = function() end },
        { name = 'delete', label = 'delete', fn = function() end },
        { name = 'browse', label = 'browse', fn = function() end },
      },
      picker_name = 'branch',
    })

    assert.is_not_nil(captured)
    assert.equals(
      '[FzfLuaHeaderBind:<cr>] [FzfLuaHeaderText:switch]|[FzfLuaHeaderBind:^S] [FzfLuaHeaderText:delete]|[FzfLuaHeaderBind:^X] [FzfLuaHeaderText:browse]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('treats placeholder rows as no selection', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Open PRs (0)> ',
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
    captured.opts.actions.enter({ '1\tNo open PRs\tNo open PRs' })
    assert.is_nil(selected)
  end)

  it('keeps close=false actions open', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = { { '#42' } },
          value = '42',
        },
      },
      actions = {
        {
          name = 'browse',
          label = 'browse',
          close = false,
          fn = function(entry)
            selected = entry
          end,
        },
      },
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.same('table', type(captured.opts.actions['ctrl-x']))
    assert.is_true(captured.opts.actions['ctrl-x'].reload)
    assert.is_nil(captured.opts.actions['ctrl-x'].noclose)
    captured.opts.actions['ctrl-x'].fn({ '1\t42\t#42' })
    assert.equals('42', selected.value)
  end)

  it('closes close=false actions when the selected row forces it', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issues> ',
      entries = {
        {
          display = { { 'Load more...' } },
          value = nil,
          load_more = true,
          force_close = true,
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          close = false,
          fn = function(entry)
            selected = entry
          end,
        },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.same('table', type(captured.opts.actions.enter))
    assert.is_true(captured.opts.actions.enter.reload)
    captured.opts.actions.enter.fn({ '1\tLoad more\tLoad more...' })

    vim.wait(100, function()
      return selected ~= false
    end)

    assert.equals(1, close_calls)
    assert.equals(1, ctx_clears)
    assert.is_true(selected.load_more)
  end)

  it('streams entries and resolves streamed selections', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issues> ',
      entries = {
        {
          display = { { '#1' } },
          value = '1',
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
      picker_name = 'issue',
      stream = function(emit)
        emit({
          display = { { '#2' } },
          value = '2',
        })
        emit(nil)
      end,
    })

    assert.is_not_nil(captured)
    assert.same('function', type(captured.lines))

    local lines = {}
    local done = false
    captured.lines(function(line)
      if line == nil then
        done = true
        return
      end
      lines[#lines + 1] = line
    end)

    assert.same({ '1\t#1\t#1', '2\t#2\t#2' }, lines)
    assert.is_true(done)

    captured.opts.actions.enter({ '2\t#2\t#2' })
    assert.equals('2', selected.value)
  end)

  it('skips rows whose rendered display is blank', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issues> ',
      entries = {
        {
          display = { { '' } },
          value = 'blank',
        },
        {
          display = { { '#2' } },
          value = '2',
        },
      },
      actions = {},
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.same({ '2\t#2\t#2' }, captured.lines)
  end)

  it('skips streamed rows whose rendered display is blank', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issues> ',
      entries = {},
      actions = {},
      picker_name = 'issue',
      stream = function(emit)
        emit({
          display = { { '' } },
          value = 'blank',
        })
        emit({
          display = { { '#2' } },
          value = '2',
        })
        emit(nil)
      end,
    })

    assert.is_not_nil(captured)
    assert.same('function', type(captured.lines))

    local lines = {}
    captured.lines(function(line)
      if line ~= nil then
        lines[#lines + 1] = line
      end
    end)

    assert.same({ '2\t#2\t#2' }, lines)
  end)

  it('strips branch background ANSI so the selected row highlight can win', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {
        {
          display = {
            { '*', 'ForgePass' },
            { ' build ' },
            { 'feature/test', 'ForgeBranch' },
            { ' main', 'ForgeBranchCurrent' },
          },
          value = 'run-1',
        },
      },
      actions = {},
      picker_name = 'ci',
    })

    assert.is_not_nil(captured)
    assert.same(1, #captured.lines)
    assert.is_nil(captured.lines[1]:match('\27%[48;'))
    assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3mfeature/test\27%[0m'))
    assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3m main\27%[0m'))
  end)
end)
