vim.opt.runtimepath:prepend(vim.fn.getcwd())

local log_mod = require('forge.log')
local strip_ansi = log_mod._strip_ansi
local parse_github = log_mod._parse_github
local parse_gitlab = log_mod._parse_gitlab

describe('strip_ansi', function()
  it('strips SGR codes and extracts highlights', function()
    local text, hls = strip_ansi('\027[31mhello\027[0m world')
    assert.equals('hello world', text)
    assert.equals(1, #hls)
    assert.equals(0, hls[1].col)
    assert.equals(5, hls[1].end_col)
    assert.equals('ForgeFail', hls[1].group)
  end)

  it('strips BOM', function()
    local text = strip_ansi('\xEF\xBB\xBFhello')
    assert.equals('hello', text)
  end)

  it('strips carriage returns', function()
    local text = strip_ansi('hello\rworld')
    assert.equals('helloworld', text)
  end)

  it('handles multiple colors', function()
    local text, hls = strip_ansi('\027[32mok\027[0m \027[31mfail\027[0m')
    assert.equals('ok fail', text)
    assert.equals(2, #hls)
    assert.equals('ForgePass', hls[1].group)
    assert.equals(0, hls[1].col)
    assert.equals(2, hls[1].end_col)
    assert.equals('ForgeFail', hls[2].group)
    assert.equals(3, hls[2].col)
    assert.equals(7, hls[2].end_col)
  end)

  it('strips non-SGR escape sequences', function()
    local text = strip_ansi('\027[2Khello')
    assert.equals('hello', text)
  end)

  it('returns plain text unchanged', function()
    local text, hls = strip_ansi('plain text')
    assert.equals('plain text', text)
    assert.equals(0, #hls)
  end)

  it('handles compound SGR parameters', function()
    local text, hls = strip_ansi('\027[36;1mcyan bold\027[0m')
    assert.equals('cyan bold', text)
    assert.equals(1, #hls)
    assert.equals('ForgeLogSection', hls[1].group)
  end)

  it('handles empty input', function()
    local text, hls = strip_ansi('')
    assert.equals('', text)
    assert.equals(0, #hls)
  end)
end)

describe('parse_github', function()
  it('parses job and step headers from tab-separated lines', function()
    local result = parse_github({
      'build\tSetup\t2024-01-01T00:00:00Z hello',
      'build\tSetup\t2024-01-01T00:00:01Z world',
      'build\tRun\t2024-01-01T00:00:02Z go test',
    })
    assert.equals(6, #result.lines)
    assert.equals('build', result.lines[1].text)
    assert.equals('job', result.lines[1].kind)
    assert.equals('>1', result.lines[1].fold)
    assert.equals('  Setup', result.lines[2].text)
    assert.equals('step', result.lines[2].kind)
    assert.equals('>2', result.lines[2].fold)
    assert.equals('    hello', result.lines[3].text)
    assert.equals('content', result.lines[3].kind)
    assert.equals('2', result.lines[3].fold)
    assert.equals('  Run', result.lines[5].text)
    assert.equals('step', result.lines[5].kind)
  end)

  it('tracks headers', function()
    local result = parse_github({
      'job1\tstep1\t2024-01-01T00:00:00Z line',
      'job2\tstep2\t2024-01-01T00:00:01Z line',
    })
    assert.equals(4, #result.headers)
  end)

  it('detects error markers', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[error]something broke',
    })
    assert.equals(3, #result.lines)
    assert.equals('error', result.lines[3].kind)
    assert.equals('    Error: something broke', result.lines[3].text)
    assert.equals(1, #result.errors)
    assert.equals(3, result.errors[1])
  end)

  it('detects warning markers', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[warning]careful',
    })
    assert.equals('warning', result.lines[3].kind)
  end)

  it('detects error markers with properties', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[error file=main.go,line=5]compile error',
    })
    assert.equals('error', result.lines[3].kind)
    assert.equals('    Error: compile error', result.lines[3].text)
  end)

  it('skips endgroup lines', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[group]My Group',
      'job\tstep\t2024-01-01T00:00:01Z inside',
      'job\tstep\t2024-01-01T00:00:02Z ##[endgroup]',
    })
    assert.equals(4, #result.lines)
    assert.equals('group', result.lines[3].kind)
    assert.equals('>3', result.lines[3].fold)
  end)

  it('handles non-tab lines as raw', function()
    local result = parse_github({
      'raw line without tabs',
    })
    assert.equals(1, #result.lines)
    assert.equals('raw line without tabs', result.lines[1].text)
    assert.equals('raw', result.lines[1].kind)
    assert.equals('0', result.lines[1].fold)
  end)

  it('strips BOM from lines', function()
    local result = parse_github({
      '\xEF\xBB\xBFjob\tstep\t2024-01-01T00:00:00Z hello',
    })
    assert.equals('job', result.lines[1].text)
    assert.equals('job', result.lines[1].kind)
  end)

  it('detects debug markers', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[debug]verbose output',
    })
    assert.equals('debug', result.lines[3].kind)
    assert.equals('    verbose output', result.lines[3].text)
  end)

  it('handles multiple jobs', function()
    local result = parse_github({
      'build\tstep\t2024-01-01T00:00:00Z line1',
      'test\tstep\t2024-01-01T00:00:01Z line2',
    })
    assert.equals('build', result.lines[1].text)
    assert.equals('test', result.lines[4].text)
    assert.equals('job', result.lines[4].kind)
    assert.equals('>1', result.lines[4].fold)
  end)

  it('prepends Warning: to warning content', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z ##[warning]careful now',
    })
    assert.equals('warning', result.lines[3].kind)
    assert.equals('    Warning: careful now', result.lines[3].text)
  end)

  it('skips UNKNOWN STEP header and promotes groups', function()
    local result = parse_github({
      'job\tUNKNOWN STEP\t2024-01-01T00:00:00Z ##[group]Run cachix/install-nix',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:01Z installing...',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:02Z ##[endgroup]',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:03Z ##[group]Run nix develop',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:04Z building...',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:05Z ##[endgroup]',
    })
    assert.equals('job', result.lines[1].text)
    assert.equals('job', result.lines[1].kind)
    assert.equals('  Run cachix/install-nix', result.lines[2].text)
    assert.equals('group', result.lines[2].kind)
    assert.equals('>2', result.lines[2].fold)
    assert.equals('    installing...', result.lines[3].text)
    assert.equals('2', result.lines[3].fold)
    assert.equals('  Run nix develop', result.lines[4].text)
    assert.equals('>2', result.lines[4].fold)
    assert.equals('    building...', result.lines[5].text)
    assert.equals('2', result.lines[5].fold)
  end)

  it('uses indent 2 for content outside groups in UNKNOWN STEP', function()
    local result = parse_github({
      'job\tUNKNOWN STEP\t2024-01-01T00:00:00Z top level content',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:01Z ##[group]My Group',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:02Z inside group',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:03Z ##[endgroup]',
      'job\tUNKNOWN STEP\t2024-01-01T00:00:04Z after group',
    })
    assert.equals('  top level content', result.lines[2].text)
    assert.equals('1', result.lines[2].fold)
    assert.equals('  My Group', result.lines[3].text)
    assert.equals('>2', result.lines[3].fold)
    assert.equals('    inside group', result.lines[4].text)
    assert.equals('2', result.lines[4].fold)
    assert.equals('  after group', result.lines[5].text)
    assert.equals('1', result.lines[5].fold)
  end)

  it('does not skip real step names', function()
    local result = parse_github({
      'job\tSetup\t2024-01-01T00:00:00Z ##[group]My Group',
      'job\tSetup\t2024-01-01T00:00:01Z inside',
      'job\tSetup\t2024-01-01T00:00:02Z ##[endgroup]',
    })
    assert.equals('  Setup', result.lines[2].text)
    assert.equals('step', result.lines[2].kind)
    assert.equals('>2', result.lines[2].fold)
    assert.equals('    My Group', result.lines[3].text)
    assert.equals('>3', result.lines[3].fold)
    assert.equals('    inside', result.lines[4].text)
    assert.equals('2', result.lines[4].fold)
  end)
end)

describe('parse_gitlab', function()
  it('parses section markers', function()
    local result = parse_gitlab({
      'section_start:1705312245:prepare\027[0KPreparing',
      'running command',
      'section_end:1705312250:prepare\027[0K',
    })
    assert.equals(2, #result.lines)
    assert.equals('Preparing', result.lines[1].text)
    assert.equals('section', result.lines[1].kind)
    assert.equals('>1', result.lines[1].fold)
    assert.equals('  running command', result.lines[2].text)
    assert.equals('1', result.lines[2].fold)
  end)

  it('tracks section headers', function()
    local result = parse_gitlab({
      'section_start:100:sec1\027[0KSection One',
      'content',
      'section_end:105:sec1\027[0K',
    })
    assert.equals(1, #result.headers)
    assert.equals(1, result.headers[1])
  end)

  it('handles content outside sections', function()
    local result = parse_gitlab({
      'standalone line',
    })
    assert.equals(1, #result.lines)
    assert.equals('standalone line', result.lines[1].text)
    assert.equals('0', result.lines[1].fold)
    assert.equals('content', result.lines[1].kind)
  end)

  it('detects error lines from ANSI red', function()
    local result = parse_gitlab({
      '\027[31mError: something failed\027[0m',
    })
    assert.equals('error', result.lines[1].kind)
    assert.equals(1, #result.errors)
  end)

  it('strips ANSI from section headers', function()
    local result = parse_gitlab({
      'section_start:100:build\027[0K\027[36;1mBuilding project\027[0;m',
      'section_end:110:build\027[0K',
    })
    assert.equals('Building project', result.lines[1].text)
  end)

  it('extracts content after section_end separator', function()
    local result = parse_gitlab({
      'section_end:100:step\027[0K\027[31;1mERROR: Job failed: exit code 1\027[0;m',
    })
    assert.equals(1, #result.lines)
    assert.equals('ERROR: Job failed: exit code 1', result.lines[1].text)
    assert.equals('error', result.lines[1].kind)
  end)

  it('handles section_end + section_start on same line', function()
    local result = parse_gitlab({
      'section_end:100:step_script\027[0Ksection_start:100:cleanup\027[0K\027[36;1mCleaning up\027[0;m',
    })
    assert.equals(1, #result.lines)
    assert.equals('Cleaning up', result.lines[1].text)
    assert.equals('section', result.lines[1].kind)
  end)

  it('handles multiple sections', function()
    local result = parse_gitlab({
      'section_start:100:a\027[0KFirst',
      'line1',
      'section_end:105:a\027[0K',
      'section_start:106:b\027[0KSecond',
      'line2',
      'section_end:110:b\027[0K',
    })
    assert.equals(4, #result.lines)
    assert.equals('First', result.lines[1].text)
    assert.equals('Second', result.lines[3].text)
    assert.equals(2, #result.headers)
  end)
end)
