vim.opt.runtimepath:prepend(vim.fn.getcwd())

local close_calls = 0
local ctx_clears = 0
local ansi_headers = false
local fzf_config
local sigwinch_calls = {}
local sigwinch_handlers = {}
local function header_hls(bind, text, separator)
  return {
    header_bind = bind or 'FzfLuaHeaderBind',
    header_text = text or 'FzfLuaHeaderText',
    fzf = {
      info = separator or 'FzfLuaFzfInfo',
    },
  }
end

local function set_header_hls(bind, text, separator, legacy)
  local hls = header_hls(bind, text, separator)
  fzf_config.globals.hls = legacy == false and nil or vim.deepcopy(hls)
  fzf_config.globals.__HLS = vim.deepcopy(hls)
end

fzf_config = {
  globals = {
    hls = header_hls(),
    __HLS = header_hls(),
  },
}

package.preload['fzf-lua.config'] = function()
  return fzf_config
end

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(group, text)
      if
        group == 'FzfLuaHeaderBind'
        or group == 'FzfLuaHeaderText'
        or group == 'FzfLuaFzfInfo'
        or group == 'ForgeTestHeaderBind'
        or group == 'ForgeTestHeaderText'
        or group == 'ForgeTestHeaderSep'
      then
        if ansi_headers then
          return ('\27[38;2;1;2;3m%s\27[0m'):format(text), '\27[38;2;1;2;3m'
        end
        return ('[%s:%s]'):format(group, text), '\27[38;2;1;2;3m'
      end
      if group == 'ForgeBranch' or group == 'ForgeBranchCurrent' or group == 'ForgeMerged' then
        return ('\27[48;2;255;255;255m\27[38;2;1;2;3m%s\27[0m'):format(text)
      end
      return text, '\27[38;2;1;2;3m'
    end,
    fzf_winobj = function()
      return {
        fzf_winid = vim.api.nvim_get_current_win(),
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

local function collect_lines(lines)
  if type(lines) ~= 'function' then
    return vim.deepcopy(lines)
  end
  local collected = {}
  lines(function(line)
    if line then
      collected[#collected + 1] = line
    end
  end)
  return collected
end

package.preload['fzf-lua'] = function()
  return {
    fzf_exec = function(lines, opts)
      captured = { lines = lines, opts = opts }
    end,
  }
end

package.preload['fzf-lua.win'] = function()
  return {
    on_SIGWINCH = function(opts, scope, cb)
      sigwinch_handlers[scope] = { opts = opts, cb = cb }
      return true
    end,
    SIGWINCH = function(scopes)
      sigwinch_calls[#sigwinch_calls + 1] = scopes
      return true
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
    ansi_headers = false
    sigwinch_calls = {}
    sigwinch_handlers = {}
    package.loaded['forge'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.fzf'] = nil
    package.loaded['fzf-lua.config'] = nil
    package.loaded['fzf-lua.win'] = nil
    vim.g.forge = nil
    set_header_hls()
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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.same({ '#42 fix api drift alice  1h\t1' }, captured.lines)
    assert.equals('PRs> ', captured.opts.prompt)
    assert.equals('1', captured.opts.fzf_opts['--with-nth'])
    assert.equals('2', captured.opts.fzf_opts['--accept-nth'])
  end)

  it('opts out of fzf-lua hide and resume so <c-c> fully exits forge pickers', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = { { '#42' } },
          value = '42',
        },
      },
      actions = {},
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.is_true(captured.opts.no_hide)
    assert.is_true(captured.opts.no_resume)
  end)

  it('renders headers with enter, ctrl, and tab labels without to text', function()
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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[FzfLuaHeaderBind:cr]> [FzfLuaHeaderText:more]|[FzfLuaHeaderBind:^X] [FzfLuaHeaderText:browse]|<[FzfLuaHeaderBind:tab]> [FzfLuaHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
    assert.is_nil(captured.opts.fzf_opts['--header']:match(' to '))
    assert.is_function(captured.opts.actions.tab)
  end)

  it('uses resolved fzf-lua header highlight config for binds and labels', function()
    set_header_hls('ForgeTestHeaderBind', 'ForgeTestHeaderText', 'ForgeTestHeaderSep')

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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[ForgeTestHeaderBind:cr]> [ForgeTestHeaderText:more]|[ForgeTestHeaderBind:^X] [ForgeTestHeaderText:browse]|<[ForgeTestHeaderBind:tab]> [ForgeTestHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('supports fzf-lua __HLS header highlight config', function()
    set_header_hls('ForgeTestHeaderBind', 'ForgeTestHeaderText', 'ForgeTestHeaderSep', false)

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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[ForgeTestHeaderBind:cr]> [ForgeTestHeaderText:more]|[ForgeTestHeaderBind:^X] [ForgeTestHeaderText:browse]|<[ForgeTestHeaderBind:tab]> [ForgeTestHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('renders headers for single-action pickers', function()
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
    assert.equals(
      ':: <[FzfLuaHeaderBind:cr]> [FzfLuaHeaderText:use]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('seeds dynamic headers from placeholder rows when no entity rows exist', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Open PRs (0)> ',
      entries = {
        {
          display = { { 'Failed to fetch PRs', 'ForgeDim' } },
          value = nil,
          placeholder = true,
          placeholder_kind = 'error',
        },
      },
      actions = {
        {
          name = 'default',
          label = function(entry)
            if entry and entry.load_more then
              return 'load more'
            end
            return 'checkout'
          end,
          available = function(entry)
            return entry ~= nil and not entry.placeholder
          end,
          fn = function() end,
        },
        {
          name = 'create',
          label = 'create',
          fn = function() end,
        },
        {
          name = 'filter',
          label = 'filter',
          available = function(entry)
            return not (entry and entry.placeholder_kind == 'error')
          end,
          fn = function() end,
        },
        {
          name = 'refresh',
          label = 'refresh',
          fn = function() end,
        },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: [FzfLuaHeaderBind:^A] [FzfLuaHeaderText:create]|[FzfLuaHeaderBind:^R] [FzfLuaHeaderText:refresh]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('binds a hidden back action without adding a header hint', function()
    local picker = require('forge.picker.fzf')
    local back_calls = 0
    picker.pick({
      prompt = 'PR #42 More> ',
      entries = {
        {
          display = { { 'Edit' } },
          value = 'Edit',
        },
      },
      actions = {
        { name = 'default', label = 'run', fn = function() end },
      },
      picker_name = '_menu',
      back = function()
        back_calls = back_calls + 1
      end,
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[FzfLuaHeaderBind:cr]> [FzfLuaHeaderText:run]',
      captured.opts.fzf_opts['--header']
    )
    assert.is_function(captured.opts.actions['ctrl-o'])

    captured.opts.actions['ctrl-o']({})

    assert.equals(1, back_calls)
  end)

  it('skips unavailable actions without closing the picker', function()
    local picker = require('forge.picker.fzf')
    local calls = 0
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = { { '#42' } },
          value = { num = '42', state = 'OPEN' },
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function()
            calls = calls + 1
          end,
        },
        {
          name = 'browse',
          label = 'browse',
          available = function()
            return false
          end,
          fn = function()
            calls = calls + 10
          end,
        },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[FzfLuaHeaderBind:cr]> [FzfLuaHeaderText:open]',
      captured.opts.fzf_opts['--header']
    )
    assert.is_function(captured.opts.actions['ctrl-x'])

    captured.opts.actions['ctrl-x']({ '1' })

    assert.equals(0, calls)
    assert.equals(0, close_calls)
    assert.equals(0, ctx_clears)
  end)

  it('renders the issue filter hint when the action is labeled', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Open Issues> ',
      entries = {
        {
          display = { { '#7' }, { ' Bug' } },
          value = '7',
        },
      },
      actions = {
        { name = 'default', label = 'open', fn = function() end },
        { name = 'browse', fn = function() end },
        { name = 'toggle', label = 'close', fn = function() end },
        { name = 'create', fn = function() end },
        { name = 'filter', label = 'filter', fn = function() end },
        { name = 'refresh', fn = function() end },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals(
      ':: <[FzfLuaHeaderBind:cr]> [FzfLuaHeaderText:open]|[FzfLuaHeaderBind:^S] [FzfLuaHeaderText:close]|<[FzfLuaHeaderBind:tab]> [FzfLuaHeaderText:filter]',
      captured.opts.fzf_opts['--header']
    )
  end)

  it('renders root menu rows with visible labels and hidden selection ids', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Forge> ',
      entries = {
        {
          display = { { 'CI' } },
          value = 'ci.current_branch',
        },
      },
      actions = {},
      picker_name = '_menu',
    })

    assert.is_not_nil(captured)
    assert.same({ 'CI\t1' }, captured.lines)
  end)

  it('suppresses headers when a picker opts out', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Forge> ',
      entries = {
        {
          display = { { 'Releases' } },
          value = 'releases.all',
        },
      },
      actions = {
        { name = 'default', label = 'open', fn = function() end },
      },
      picker_name = '_menu',
      show_header = false,
    })

    assert.is_not_nil(captured)
    assert.is_nil(captured.opts.fzf_opts['--header'])
  end)

  it('wires a focus bind and appends per-row headers when a label is dynamic', function()
    vim.g.forge = { keys = { ci = { toggle = '<c-s>', filter = '<tab>' } } }
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {
        {
          display = { { 'run' } },
          value = { id = '1', status = 'in_progress' },
        },
        {
          display = { { 'done' } },
          value = { id = '2', status = 'success' },
        },
      },
      actions = {
        { name = 'default', label = 'open', fn = function() end },
        {
          name = 'toggle',
          label = function(entry)
            if not entry then
              return 'cancel/rerun'
            end
            local status = entry.value.status
            if status == 'in_progress' then
              return 'cancel'
            end
            return 'rerun'
          end,
          fn = function() end,
        },
        { name = 'filter', label = 'filter', fn = function() end },
      },
      picker_name = 'ci',
    })

    assert.is_not_nil(captured)
    local bind = captured.opts.keymap
      and captured.opts.keymap.fzf
      and captured.opts.keymap.fzf.focus
    assert.is_string(bind)
    assert.equals("transform-header:printf '%b' {3}", bind)
    assert.equals(2, #captured.lines)
    assert.truthy(captured.lines[1]:match('FzfLuaHeaderText:cancel'))
    assert.truthy(captured.lines[2]:match('FzfLuaHeaderText:rerun'))
    assert.truthy(captured.opts.fzf_opts['--header']:find('cancel'))
  end)

  it('escapes dynamic header ansi for focus transform replay', function()
    ansi_headers = true

    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {
        {
          display = { { 'build' } },
          value = { status = 'in_progress' },
        },
        {
          display = { { 'deploy' } },
          value = { status = 'done' },
        },
      },
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function() end,
        },
        {
          name = 'toggle',
          label = function(entry)
            local status = entry and entry.value and entry.value.status
            if status == 'in_progress' then
              return 'cancel'
            end
            return 'rerun'
          end,
          fn = function() end,
        },
        { name = 'filter', label = 'filter', fn = function() end },
      },
      picker_name = 'ci',
    })

    assert.is_not_nil(captured)
    assert.equals("transform-header:printf '%b' {3}", captured.opts.keymap.fzf.focus)
    assert.truthy(captured.opts.fzf_opts['--header']:find('\27%[38;2;1;2;3m'))
    assert.truthy(captured.lines[1]:find('\\033%[38;2;1;2;3m'))
    assert.truthy(captured.lines[1]:find('cancel'))
    assert.truthy(captured.lines[2]:find('rerun'))
  end)

  it('does not wire a focus bind when no action labels are dynamic', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Releases> ',
      entries = {
        {
          display = { { 'v1.0' } },
          value = { tag = 'v1.0' },
        },
      },
      actions = {
        { name = 'default', label = 'browse', fn = function() end },
      },
      picker_name = 'release',
    })

    assert.is_not_nil(captured)
    local has_focus = captured.opts.keymap
      and captured.opts.keymap.fzf
      and captured.opts.keymap.fzf.focus
    assert.is_falsy(has_focus)
  end)

  it('returns a refresh handle for streamed pickers', function()
    local picker = require('forge.picker.fzf')
    local handle = picker.pick({
      prompt = 'CI> ',
      entries = {},
      actions = {},
      picker_name = 'ci',
      stream = function(emit)
        emit({
          display = { { 'build' } },
          value = '1',
        })
        emit(nil)
      end,
    })

    assert.is_not_nil(handle)
    assert.is_function(handle.refresh)
    captured.opts._contents = 'printf build'

    local scope = next(sigwinch_handlers)
    assert.is_string(scope)
    assert.same(captured.opts, sigwinch_handlers[scope].opts)
    assert.equals('reload:printf build', sigwinch_handlers[scope].cb({}))
    assert.is_true(handle.refresh())
    assert.same({ scope }, sigwinch_calls[1])
  end)

  it('renders branch rows with visible labels and hidden selection ids', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Branches> ',
      entries = {
        {
          display = {
            { '* ', 'ForgeBranchCurrent' },
            { 'main', 'ForgeBranchCurrent' },
            { ' [origin/main]', 'Directory' },
          },
          value = {
            name = 'main',
            upstream = 'origin/main',
            subject = 'Main branch',
          },
        },
      },
      actions = {},
      picker_name = 'branch',
    })

    assert.is_not_nil(captured)
    assert.same(1, #captured.lines)
    assert.truthy(captured.lines[1]:find('^\27%[38;2;1;2;3m%* \27%[0m', 1))
    assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3mmain\27%[0m', 1))
    assert.truthy(captured.lines[1]:find(' %[origin/main%]\t1$', 1))
  end)

  it('re-runs stream on each source invocation without duplicating rows', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {},
      actions = {},
      picker_name = 'ci',
      stream = function(emit)
        emit({
          display = { { 'check one' } },
          value = 'check-1',
        })
        emit({
          display = { { 'check two' } },
          value = 'check-2',
        })
        emit(nil)
      end,
    })

    assert.is_not_nil(captured)
    assert.is_function(captured.lines)

    local function collect_streamed_lines()
      local lines = {}
      captured.lines(function(line)
        if line then
          table.insert(lines, line)
        end
      end)
      return lines
    end

    local expected = { 'check-1\tcheck one\t1', 'check-2\tcheck two\t2' }
    assert.same(expected, collect_streamed_lines())
    assert.same(expected, collect_streamed_lines())
  end)

  it('renders entries against the live picker width when available', function()
    local old_win_get_width = vim.api.nvim_win_get_width
    vim.api.nvim_win_get_width = function()
      return 40
    end

    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {
        {
          display = { { 'Markdown Form...' } },
          render_display = function(width)
            return { { width >= 40 and 'Markdown Format Check' or 'Markdown Form...' } }
          end,
          value = 'check-1',
        },
      },
      actions = {},
      picker_name = 'ci',
    })

    assert.is_function(captured.lines)
    assert.same({ 'Markdown Format Check\t1' }, collect_lines(captured.lines))
    vim.api.nvim_win_get_width = old_win_get_width
  end)

  it('renders worktree rows with visible labels and hidden selection ids', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Worktrees> ',
      entries = {
        {
          display = {
            { '* ', 'ForgeBranchCurrent' },
            { '/repo-feature', 'Directory' },
            { ' feature', 'ForgeBranch' },
            { ' abc1234', 'ForgeCommitHash' },
          },
          value = {
            path = '/repo-feature',
            branch = 'feature',
            detached = false,
            short_head = 'abc1234',
          },
        },
        {
          display = {
            { '  ', 'ForgeDim' },
            { '/repo-bisect', 'Directory' },
            { ' detached', 'ForgeDim' },
            { ' def5678', 'ForgeCommitHash' },
          },
          value = {
            path = '/repo-bisect',
            branch = '',
            detached = true,
            short_head = 'def5678',
          },
        },
      },
      actions = {},
      picker_name = 'worktree',
    })

    assert.is_not_nil(captured)
    assert.same(2, #captured.lines)
    assert.truthy(captured.lines[1]:find('^\27%[38;2;1;2;3m%* \27%[0m/repo%-feature', 1))
    assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3m feature\27%[0m', 1))
    assert.truthy(captured.lines[1]:find(' abc1234\t1$', 1))
    assert.equals('  /repo-bisect detached def5678\t2', captured.lines[2])
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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    captured.opts.actions.enter({ '1' })
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
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.same('table', type(captured.opts.actions['ctrl-x']))
    assert.is_true(captured.opts.actions['ctrl-x'].reload)
    assert.is_nil(captured.opts.actions['ctrl-x'].noclose)
    captured.opts.actions['ctrl-x'].fn({ '1' })
    assert.equals('42', selected.value)
  end)

  it('pins reload actions to the index field so fzf passes just that column', function()
    local picker = require('forge.picker.fzf')
    local invoked = 0
    picker.pick({
      prompt = 'CI> ',
      entries = {},
      stream = function(emit)
        emit({
          display = { { 'run' } },
          value = { id = '1', status = 'in_progress' },
        })
        emit(nil)
      end,
      actions = {
        {
          name = 'default',
          label = 'open',
          close = false,
          fn = function(entry)
            if entry then
              invoked = invoked + 1
            end
          end,
        },
      },
      picker_name = 'ci',
    })

    assert.is_not_nil(captured)
    local enter = captured.opts.actions['enter']
    assert.same('table', type(enter))
    assert.is_true(enter.reload)
    assert.equals('{3}', enter.field_index)
    captured.lines(function() end)
    enter.fn({ '1' })
    assert.equals(1, invoked)
  end)

  it('lets streamed filter actions opt out of reload wrapping', function()
    local picker = require('forge.picker.fzf')
    local invoked = 0
    picker.pick({
      prompt = 'Issues> ',
      entries = {},
      stream = function(emit)
        emit({
          display = { { '#1' } },
          value = '1',
        })
        emit(nil)
      end,
      actions = {
        {
          name = 'filter',
          label = 'filter',
          reload = false,
          fn = function()
            invoked = invoked + 1
          end,
        },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.is_function(captured.opts.actions.tab)
    captured.opts.actions.tab({ '1' })
    assert.equals(1, invoked)
  end)

  it('lets streamed back actions opt out of reload wrapping', function()
    local picker = require('forge.picker.fzf')
    local invoked = 0
    picker.pick({
      prompt = 'Checks> ',
      entries = {},
      stream = function(emit)
        emit({
          display = { { 'lint' } },
          value = 'lint',
        })
        emit(nil)
      end,
      actions = {},
      picker_name = 'ci',
      back = function()
        invoked = invoked + 1
      end,
    })

    assert.is_not_nil(captured)
    assert.is_function(captured.opts.actions['ctrl-o'])
    captured.opts.actions['ctrl-o']({})
    assert.equals(1, invoked)
  end)

  it('pins reload actions to field 2 on untracked pickers', function()
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
          fn = function() end,
        },
      },
      picker_name = 'issue',
    })

    assert.is_not_nil(captured)
    assert.equals('{2}', captured.opts.actions['ctrl-x'].field_index)
  end)

  it('resolves selections when fzf-lua returns the full rendered row', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Forge> ',
      entries = {
        {
          display = { { 'Releases' } },
          value = 'releases.all',
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
      picker_name = '_menu',
    })

    assert.is_not_nil(captured)
    captured.opts.actions.enter({ 'Releases\t1' })
    assert.equals('releases.all', selected.value)
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
    captured.opts.actions.enter.fn({ '1' })

    vim.wait(100, function()
      return selected ~= false
    end)

    assert.equals(1, close_calls)
    assert.equals(1, ctx_clears)
    assert.is_true(selected.load_more)
  end)

  it('keeps close=true actions open when the selected row requests it', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'PRs> ',
      entries = {
        {
          display = { { 'Load more...' } },
          value = nil,
          load_more = true,
          keep_open = true,
        },
      },
      actions = {
        {
          name = 'default',
          label = 'checkout',
          fn = function(entry)
            selected = entry
          end,
        },
      },
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.same('table', type(captured.opts.actions.enter))
    assert.is_true(captured.opts.actions.enter.reload)

    captured.opts.actions.enter.fn({ '1' })

    assert.equals(0, close_calls)
    assert.is_true(selected.load_more)
  end)

  it('streams entries and resolves streamed selections', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'Issues> ',
      entries = {},
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
      stream = function(emit)
        emit({
          display = { { '#1' } },
          value = '1',
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
    local done = false
    captured.lines(function(line)
      if line == nil then
        done = true
        return
      end
      lines[#lines + 1] = line
    end)

    assert.same({ '1\t#1\t1', '2\t#2\t2' }, lines)
    assert.is_true(done)

    captured.opts.actions.enter.fn({ '2' })
    assert.equals('2', selected.value)
  end)

  it('rebuilds streamed entries each time the source function runs', function()
    local picker = require('forge.picker.fzf')
    local phase = 1
    picker.pick({
      prompt = 'PRs> ',
      entries = {},
      stream = function(emit)
        emit({ display = { { '#1' } }, value = '1' })
        if phase == 2 then
          emit({ display = { { '#2' } }, value = '2' })
        end
        emit(nil)
      end,
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
      picker_name = 'pr',
    })

    assert.is_not_nil(captured)
    assert.same('function', type(captured.lines))
    assert.equals('2', captured.opts.fzf_opts['--with-nth'])
    assert.equals('3', captured.opts.fzf_opts['--accept-nth'])
    assert.equals('1', captured.opts.fzf_opts['--id-nth'])
    assert.equals('', captured.opts.fzf_opts['--track'])

    local first = {}
    captured.lines(function(line)
      if line ~= nil then
        first[#first + 1] = line
      end
    end)

    phase = 2

    local second = {}
    captured.lines(function(line)
      if line ~= nil then
        second[#second + 1] = line
      end
    end)

    assert.same({ '1\t#1\t1' }, first)
    assert.same({ '1\t#1\t1', '2\t#2\t2' }, second)

    captured.opts.actions.enter.fn({ '2' })
    assert.equals('2', selected.value)
  end)

  it('redirects tracked load more selection to the first new row after reload', function()
    local picker = require('forge.picker.fzf')
    local phase = 1
    picker.pick({
      prompt = 'CI> ',
      entries = {},
      stream = function(emit)
        emit({ display = { { '#1' } }, value = '1' })
        if phase == 2 then
          emit({ display = { { '#2' } }, value = '2' })
        end
        local next_limit = phase == 1 and 2 or 3
        emit({
          display = { { 'Load more...' } },
          value = nil,
          load_more = true,
          next_limit = next_limit,
          keep_open = true,
        })
        emit(nil)
      end,
      actions = {
        {
          name = 'default',
          label = 'more',
          fn = function(entry)
            if entry and entry.load_more then
              phase = 2
            end
          end,
        },
      },
      picker_name = 'ci',
    })

    assert.is_not_nil(captured)
    assert.same('table', type(captured.opts.actions.enter))

    captured.lines(function() end)
    captured.opts.actions.enter.fn({ '2' })

    local lines = {}
    captured.lines(function(line)
      if line ~= nil then
        lines[#lines + 1] = line
      end
    end)

    assert.same({
      '1\t#1\t1',
      '__load_more__:2\t#2\t2',
      '__load_more__:3\tLoad more...\t3',
    }, lines)
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
    assert.same({ '#2\t2' }, captured.lines)
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

    assert.same({ '2\t#2\t2' }, lines)
  end)

  it('strips merged and branch background ANSI so the selected row highlight can win', function()
    local picker = require('forge.picker.fzf')
    picker.pick({
      prompt = 'CI> ',
      entries = {
        {
          display = {
            { 'm', 'ForgeMerged' },
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

  it(
    'strips author and metadata background ANSI so the selected row highlight can win across pickers',
    function()
      local utils = require('fzf-lua.utils')
      local old_ansi_from_hl = utils.ansi_from_hl
      utils.ansi_from_hl = function(group, text)
        if group == 'FzfLuaHeaderBind' or group == 'FzfLuaHeaderText' then
          return ('[%s:%s]'):format(group, text)
        end
        if group then
          return ('\27[48;2;255;255;255m\27[38;2;1;2;3m%s\27[0m'):format(text)
        end
        return text
      end

      local picker = require('forge.picker.fzf')
      picker.pick({
        prompt = 'Issues> ',
        entries = {
          {
            display = {
              { '#7', 'ForgeNumber' },
              { ' Cursorline bug ' },
              { 'alice', 'ForgeAuthor' },
              { ' 1h', 'ForgeTime' },
            },
            value = '7',
          },
          {
            display = {
              { 'abc1234', 'ForgeCommitHash' },
              { ' fix selection ' },
              { 'bob', 'ForgeCommitAuthor' },
              { ' /repo-feature', 'Directory' },
              { ' detached', 'ForgeDim' },
            },
            value = 'abc1234',
          },
        },
        actions = {},
        picker_name = 'issue',
      })

      utils.ansi_from_hl = old_ansi_from_hl

      assert.is_not_nil(captured)
      assert.same(2, #captured.lines)
      assert.is_nil(captured.lines[1]:match('\27%[48;'))
      assert.is_nil(captured.lines[2]:match('\27%[48;'))
      assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3malice\27%[0m'))
      assert.truthy(captured.lines[1]:find('\27%[38;2;1;2;3m 1h\27%[0m'))
      assert.truthy(captured.lines[2]:find('\27%[38;2;1;2;3mbob\27%[0m'))
      assert.truthy(captured.lines[2]:find('\27%[38;2;1;2;3m /repo%-feature\27%[0m'))
      assert.truthy(captured.lines[2]:find('\27%[38;2;1;2;3m detached\27%[0m'))
    end
  )
end)
