vim.opt.runtimepath:prepend(vim.fn.getcwd())

local log_mod = require('forge.log')
local strip_ansi = log_mod._strip_ansi
local parse_github = log_mod._parse_github
local parse_gitlab = log_mod._parse_gitlab
local parse_summary = log_mod._parse_summary
local summary_job_at_line = log_mod._summary_job_at_line
local parse_summary_json = log_mod._parse_summary_json

local test_scope = { kind = 'github', host = 'github.com', slug = 'owner/repo' }

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

  it('detects [command] lines', function()
    local result = parse_github({
      'job\tstep\t2024-01-01T00:00:00Z [command]/usr/bin/git version',
      'job\tstep\t2024-01-01T00:00:01Z normal line',
    })
    assert.equals('command', result.lines[3].kind)
    assert.equals('    /usr/bin/git version', result.lines[3].text)
    assert.equals('content', result.lines[4].kind)
    assert.equals('    normal line', result.lines[4].text)
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
    assert.equals('3', result.lines[4].fold)
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

describe('parse_summary', function()
  it('extracts job IDs from text output', function()
    local result = parse_summary({
      '\027[32m✓\027[0m lint (ID 12345)',
      '\027[31mX\027[0m test (ID 67890)',
      '\027[32m✓\027[0m deploy (ID 11111)',
    })
    assert.equals(3, #result.lines)
    assert.equals(3, #result.job_lnums)
    assert.equals('✓ lint (ID 12345)', result.lines[1])
    assert.equals('X test (ID 67890)', result.lines[2])
    assert.equals('✓ deploy (ID 11111)', result.lines[3])
    assert.same({ id = '12345', failed = false }, result.jobs[1])
    assert.same({ id = '67890', failed = true }, result.jobs[2])
    assert.same({ id = '11111', failed = false }, result.jobs[3])
  end)

  it('handles empty output', function()
    local result = parse_summary({})
    assert.equals(0, #result.lines)
    assert.equals(0, #result.job_lnums)
  end)

  it('preserves ansi-derived job styling from native GitHub output', function()
    local result = parse_summary({
      '\027[0;32m✓\027[0m \027[0;1;39mLua Test Check\027[0m in 2m12s (ID \027[0;36m71350221923\027[0m)',
      '\027[0;33m!\027[0m warning text',
      '\027[38;5;242mLua Test Check: .github#2\027[0m',
    })
    assert.same({
      { col = 0, end_col = 3, group = 'ForgePass' },
      { col = 4, end_col = 18, group = 'ForgeLogJob' },
      { col = 32, end_col = 43, group = 'ForgeLogSection' },
    }, result.hls[1])
    assert.same({ { col = 0, end_col = 1, group = 'ForgeLogWarning' } }, result.hls[2])
    assert.same({ { col = 0, end_col = 25, group = 'ForgeLogDim' } }, result.hls[3])
  end)

  it('trims boundary blank lines but preserves internal blank separators', function()
    local result = parse_summary({
      '',
      '   ',
      'header',
      '',
      'JOBS',
      'job',
      '   ',
      'ANNOTATIONS',
      '',
      '! warning',
      '  ',
      '',
    })
    assert.same({ 'header', '', 'JOBS', 'job', '', 'ANNOTATIONS', '', '! warning' }, result.lines)
  end)

  it('maps job step lines without binding annotation lines', function()
    local result = parse_summary({
      'JOBS',
      '✓ lint (ID 12345)',
      '  ✓ Set up job',
      '  * Run stylua',
      '',
      'ANNOTATIONS',
      '! warning',
    })
    assert.same({ id = '12345', failed = false }, result.jobs[2])
    assert.same({ id = '12345', failed = false }, result.jobs[3])
    assert.same({ id = '12345', failed = false }, result.jobs[4])
    assert.is_nil(result.jobs[5])
    assert.is_nil(result.jobs[6])
    assert.is_nil(result.jobs[7])
    assert.equals(1, #result.job_lnums)
  end)

  it('maps raw line numbers to jobs when boundary blank lines are trimmed', function()
    local lines = {
      '',
      '  ',
      'JOBS',
      '✓ lint (ID 12345)',
      '  * Run stylua',
      '',
      'ANNOTATIONS',
      '! warning',
      '',
    }

    assert.is_nil(summary_job_at_line(lines, 1))
    assert.is_nil(summary_job_at_line(lines, 2))
    assert.is_nil(summary_job_at_line(lines, 3))
    assert.same({ id = '12345', failed = false }, summary_job_at_line(lines, 4))
    assert.same({ id = '12345', failed = false }, summary_job_at_line(lines, 5))
    assert.is_nil(summary_job_at_line(lines, 6))
    assert.is_nil(summary_job_at_line(lines, 7))
    assert.is_nil(summary_job_at_line(lines, 8))
    assert.is_nil(summary_job_at_line(lines, 9))
  end)
end)

describe('parse_summary_json', function()
  it('renders completed run with multiple jobs', function()
    local result = parse_summary_json({
      name = 'CI',
      status = 'completed',
      conclusion = 'success',
      jobs = {
        {
          databaseId = 100,
          name = 'lint',
          status = 'completed',
          conclusion = 'success',
          startedAt = '2024-01-01T00:00:00Z',
          completedAt = '2024-01-01T00:01:30Z',
          steps = {},
        },
        {
          databaseId = 200,
          name = 'test',
          status = 'completed',
          conclusion = 'failure',
          startedAt = '2024-01-01T00:00:00Z',
          completedAt = '2024-01-01T00:05:00Z',
          steps = {},
        },
      },
    })
    assert.equals('p  CI', result.lines[1])
    assert.truthy(result.lines[3]:match('^p  lint'))
    assert.truthy(result.lines[3]:match('%[1m 30s%]'))
    assert.truthy(result.lines[4]:match('^f  test'))
    assert.same({ id = '100', failed = false }, result.jobs[3])
    assert.same({ id = '200', failed = true }, result.jobs[4])
    assert.equals(2, #result.job_lnums)
    assert.equals('ForgePass', result.hls[1][1].group)
    assert.equals(3, result.hls[1][1].end_col)
    assert.equals('ForgePass', result.hls[3][1].group)
    assert.equals('ForgeFail', result.hls[4][1].group)
  end)

  it('shows step progress for in-progress jobs', function()
    local result = parse_summary_json({
      name = 'Build',
      status = 'in_progress',
      conclusion = '',
      jobs = {
        {
          databaseId = 300,
          name = 'compile',
          status = 'in_progress',
          conclusion = '',
          steps = {
            { name = 'Checkout', status = 'completed', conclusion = 'success', number = 1 },
            { name = 'Setup', status = 'completed', conclusion = 'success', number = 2 },
            { name = 'Build', status = 'in_progress', conclusion = '', number = 3 },
            { name = 'Test', status = 'queued', conclusion = '', number = 4 },
          },
        },
      },
    })
    assert.equals('~  Build', result.lines[1])
    assert.truthy(result.lines[3]:match('%[2/4%]'))
  end)

  it('renders header with run name and status icon', function()
    local result = parse_summary_json({
      name = 'Deploy',
      status = 'completed',
      conclusion = 'failure',
      jobs = {},
    })
    assert.equals('f  Deploy', result.lines[1])
    assert.equals(1, #result.hls[1])
    assert.equals('ForgeFail', result.hls[1][1].group)
  end)

  it('prefers displayTitle over workflow name in the summary header', function()
    local result = parse_summary_json({
      name = 'quality',
      displayTitle = 'fix(pr): use fetched metadata in edit compose (#203)',
      status = 'completed',
      conclusion = 'success',
      jobs = {},
    })
    assert.equals('p  fix(pr): use fetched metadata in edit compose (#203)', result.lines[1])
    assert.equals('ForgePass', result.hls[1][1].group)
  end)

  it('handles empty jobs list', function()
    local result = parse_summary_json({
      name = 'Empty',
      status = 'completed',
      conclusion = 'success',
      jobs = {},
    })
    assert.equals(2, #result.lines)
    assert.equals(0, #result.job_lnums)
  end)

  it('uses correct icons for queued and in_progress status', function()
    local result = parse_summary_json({
      name = 'Pipeline',
      status = 'queued',
      conclusion = '',
      jobs = {
        {
          databaseId = 400,
          name = 'waiting',
          status = 'queued',
          conclusion = '',
          steps = {},
        },
      },
    })
    assert.equals('~  Pipeline', result.lines[1])
    assert.equals('~  waiting', result.lines[3])
    assert.equals('ForgePending', result.hls[1][1].group)
    assert.equals('ForgePending', result.hls[3][1].group)
  end)
end)

describe('buffer reuse refreshes', function()
  local original_system

  before_each(function()
    original_system = vim.system
  end)

  after_each(function()
    vim.system = original_system
  end)

  local function stub_pending_system()
    local calls = {}
    vim.system = function(cmd, opts, cb)
      local proc = {
        killed = false,
        kill = function(self)
          self.killed = true
        end,
      }
      calls[#calls + 1] = {
        cmd = cmd,
        opts = opts,
        cb = cb,
        proc = proc,
      }
      return proc
    end
    return calls
  end

  it('keeps existing log lines visible while a reused log buffer refreshes', function()
    local calls = stub_pending_system()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'old log line' })

    log_mod.open({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '111',
    }, buf)

    assert.equals(1, #calls)
    assert.same({ 'old log line' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it('keeps existing summary lines visible while a reused summary buffer refreshes', function()
    local calls = stub_pending_system()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'old summary line' })

    log_mod.open_summary({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '123',
    }, buf)

    assert.equals(1, #calls)
    assert.same({ 'old summary line' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it('ignores stale reused log results after a newer refresh completes', function()
    local calls = stub_pending_system()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'old log line' })

    log_mod.open({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '111',
    }, buf)
    log_mod.open({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '111',
    }, buf)

    assert.equals(2, #calls)
    assert.is_true(calls[1].proc.killed)

    calls[2].cb({ code = 0, stdout = 'new log line' })
    vim.wait(100, function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      return lines[1] == 'new log line'
    end)

    calls[1].cb({ code = 0, stdout = 'old log line' })
    vim.wait(20)

    assert.same({ 'new log line' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it('ignores stale reused summary results after a newer refresh completes', function()
    local calls = stub_pending_system()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'old summary line' })

    log_mod.open_summary({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '123',
    }, buf)
    log_mod.open_summary({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '123',
    }, buf)

    assert.equals(2, #calls)
    assert.is_true(calls[1].proc.killed)

    calls[2].cb({ code = 0, stdout = '✓ new job (ID 2)' })
    vim.wait(100, function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      return lines[1] == '✓ new job (ID 2)'
    end)

    calls[1].cb({ code = 0, stdout = '✓ old job (ID 1)' })
    vim.wait(20)

    assert.same({ '✓ new job (ID 2)' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)

describe('summary job mappings', function()
  local original_system
  local original_open
  local original_ui_open

  before_each(function()
    original_system = vim.system
    original_open = log_mod.open
    original_ui_open = vim.ui.open
  end)

  after_each(function()
    vim.system = original_system
    log_mod.open = original_open
    vim.ui.open = original_ui_open

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^forge://') then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    vim.cmd('silent! %bwipeout!')
    vim.cmd('enew!')
  end)

  it('opens logs from job step lines but not annotation lines', function()
    local opened = {}
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = table.concat({
          '✓ lint (ID 12345)',
          '  ✓ Set up job',
          '  * Run stylua',
          '',
          'ANNOTATIONS',
          '! warning',
        }, '\n'),
      })
      return {
        kill = function() end,
      }
    end
    log_mod.open = function(cmd, opts)
      opened[#opened + 1] = { cmd = cmd, opts = opts }
    end

    log_mod.open_summary({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '12345',
      log_cmd_fn = function(job_id, failed)
        return { 'log', job_id, tostring(failed) }, { job_id = job_id }
      end,
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == '✓ lint (ID 12345)'
    end)

    local enter = vim.fn.maparg('<cr>', 'n', false, true).callback
    local win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    enter()
    vim.wait(100, function()
      return #opened == 1
    end)

    assert.same({ 'log', '12345', 'false' }, opened[1].cmd)
    assert.same({ job_id = '12345', replace_win = win }, opened[1].opts)

    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    enter()
    vim.wait(20)

    assert.equals(1, #opened)
  end)

  it('browses the job URL on job lines and the run URL elsewhere', function()
    local opened = {}
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = table.concat({
          '✓ lint (ID 12345)',
          '  ✓ Set up job',
          '',
          'ANNOTATIONS',
          '! warning',
        }, '\n'),
      })
      return {
        kill = function() end,
      }
    end
    vim.ui.open = function(url)
      opened[#opened + 1] = url
      return true
    end

    log_mod.open_summary({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '12345',
      url = 'https://example.com/runs/12345',
      browse_url_fn = function(job_id)
        return 'https://example.com/runs/12345/job/' .. job_id
      end,
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == '✓ lint (ID 12345)'
    end)

    local browse = vim.fn.maparg('gx', 'n', false, true).callback

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    browse()

    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    browse()

    assert.same({
      'https://example.com/runs/12345/job/12345',
      'https://example.com/runs/12345',
    }, opened)
  end)

  it('browses the configured URL in a job log buffer', function()
    local opened = {}
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = 'build\tstep\t2024-01-01T00:00:00Z hello',
      })
      return {
        kill = function() end,
      }
    end
    vim.ui.open = function(url)
      opened[#opened + 1] = url
      return true
    end

    log_mod.open({ 'gh', 'run', 'view', '--log', '--job', '12345' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '77',
      job_id = '12345',
      url = 'https://example.com/runs/77/job/12345',
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'build'
    end)

    local browse = vim.fn.maparg('gx', 'n', false, true).callback
    browse()

    assert.same({ 'https://example.com/runs/77/job/12345' }, opened)
  end)
end)

describe('log folds', function()
  local original_system

  before_each(function()
    original_system = vim.system
  end)

  after_each(function()
    vim.system = original_system
  end)

  it('leaves completed log folds open by default', function()
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = table.concat({
          'build\tSetup\t2024-01-01T00:00:00Z hello',
          'build\tSetup\t2024-01-01T00:00:01Z ##[group]Install',
          'build\tSetup\t2024-01-01T00:00:02Z done',
          'build\tSetup\t2024-01-01T00:00:03Z ##[endgroup]',
        }, '\n'),
      })
      return {
        kill = function() end,
      }
    end

    log_mod.open({ 'gh', 'run', 'view' }, {
      forge_name = 'github',
      scope = test_scope,
      run_id = '99',
    })

    local buf = vim.api.nvim_get_current_buf()
    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'build'
    end)

    assert.equals(99, vim.wo[0].foldlevel)
    assert.equals(-1, vim.fn.foldclosed(1))
    assert.equals(-1, vim.fn.foldclosed(2))
    assert.equals(-1, vim.fn.foldclosed(3))
  end)
end)
