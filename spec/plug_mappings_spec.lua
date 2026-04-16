vim.opt.runtimepath:prepend(vim.fn.getcwd())

if not vim.api.nvim_get_commands({ builtin = false }).Forge then
  dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
end

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode, false, true)
end

local function listed_plugs(mode)
  local names = {}

  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if map.lhs:match('^<Plug>%(') and map.lhs:match('^<Plug>%(forge') then
      names[#names + 1] = map.lhs
    end
  end

  table.sort(names)
  return names
end

describe('<Plug> mappings', function()
  local captured
  local old_preload

  local exact_route_plugs = {
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
  }

  local section_plugs = {
    { '<Plug>(forge-prs)', 'prs' },
    { '<Plug>(forge-issues)', 'issues' },
    { '<Plug>(forge-ci)', 'ci' },
    { '<Plug>(forge-browse)', 'browse' },
    { '<Plug>(forge-releases)', 'releases' },
  }

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
    }

    for _, item in ipairs(exact_route_plugs) do
      expected[#expected + 1] = item
    end

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

    local expected = vim.deepcopy(section_plugs)

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

  it('exposes only root, section alias, and exact-route forge plugs', function()
    local normal_expected = { '<Plug>(forge)' }
    local visual_expected = {
      '<Plug>(forge-browse)',
      '<Plug>(forge-browse-contextual)',
    }

    for _, item in ipairs(section_plugs) do
      normal_expected[#normal_expected + 1] = item[1]
    end

    for _, item in ipairs(exact_route_plugs) do
      normal_expected[#normal_expected + 1] = item[1]
    end

    table.sort(normal_expected)
    table.sort(visual_expected)

    assert.same(normal_expected, listed_plugs('n'))
    assert.same(visual_expected, listed_plugs('x'))
  end)
end)
