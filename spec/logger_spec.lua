vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('logger', function()
  local old_notify
  local old_schedule
  local old_in_fast_event
  local old_cmd
  local notified
  local scheduled

  before_each(function()
    notified = {}
    scheduled = {}
    old_notify = vim.notify
    old_schedule = vim.schedule
    old_in_fast_event = vim.in_fast_event
    old_cmd = vim.cmd
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    vim.schedule = function(fn)
      scheduled[#scheduled + 1] = fn
    end
    vim.cmd = setmetatable({
      redraw = function()
        notified[#notified + 1] = { redraw = true }
      end,
    }, {
      __call = function(_, ...)
        return old_cmd(...)
      end,
    })
    package.loaded['forge.logger'] = nil
  end)

  after_each(function()
    vim.notify = old_notify
    vim.schedule = old_schedule
    vim.in_fast_event = old_in_fast_event
    vim.cmd = old_cmd
    package.loaded['forge.logger'] = nil
  end)

  it('schedules notifications when called in a fast event', function()
    vim.in_fast_event = function()
      return true
    end

    require('forge.logger').info('fast')

    assert.equals(1, #scheduled)
    assert.same({}, notified)

    scheduled[1]()

    assert.same({
      { redraw = true },
      { msg = '[forge]: fast', level = vim.log.levels.INFO },
    }, notified)
  end)

  it('notifies immediately outside fast events', function()
    vim.in_fast_event = function()
      return false
    end

    require('forge.logger').warn('slow')

    assert.equals(0, #scheduled)
    assert.same({
      { redraw = true },
      { msg = '[forge]: slow', level = vim.log.levels.WARN },
    }, notified)
  end)
end)
