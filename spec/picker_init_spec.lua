vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function names(items)
  return vim.tbl_map(function(item)
    return item.name
  end, items)
end

describe('forge.surface_policy.pr_toggle_verb', function()
  local surface_policy

  before_each(function()
    package.loaded['forge.surface.policy'] = nil
    surface_policy = require('forge.surface.policy')
  end)

  it('returns close for open prs', function()
    assert.equals('close', surface_policy.pr_toggle_verb({ value = { num = '1', state = 'OPEN' } }))
  end)

  it('returns close for lowercase opened state (gitlab)', function()
    assert.equals(
      'close',
      surface_policy.pr_toggle_verb({ value = { num = '1', state = 'opened' } })
    )
  end)

  it('returns reopen for closed (non-merged) prs', function()
    assert.equals(
      'reopen',
      surface_policy.pr_toggle_verb({ value = { num = '1', state = 'CLOSED' } })
    )
  end)

  it('returns nil for merged prs because merged is a terminal state', function()
    assert.is_nil(surface_policy.pr_toggle_verb({ value = { num = '1', state = 'MERGED' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(surface_policy.pr_toggle_verb({ placeholder = true, value = { state = 'OPEN' } }))
    assert.is_nil(surface_policy.pr_toggle_verb({ load_more = true, value = { state = 'OPEN' } }))
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(surface_policy.pr_toggle_verb(nil))
    assert.is_nil(surface_policy.pr_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.surface_policy.issue_toggle_verb', function()
  local surface_policy

  before_each(function()
    package.loaded['forge.surface.policy'] = nil
    surface_policy = require('forge.surface.policy')
  end)

  it('returns close for open issues', function()
    assert.equals(
      'close',
      surface_policy.issue_toggle_verb({ value = { num = '1', state = 'opened' } })
    )
  end)

  it('returns reopen for closed issues', function()
    assert.equals(
      'reopen',
      surface_policy.issue_toggle_verb({ value = { num = '1', state = 'closed' } })
    )
  end)

  it('does not treat merged as a valid issue state', function()
    assert.is_nil(surface_policy.issue_toggle_verb({ value = { num = '1', state = 'merged' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(
      surface_policy.issue_toggle_verb({ placeholder = true, value = { state = 'OPEN' } })
    )
    assert.is_nil(
      surface_policy.issue_toggle_verb({ load_more = true, value = { state = 'OPEN' } })
    )
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(surface_policy.issue_toggle_verb(nil))
    assert.is_nil(surface_policy.issue_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.surface_policy.ci_toggle_verb', function()
  local surface_policy

  before_each(function()
    package.loaded['forge.surface.policy'] = nil
    surface_policy = require('forge.surface.policy')
  end)

  it('returns cancel for in-progress runs', function()
    for _, status in ipairs({ 'in_progress', 'queued', 'pending', 'running' }) do
      assert.equals(
        'cancel',
        surface_policy.ci_toggle_verb({ value = { id = '1', status = status } }),
        'status=' .. status
      )
    end
  end)

  it('returns rerun for completed runs', function()
    for _, status in ipairs({ 'success', 'failure', 'cancelled', 'timed_out' }) do
      assert.equals(
        'rerun',
        surface_policy.ci_toggle_verb({ value = { id = '1', status = status } }),
        'status=' .. status
      )
    end
  end)

  it('returns rerun when a run status is missing', function()
    assert.equals('rerun', surface_policy.ci_toggle_verb({ value = { id = '1' } }))
  end)

  it('returns nil for skipped runs', function()
    assert.is_nil(surface_policy.ci_toggle_verb({ value = { id = '1', status = 'skipped' } }))
  end)

  it('returns nil for placeholder or load_more rows', function()
    assert.is_nil(
      surface_policy.ci_toggle_verb({ placeholder = true, value = { status = 'running' } })
    )
    assert.is_nil(
      surface_policy.ci_toggle_verb({ load_more = true, value = { status = 'running' } })
    )
  end)

  it('returns nil when the entry has no value table', function()
    assert.is_nil(surface_policy.ci_toggle_verb(nil))
    assert.is_nil(surface_policy.ci_toggle_verb({ value = 'not-a-table' }))
  end)
end)

describe('forge.surface_policy.resolve_label', function()
  local surface_policy

  before_each(function()
    package.loaded['forge.surface.policy'] = nil
    surface_policy = require('forge.surface.policy')
  end)

  it('returns string labels verbatim', function()
    assert.equals('merge', surface_policy.resolve_label({ name = 'merge', label = 'merge' }))
  end)

  it('hides labels when the action is unavailable', function()
    local def = {
      name = 'merge',
      label = 'merge',
      available = function()
        return false
      end,
    }

    assert.is_nil(surface_policy.resolve_label(def, { value = { state = 'OPEN' } }))
  end)

  it('invokes function labels with the entry', function()
    local captured
    local def = {
      name = 'toggle',
      label = function(entry)
        captured = entry
        return 'close'
      end,
    }
    local label = surface_policy.resolve_label(def, { value = { state = 'OPEN' } })
    assert.equals('close', label)
    assert.same({ value = { state = 'OPEN' } }, captured)
  end)

  it('returns nil when a function label raises', function()
    local def = {
      name = 'toggle',
      label = function()
        error('boom')
      end,
    }
    assert.is_nil(surface_policy.resolve_label(def, nil))
  end)

  it('treats availability function failures as unavailable', function()
    local def = {
      name = 'toggle',
      label = 'close',
      available = function()
        error('boom')
      end,
    }

    assert.is_nil(surface_policy.resolve_label(def, nil))
    assert.is_false(surface_policy.available(def, nil))
  end)

  it('resolves static and dynamic availability', function()
    assert.is_true(surface_policy.available({ name = 'a' }, nil))
    assert.is_false(surface_policy.available({ name = 'b', available = false }, nil))
    assert.is_true(surface_policy.available({
      name = 'c',
      available = function(entry)
        return entry ~= nil
      end,
    }, { value = 1 }))
    assert.is_false(surface_policy.available({
      name = 'd',
      available = function(entry)
        return entry ~= nil
      end,
    }, nil))
  end)

  it('reports dynamic labels', function()
    assert.is_true(surface_policy.has_dynamic_label({ name = 'a', label = function() end }))
    assert.is_false(surface_policy.has_dynamic_label({ name = 'b', label = 'static' }))
    assert.is_true(surface_policy.has_dynamic_label({ name = 'c', available = function() end }))
    assert.is_false(surface_policy.has_dynamic_label({ name = 'd' }))
  end)
end)

describe('forge.picker.order_hints', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('orders hints by explicit semantic rank', function()
    local ordered = picker.order_hints({
      { name = 'refresh', key = '^R', label = 'refresh' },
      { name = 'filter', key = '<tab>', label = 'filter' },
      { name = 'browse', key = '^X', label = 'web' },
      { name = 'default', key = '<cr>', label = 'open' },
    }, {
      'default',
      'browse',
      'filter',
      'refresh',
    })

    assert.same({ 'default', 'browse', 'filter', 'refresh' }, names(ordered))
  end)

  it('preserves original order for unranked hints and dedupes by rendered key', function()
    local ordered = picker.order_hints({
      { name = 'filter', key = '<tab>', label = 'filter' },
      { name = 'mystery_a', key = '^M', label = 'alpha' },
      { name = 'create', key = '^A', label = 'create' },
      { name = 'mystery_b', key = '^M', label = 'beta' },
      { name = 'refresh', key = '^R', label = 'refresh' },
      { name = 'default', key = '<cr>', label = 'open' },
    }, {
      'default',
      'create',
      'filter',
      'refresh',
    })

    assert.same({ 'default', 'create', 'filter', 'refresh', 'mystery_a' }, names(ordered))
  end)
end)

describe('forge.picker.search_key', function()
  local picker

  before_each(function()
    package.loaded['forge.picker'] = nil
    picker = require('forge.picker')
  end)

  it('includes CI context alongside the run name and branch', function()
    local key = picker.search_key('ci', {
      value = {
        name = 'feat(browse): accept shorthand target paths (#486)',
        context = 'quality',
        branch = 'main',
      },
    })

    assert.equals('feat(browse): accept shorthand target paths (#486) quality main', key)
  end)
end)

describe('forge.picker.pick', function()
  local old_preload
  local warnings

  before_each(function()
    warnings = {}
    old_preload = {
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker.fzf'] = package.preload['forge.picker.fzf'],
      ['fzf-lua'] = package.preload['fzf-lua'],
    }

    package.preload['forge.logger'] = function()
      return {
        warn = function(msg)
          warnings[#warnings + 1] = msg
        end,
      }
    end

    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.fzf'] = nil
    package.loaded['fzf-lua'] = nil
  end)

  after_each(function()
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker.fzf'] = old_preload['forge.picker.fzf']
    package.preload['fzf-lua'] = old_preload['fzf-lua']

    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.fzf'] = nil
    package.loaded['fzf-lua'] = nil
  end)

  it('warns cleanly when fzf-lua is unavailable', function()
    package.preload['fzf-lua'] = function()
      error("module 'fzf-lua' not found")
    end

    local picker = require('forge.picker')
    local handle = picker.pick({
      entries = {},
      actions = {},
      picker_name = 'pr',
    })

    assert.is_nil(handle)
    assert.same({
      "fzf-lua not found (interactive routes and require('forge.picker').pick() disabled; direct :Forge commands and deterministic Lua helpers still available)",
    }, warnings)
  end)

  it('delegates to the fzf backend when available', function()
    local captured
    package.preload['fzf-lua'] = function()
      return {}
    end
    package.preload['forge.picker.fzf'] = function()
      return {
        pick = function(opts)
          captured = opts
          return { refresh = function() end }
        end,
      }
    end

    local picker = require('forge.picker')
    local handle = picker.pick({
      entries = {},
      actions = {},
      picker_name = 'pr',
    })

    assert.is_table(handle)
    assert.same('pr', captured.picker_name)
    assert.same({}, warnings)
  end)
end)
