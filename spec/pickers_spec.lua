vim.opt.runtimepath:prepend(vim.fn.getcwd())

local captured
local cache

local function fake_forge()
  return {
    labels = { pr = 'PRs', pr_one = 'PR' },
    kinds = { pr = 'pull_request' },
    pr_fields = {
      number = 'number',
      title = 'title',
      state = 'state',
      author = 'author',
      created_at = 'created_at',
    },
    repo_info = function()
      return {
        permission = 'WRITE',
        merge_methods = { 'merge' },
      }
    end,
    pr_state = function()
      return {
        state = 'OPEN',
        is_draft = false,
      }
    end,
    approve_cmd = function(_, num)
      return { 'approve', num }
    end,
    merge_cmd = function(_, num, method)
      return { 'merge', num, method }
    end,
    close_cmd = function(_, num)
      return { 'close', num }
    end,
    reopen_cmd = function(_, num)
      return { 'reopen', num }
    end,
    draft_toggle_cmd = function(_, num)
      return { 'draft', num }
    end,
  }
end

local function fake_issue_forge()
  return {
    labels = { issue = 'Issues' },
    kinds = { issue = 'issue' },
    issue_fields = {
      number = 'number',
      title = 'title',
      state = 'state',
      author = 'author',
      created_at = 'created_at',
    },
    view_web = function() end,
    close_issue_cmd = function(_, num)
      return { 'close', num }
    end,
    reopen_issue_cmd = function(_, num)
      return { 'reopen', num }
    end,
  }
end

local function fake_ci_forge()
  return {
    labels = { ci = 'CI', pr_one = 'PR' },
    check_log_cmd = function(_, run_id)
      return { 'log', run_id }
    end,
    list_runs_json_cmd = function(_, branch)
      return { 'runs', branch or '' }
    end,
    normalize_run = function(_, run)
      return run
    end,
  }
end

local function fake_release_forge()
  return {
    release_fields = {
      tag = 'tag',
      title = 'title',
      is_draft = 'is_draft',
      is_prerelease = 'is_prerelease',
    },
    browse_release = function() end,
    delete_release_cmd = function(_, tag)
      return { 'delete', tag }
    end,
    list_releases_json_cmd = function()
      return { 'releases' }
    end,
  }
end

local function action_by_name(name)
  for _, def in ipairs(captured.actions) do
    if def.name == name then
      return def
    end
  end
end

describe('pickers', function()
  local old_preload

  before_each(function()
    captured = nil
    cache = {
      ['pr:open'] = {
        { number = 42, title = 'Fix api drift', state = 'OPEN', author = 'alice', created_at = '' },
      },
    }
    old_preload = {
      ['fzf-lua.utils'] = package.preload['fzf-lua.utils'],
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.picker'] = package.preload['forge.picker'],
    }
    package.preload['fzf-lua.utils'] = function()
      return {
        ansi_from_hl = function(_, text)
          return text
        end,
      }
    end
    package.preload['forge.logger'] = function()
      return {
        info = function() end,
        error = function() end,
        debug = function() end,
        warn = function() end,
      }
    end
    package.preload['forge.picker'] = function()
      return {
        backends = { ['fzf-lua'] = 'forge.picker.fzf' },
        pick = function(opts)
          captured = opts
        end,
      }
    end
    package.preload['forge'] = function()
      return {
        config = require('forge.config').config,
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          return cache[key]
        end,
        set_list = function(key, value)
          cache[key] = value
        end,
        clear_list = function(key)
          if key then
            cache[key] = nil
          end
        end,
        format_pr = function(pr)
          return {
            { '#' .. tostring(pr.number) },
            { ' ' .. (pr.title or '') },
          }
        end,
        format_issue = function(issue)
          return {
            { '#' .. tostring(issue.number) },
            { ' ' .. (issue.title or '') },
          }
        end,
        format_check = function(check)
          return {
            { check.name or '' },
          }
        end,
        filter_checks = function(checks)
          return checks
        end,
        format_run = function(run)
          return {
            { run.name or '' },
          }
        end,
        filter_runs = function(runs)
          return runs
        end,
        format_release = function(rel)
          return {
            { tostring(rel.tag or '') },
            { ' ' .. (rel.title or '') },
          }
        end,
        remote_web_url = function()
          return 'https://example.com/repo'
        end,
        repo_info = function(f)
          return f:repo_info()
        end,
        create_pr = function() end,
        edit_pr = function() end,
      }
    end
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
    vim.g.forge = nil
  end)

  after_each(function()
    package.preload['fzf-lua.utils'] = old_preload['fzf-lua.utils']
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.picker'] = old_preload['forge.picker']
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
  end)

  it('uses more as the default PR action without a separate default key binding', function()
    local cfg = require('forge.config').config()
    assert.is_nil(cfg.keys.pr.checkout)
    assert.is_nil(cfg.keys.pr.manage)
    assert.is_nil(cfg.keys.pr.edit)
    assert.is_nil(cfg.keys.pr.close)
    assert.equals('<c-o>', cfg.keys.ci.filter)

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('PRs (open · 1)> ', captured.prompt)
    local labels = {}
    for _, def in ipairs(captured.actions) do
      labels[def.name] = def.label
    end
    assert.equals('more', labels.default)
    assert.equals('more', labels.manage)
    assert.is_nil(labels.worktree)
    assert.is_nil(labels.create)
    assert.is_nil(labels.filter)
    assert.is_nil(labels.refresh)
  end)

  it('keeps auxiliary PR actions open', function()
    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('more', action_by_name('default').label)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_false(rawget(action_by_name('worktree'), 'close'))
    assert.is_nil(rawget(action_by_name('checkout'), 'close'))
    assert.is_nil(rawget(action_by_name('manage'), 'close'))
  end)

  it('shows edit inside the more picker', function()
    local pickers = require('forge.pickers')
    pickers.pr_manage(fake_forge(), '42')

    assert.is_not_nil(captured)
    assert.equals('PR #42 More> ', captured.prompt)
    assert.equals('_menu', captured.picker_name)

    local labels = {}
    for _, entry in ipairs(captured.entries) do
      labels[#labels + 1] = entry.display[1][1]
    end
    assert.same({ 'Edit', 'Approve', 'Merge (merge)', 'Close', 'Mark as draft' }, labels)
  end)

  it('shows an explicit empty PR row instead of a blank picker', function()
    cache['pr:open'] = {}

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    assert.equals('PRs (open · 0)> ', captured.prompt)
    assert.equals('No open PRs', captured.entries[1].display[1][1])
    assert.is_true(captured.entries[1].placeholder)
  end)

  it('keeps issue web actions open', function()
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }

    local pickers = require('forge.pickers')
    pickers.issue('all', fake_issue_forge())

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('default'), 'close'))
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('close'), 'close'))
  end)

  it('keeps the issue header affordance on the default open action only', function()
    package.loaded['forge'] = nil
    package.loaded['forge.config'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.picker'] = nil
    package.loaded['forge.pickers'] = nil
    cache['issue:all'] = {
      { number = 7, title = 'Bug', state = 'OPEN', author = 'alice', created_at = '' },
    }
    package.preload['forge'] = function()
      return {
        config = require('forge.config').config,
        list_key = function(kind, state)
          return kind .. ':' .. state
        end,
        get_list = function(key)
          return cache[key]
        end,
        set_list = function(key, value)
          cache[key] = value
        end,
        clear_list = function(key)
          if key then
            cache[key] = nil
          end
        end,
        format_issue = function(issue)
          return {
            { '#' .. tostring(issue.number) },
            { ' ' .. (issue.title or '') },
          }
        end,
        create_issue = function() end,
      }
    end

    local pickers = require('forge.pickers')
    pickers.issue('all', {
      labels = { issue = 'Issues' },
      kinds = { issue = 'issue' },
      issue_fields = {
        number = 'number',
        title = 'title',
        state = 'state',
        author = 'author',
        created_at = 'created_at',
      },
      view_web = function() end,
      close_issue_cmd = function(_, num)
        return { 'close', num }
      end,
      reopen_issue_cmd = function(_, num)
        return { 'reopen', num }
      end,
    })

    assert.is_not_nil(captured)
    local labels = {}
    for _, def in ipairs(captured.actions) do
      labels[def.name] = def.label
    end
    assert.equals('open', labels.default)
    assert.is_nil(labels.browse)
    assert.equals('toggle', labels.close)
    assert.is_nil(labels.create)
    assert.is_nil(labels.filter)
    assert.is_nil(labels.refresh)
  end)

  it('keeps check and CI web actions open', function()
    local pickers = require('forge.pickers')
    pickers.checks(fake_ci_forge(), '42', 'all', {
      { name = 'lint', link = 'https://example.com/check', bucket = 'pass' },
    })

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))

    local old_system = vim.system
    vim.system = function(_, _, cb)
      cb({
        code = 0,
        stdout = vim.json.encode({
          {
            id = '1',
            name = 'CI',
            branch = 'main',
            status = 'success',
            url = 'https://example.com',
          },
        }),
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    pickers.ci(fake_ci_forge(), 'main', 'all')
    vim.wait(100, function()
      return captured and captured.prompt == 'CI (main, all · 1)> '
    end)
    vim.system = old_system

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_nil(rawget(action_by_name('log'), 'close'))
    assert.is_nil(rawget(action_by_name('watch'), 'close'))
  end)

  it('keeps release browse and copy actions open', function()
    cache['release:all'] = {
      { tag = 'v1.0.0', title = 'First', is_draft = false, is_prerelease = false },
    }

    local pickers = require('forge.pickers')
    pickers.release('all', fake_release_forge())

    assert.is_not_nil(captured)
    assert.is_false(rawget(action_by_name('browse'), 'close'))
    assert.is_false(rawget(action_by_name('yank'), 'close'))
    assert.is_nil(rawget(action_by_name('delete'), 'close'))
  end)
end)
