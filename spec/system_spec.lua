vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('system helpers', function()
  it('prefers stderr over stdout when extracting command errors', function()
    local system_mod = require('forge.system')

    assert.equals(
      'stderr',
      system_mod.cmd_error({
        code = 1,
        stderr = '  stderr  ',
        stdout = 'stdout',
      }, 'fallback')
    )
  end)

  it('falls back to stdout when stderr is blank', function()
    local system_mod = require('forge.system')

    assert.equals(
      'stdout',
      system_mod.cmd_error({
        code = 1,
        stderr = '   ',
        stdout = '  stdout  ',
      }, 'fallback')
    )
  end)

  it('falls back to the provided message when both streams are blank', function()
    local system_mod = require('forge.system')

    assert.equals(
      'fallback',
      system_mod.cmd_error({
        code = 1,
        stderr = '',
        stdout = '',
      }, 'fallback')
    )
  end)
end)
