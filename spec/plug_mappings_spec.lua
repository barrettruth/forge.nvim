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

  local function stub_review()
    package.preload['forge.review'] = function()
      return {
        toggle = function()
          captured.review[#captured.review + 1] = 'toggle'
        end,
        stop = function()
          captured.review[#captured.review + 1] = 'end'
        end,
        files = function()
          captured.review[#captured.review + 1] = 'files'
        end,
        next_file = function()
          captured.review[#captured.review + 1] = 'next-file'
        end,
        prev_file = function()
          captured.review[#captured.review + 1] = 'prev-file'
        end,
        next_hunk = function()
          captured.review[#captured.review + 1] = 'next-hunk'
        end,
        prev_hunk = function()
          captured.review[#captured.review + 1] = 'prev-hunk'
        end,
      }
    end
    package.loaded['forge.review'] = nil
  end

  before_each(function()
    captured = {
      calls = {},
      review = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.review'] = package.preload['forge.review'],
    }
    package.loaded['forge'] = nil
    package.loaded['forge.review'] = nil
  end)

  after_each(function()
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.review'] = old_preload['forge.review']
    package.loaded['forge'] = nil
    package.loaded['forge.review'] = nil
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

  it('defines review plugs in normal mode', function()
    stub_review()

    local toggle = mapping('<Plug>(forge-review-toggle)', 'n')
    local stop = mapping('<Plug>(forge-review-end)', 'n')
    local files = mapping('<Plug>(forge-review-files)', 'n')
    local next_file = mapping('<Plug>(forge-review-next-file)', 'n')
    local prev_file = mapping('<Plug>(forge-review-prev-file)', 'n')
    local next_hunk = mapping('<Plug>(forge-review-next-hunk)', 'n')
    local prev_hunk = mapping('<Plug>(forge-review-prev-hunk)', 'n')

    assert.is_function(toggle.callback)
    assert.is_function(stop.callback)
    assert.is_function(files.callback)
    assert.is_function(next_file.callback)
    assert.is_function(prev_file.callback)
    assert.is_function(next_hunk.callback)
    assert.is_function(prev_hunk.callback)

    toggle.callback()
    stop.callback()
    files.callback()
    next_file.callback()
    prev_file.callback()
    next_hunk.callback()
    prev_hunk.callback()

    assert.same(
      { 'toggle', 'end', 'files', 'next-file', 'prev-file', 'next-hunk', 'prev-hunk' },
      captured.review
    )
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
