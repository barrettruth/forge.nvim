vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('logger', function()
  local old_notify
  local old_schedule
  local old_in_fast_event
  local old_cmd
  local old_forge
  local notified
  local scheduled

  local function read_file(path)
    local fd = io.open(path, 'r')
    if not fd then
      return nil
    end
    local content = fd:read('*a')
    fd:close()
    return content
  end

  before_each(function()
    notified = {}
    scheduled = {}
    old_notify = vim.notify
    old_schedule = vim.schedule
    old_in_fast_event = vim.in_fast_event
    old_cmd = vim.cmd
    old_forge = vim.g.forge
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
    vim.g.forge = old_forge
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

  it('notifies debug logs when forge.debug is true', function()
    vim.g.forge = { debug = true }
    vim.in_fast_event = function()
      return false
    end

    require('forge.logger').debug('trace')

    assert.equals(0, #scheduled)
    assert.same({
      { redraw = true },
      { msg = '[forge]: trace', level = vim.log.levels.DEBUG },
    }, notified)
  end)

  it('writes debug logs to a file without notifying when forge.debug is a path', function()
    local path = vim.fn.tempname()
    vim.g.forge = { debug = path }
    vim.in_fast_event = function()
      return false
    end

    require('forge.logger').debug('trace')

    assert.same({}, notified)
    local content = read_file(path)
    os.remove(path)

    assert.is_not_nil(content)
    assert.is_not_nil(content:match('%[DEBUG%] trace\n?$'))
  end)

  it('writes info, warn, and error logs to a file while still notifying', function()
    local path = vim.fn.tempname()
    vim.g.forge = { debug = path }
    vim.in_fast_event = function()
      return false
    end

    local logger = require('forge.logger')
    logger.info('info')
    logger.warn('warn')
    logger.error('error')

    assert.same({
      { redraw = true },
      { msg = '[forge]: info', level = vim.log.levels.INFO },
      { redraw = true },
      { msg = '[forge]: warn', level = vim.log.levels.WARN },
      { redraw = true },
      { msg = '[forge]: error', level = vim.log.levels.ERROR },
    }, notified)

    local content = read_file(path)
    os.remove(path)

    assert.is_not_nil(content)
    assert.is_not_nil(content:match('%[INFO%] info\n'))
    assert.is_not_nil(content:match('%[WARN%] warn\n'))
    assert.is_not_nil(content:match('%[ERROR%] error\n'))
  end)
end)
