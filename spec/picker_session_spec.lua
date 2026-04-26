vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('picker session', function()
  local captured
  local old_system
  local old_schedule
  local old_preload

  before_each(function()
    captured = {
      systems = {},
      callbacks = {},
      picker = nil,
    }

    old_system = vim.system
    old_schedule = vim.schedule
    old_preload = {
      ['forge.picker'] = package.preload['forge.picker'],
    }

    vim.schedule = function(fn)
      fn()
    end

    vim.system = function(cmd, _, cb)
      table.insert(captured.systems, cmd)
      table.insert(captured.callbacks, cb)
      return {
        wait = function()
          return { code = 0, stdout = '[]' }
        end,
      }
    end

    package.preload['forge.picker'] = function()
      return {
        pick = function(opts)
          captured.picker = opts
        end,
      }
    end

    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.session'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.schedule = old_schedule

    package.preload['forge.picker'] = old_preload['forge.picker']

    package.loaded['forge.picker'] = nil
    package.loaded['forge.picker.session'] = nil
  end)

  it('decodes successful json results', function()
    local session = require('forge.picker.session')
    local ok, data, failure = session.decode_json({
      code = 0,
      stdout = '[{"id":1}]',
    })

    assert.is_true(ok)
    assert.same({ { id = 1 } }, data)
    assert.is_nil(failure)
  end)

  it('returns command failure details for failed json results', function()
    local session = require('forge.picker.session')

    local ok_failed, data_failed, failure_failed = session.decode_json({
      code = 1,
      stdout = '[{"id":1}]',
      stderr = 'boom',
    })

    assert.is_false(ok_failed)
    assert.is_nil(data_failed)
    assert.same('command', failure_failed.kind)
    assert.equals('boom', failure_failed.message)
    assert.same({
      code = 1,
      stdout = '[{"id":1}]',
      stderr = 'boom',
    }, failure_failed.result)
  end)

  it('returns decode failure details for invalid json results', function()
    local session = require('forge.picker.session')

    local ok_invalid, data_invalid, failure_invalid = session.decode_json({
      code = 0,
      stdout = '{',
    })

    assert.is_false(ok_invalid)
    assert.is_nil(data_invalid)
    assert.same('decode', failure_invalid.kind)
    assert.equals(failure_invalid.decode_error, failure_invalid.message)
    assert.is_true(
      type(failure_invalid.decode_error) == 'string' and failure_invalid.decode_error ~= ''
    )
  end)

  it('prefetches json and forwards successful data once', function()
    local session = require('forge.picker.session')
    local success
    local failures = 0

    local started = session.prefetch_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      on_success = function(data)
        success = data
      end,
      on_failure = function()
        failures = failures + 1
      end,
    })

    assert.is_true(started)
    assert.same({ 'prs', 'open' }, captured.systems[1])

    captured.callbacks[1]({
      code = 0,
      stdout = '[{"number":42}]',
      stderr = '',
    })

    assert.same({ { number = 42 } }, success)
    assert.equals(0, failures)
    assert.is_false(session.inflight('prs.open'))
  end)

  it('forwards structured failures through request_json', function()
    local session = require('forge.picker.session')
    local captured_failure
    local stale_state

    session.request_json('prs.open', { 'prs', 'open' }, function(ok, data, failure, stale)
      assert.is_false(ok)
      assert.is_nil(data)
      captured_failure = failure
      stale_state = stale
    end)

    captured.callbacks[1]({
      code = 0,
      stdout = '{',
      stderr = '',
    })

    assert.is_false(stale_state)
    assert.same('decode', captured_failure.kind)
    assert.is_true(
      type(captured_failure.decode_error) == 'string' and captured_failure.decode_error ~= ''
    )
  end)

  it('skips prefetch when skip_if passes or the key is already inflight', function()
    local session = require('forge.picker.session')

    local skipped = session.prefetch_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      skip_if = function()
        return true
      end,
    })

    local started = session.prefetch_json({
      key = 'issues.open',
      cmd = { 'issues', 'open' },
    })
    local blocked = session.prefetch_json({
      key = 'issues.open',
      cmd = { 'issues', 'open' },
    })

    assert.is_false(skipped)
    assert.is_true(started)
    assert.is_true(session.inflight('issues.open'))
    assert.is_false(blocked)
    assert.equals(1, #captured.systems)
  end)

  it('ignores stale prefetch responses after invalidation', function()
    local session = require('forge.picker.session')
    local success = 0
    local failure = 0

    assert.is_true(session.prefetch_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      on_success = function()
        success = success + 1
      end,
      on_failure = function()
        failure = failure + 1
      end,
    }))

    session.invalidate('prs.open')
    captured.callbacks[1]({
      code = 0,
      stdout = '[{"number":42}]',
      stderr = '',
    })

    assert.equals(0, success)
    assert.equals(0, failure)
    assert.is_false(session.inflight('prs.open'))
  end)

  it('forwards structured failures to prefetch failure handlers', function()
    local session = require('forge.picker.session')
    local failure

    assert.is_true(session.prefetch_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      on_failure = function(err)
        failure = err
      end,
    }))

    captured.callbacks[1]({
      code = 1,
      stdout = '',
      stderr = 'boom',
    })

    assert.same('command', failure.kind)
    assert.equals('boom', failure.message)
  end)

  it('opens cached data immediately without requesting json', function()
    local session = require('forge.picker.session')
    local opened

    session.pick_json({
      key = 'prs.open',
      cached = { { number = 42 } },
      open = function(data)
        opened = data
      end,
    })

    assert.same({ { number = 42 } }, opened)
    assert.equals(0, #captured.systems)
  end)

  it('streams json into the fzf picker and emits built entries', function()
    local session = require('forge.picker.session')
    local emitted = {}
    local opened = 0
    local fetched = 0

    session.pick_json({
      key = 'prs.open',
      cmd = function()
        return { 'prs', 'open' }
      end,
      loading_prompt = function()
        return 'PRs> '
      end,
      actions = {
        { name = 'default', fn = function() end },
      },
      picker_name = 'pr',
      build_entries = function(data)
        return {
          { display = { { '#' .. data[1].number } }, value = data[1].number },
        }
      end,
      open = function()
        opened = opened + 1
      end,
      on_fetch = function()
        fetched = fetched + 1
      end,
    })

    assert.is_not_nil(captured.picker)
    assert.equals('PRs> ', captured.picker.prompt)
    assert.equals('pr', captured.picker.picker_name)
    assert.equals(0, fetched)
    assert.equals(0, opened)

    captured.picker.stream(function(entry)
      table.insert(emitted, entry)
    end)
    assert.equals(1, fetched)

    captured.callbacks[1]({
      code = 0,
      stdout = '[{"number":42}]',
      stderr = '',
    })

    assert.same({
      { display = { { '#42' } }, value = 42 },
      vim.NIL,
    }, {
      emitted[1],
      emitted[2] == nil and vim.NIL or emitted[2],
    })
  end)

  it('emits an error entry for streamed failures', function()
    local session = require('forge.picker.session')
    local emitted = {}

    session.pick_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      picker_name = 'pr',
      actions = {},
      build_entries = function()
        return {}
      end,
      error_entry = function(failure)
        return { display = { { session.failure_message(failure, 'fallback') } }, value = false }
      end,
      open = function() end,
    })

    captured.picker.stream(function(entry)
      table.insert(emitted, entry)
    end)
    captured.callbacks[1]({
      code = 1,
      stdout = '',
      stderr = 'boom',
    })

    assert.same({
      { display = { { 'boom' } }, value = false },
      vim.NIL,
    }, {
      emitted[1],
      emitted[2] == nil and vim.NIL or emitted[2],
    })
  end)

  it('emits only a terminator for stale streamed requests', function()
    local session = require('forge.picker.session')
    local emitted = {}

    session.pick_json({
      key = 'prs.open',
      cmd = { 'prs', 'open' },
      picker_name = 'pr',
      actions = {},
      build_entries = function()
        return {}
      end,
      open = function() end,
    })

    captured.picker.stream(function(entry)
      table.insert(emitted, entry)
    end)
    session.invalidate('prs.open')
    captured.callbacks[1]({
      code = 0,
      stdout = '[{"number":42}]',
      stderr = '',
    })

    assert.same({ vim.NIL }, {
      emitted[1] == nil and vim.NIL or emitted[1],
    })
  end)
end)
