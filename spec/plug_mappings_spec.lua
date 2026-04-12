vim.opt.runtimepath:prepend(vim.fn.getcwd())

if not vim.api.nvim_get_commands({ builtin = false }).Forge then
  dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
end

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode, false, true)
end

describe('<Plug> mappings', function()
  local captured
  local old_preload

  local function stub_forge()
    package.preload['forge'] = function()
      return {
        open = function(name)
          captured.calls[#captured.calls + 1] = {
            name = name == nil and vim.NIL or name,
            mode = vim.fn.mode(),
            line_v = vim.fn.line('v'),
            line = vim.fn.line('.'),
          }
        end,
      }
    end
    package.loaded['forge'] = nil
  end

  before_each(function()
    captured = {
      calls = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
    }
    package.loaded['forge'] = nil
  end)

  after_each(function()
    package.preload['forge'] = old_preload['forge']
    package.loaded['forge'] = nil
    vim.cmd('enew!')
  end)

  it('defines the root and exact route plugs in normal mode', function()
    stub_forge()

    local expected = {
      { '<Plug>(forge)', vim.NIL },
      { '<Plug>(forge-prs-open)', 'prs.open' },
      { '<Plug>(forge-prs-closed)', 'prs.closed' },
      { '<Plug>(forge-prs-all)', 'prs.all' },
      { '<Plug>(forge-issues-open)', 'issues.open' },
      { '<Plug>(forge-issues-closed)', 'issues.closed' },
      { '<Plug>(forge-issues-all)', 'issues.all' },
      { '<Plug>(forge-ci-current-branch)', 'ci.current_branch' },
      { '<Plug>(forge-ci-all)', 'ci.all' },
      { '<Plug>(forge-browse-contextual)', 'browse.contextual' },
      { '<Plug>(forge-browse-branch)', 'browse.branch' },
      { '<Plug>(forge-browse-commit)', 'browse.commit' },
      { '<Plug>(forge-releases-all)', 'releases.all' },
      { '<Plug>(forge-releases-draft)', 'releases.draft' },
      { '<Plug>(forge-releases-prerelease)', 'releases.prerelease' },
      { '<Plug>(forge-branches-local)', 'branches.local' },
      { '<Plug>(forge-commits-current-branch)', 'commits.current_branch' },
      { '<Plug>(forge-worktrees-list)', 'worktrees.list' },
    }

    for _, item in ipairs(expected) do
      local map = mapping(item[1], 'n')
      assert.equals(item[1], map.lhs)
      assert.is_function(map.callback)
      map.callback()
    end

    for i, item in ipairs(expected) do
      assert.same(item[2], captured.calls[i].name)
    end
  end)

  it('defines section alias plugs in normal mode', function()
    stub_forge()

    local expected = {
      { '<Plug>(forge-prs)', 'prs' },
      { '<Plug>(forge-issues)', 'issues' },
      { '<Plug>(forge-ci)', 'ci' },
      { '<Plug>(forge-browse)', 'browse' },
      { '<Plug>(forge-releases)', 'releases' },
      { '<Plug>(forge-branches)', 'branches' },
      { '<Plug>(forge-commits)', 'commits' },
      { '<Plug>(forge-worktrees)', 'worktrees' },
    }

    for _, item in ipairs(expected) do
      local map = mapping(item[1], 'n')
      assert.equals(item[1], map.lhs)
      assert.is_function(map.callback)
      map.callback()
    end

    for i, item in ipairs(expected) do
      assert.same(item[2], captured.calls[i].name)
    end
  end)

  it('runs contextual browse plugs while visual mode is active', function()
    stub_forge()

    vim.cmd('new')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.cmd('normal! ggVj')

    local contextual = mapping('<Plug>(forge-browse-contextual)', 'x')
    local alias = mapping('<Plug>(forge-browse)', 'x')

    assert.is_function(contextual.callback)
    assert.is_function(alias.callback)

    contextual.callback()
    alias.callback()

    assert.same('browse.contextual', captured.calls[1].name)
    assert.equals('V', captured.calls[1].mode)
    assert.equals(1, captured.calls[1].line_v)
    assert.equals(2, captured.calls[1].line)

    assert.same('browse', captured.calls[2].name)
    assert.equals('V', captured.calls[2].mode)
    assert.equals(1, captured.calls[2].line_v)
    assert.equals(2, captured.calls[2].line)
  end)
end)
