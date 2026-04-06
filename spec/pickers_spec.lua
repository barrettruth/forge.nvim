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

  it('uses more as the visible PR submenu label while keeping it on <c-e> by default', function()
    local cfg = require('forge.config').config()
    assert.equals('<c-e>', cfg.keys.pr.manage)
    assert.is_nil(cfg.keys.pr.edit)
    assert.is_nil(cfg.keys.pr.close)
    assert.equals('<c-o>', cfg.keys.ci.filter)

    local pickers = require('forge.pickers')
    pickers.pr('open', fake_forge())

    assert.is_not_nil(captured)
    local labels = {}
    for _, def in ipairs(captured.actions) do
      labels[def.name] = def.label
    end
    assert.equals('more', labels.manage)
    assert.is_nil(labels.worktree)
    assert.is_nil(labels.create)
    assert.is_nil(labels.filter)
    assert.is_nil(labels.refresh)
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
end)
