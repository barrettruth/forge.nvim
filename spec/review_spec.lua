vim.opt.runtimepath:prepend(vim.fn.getcwd())

local helpers = dofile(vim.fn.getcwd() .. '/spec/helpers.lua')

describe('review adapters', function()
  local captured
  local old_preload
  local old_system
  local old_exists
  local old_nvim_cmd
  local old_schedule

  before_each(function()
    captured = {
      calls = {},
      cmds = {},
      infos = {},
      errors = {},
    }
    old_preload = helpers.capture_preload({ 'forge', 'forge.logger' })
    old_system = vim.system
    old_exists = vim.fn.exists
    old_nvim_cmd = vim.api.nvim_cmd
    old_schedule = vim.schedule

    vim.system = helpers.system_router({
      default = helpers.command_result('', 1),
      calls = captured.calls,
      responses = {
        ['details 42'] = helpers.command_result('{}'),
        ['git fetch origin +pull/42/head:refs/forge/review/github/github.com/owner/current/pr/42'] = helpers.command_result(
          ''
        ),
      },
    })
    vim.fn.exists = function(name)
      if name == ':DiffviewOpen' then
        return 2
      end
      return old_exists(name)
    end
    vim.api.nvim_cmd = function(cmd, opts)
      table.insert(captured.cmds, { cmd = cmd, opts = opts })
    end
    vim.schedule = function(fn)
      fn()
    end

    package.preload['forge'] = function()
      return {
        config = function()
          return { review = { adapter = 'checkout' } }
        end,
        remote_ref = function(_, branch)
          return 'origin/' .. branch
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
        warn = function() end,
        debug = function() end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.review'] = nil
  end)

  after_each(function()
    vim.system = old_system
    vim.fn.exists = old_exists
    vim.api.nvim_cmd = old_nvim_cmd
    vim.schedule = old_schedule

    helpers.restore_preload(old_preload)

    package.loaded['forge'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.review'] = nil
  end)

  it('lists diffview among built-in review adapters', function()
    local review = require('forge.review')

    assert.is_true(vim.tbl_contains(review.names(), 'diffview'))
  end)

  it('opens diffview review against fetched PR refs', function()
    local review = require('forge.review')
    local scope = {
      kind = 'github',
      host = 'github.com',
      slug = 'owner/current',
    }

    review.open({
      labels = { pr_one = 'PR' },
      fetch_pr = function(_, num, ref)
        assert.equals('42', num)
        assert.same(scope, ref)
        return { 'git', 'fetch', 'origin', 'pull/42/head:pr-42' }
      end,
      fetch_pr_details_cmd = function(_, num, ref)
        assert.equals('42', num)
        assert.same(scope, ref)
        return { 'details', num }
      end,
      parse_pr_details = function()
        return { base_branch = 'main' }
      end,
    }, { num = '42', scope = scope }, { adapter = 'diffview' })

    assert.same({
      'details 42',
      'git fetch origin +pull/42/head:refs/forge/review/github/github.com/owner/current/pr/42',
    }, captured.calls)
    assert.same({
      {
        cmd = {
          cmd = 'DiffviewOpen',
          args = { 'origin/main...refs/forge/review/github/github.com/owner/current/pr/42' },
        },
        opts = {},
      },
    }, captured.cmds)
    assert.same({ 'opening PR #42 in diffview...' }, captured.infos)
    assert.same({}, captured.errors)
  end)

  it('reports missing diffview.nvim before loading review details', function()
    vim.fn.exists = function(name)
      if name == ':DiffviewOpen' then
        return 0
      end
      return old_exists(name)
    end
    package.loaded['forge.review'] = nil

    local review = require('forge.review')

    review.open({
      labels = { pr_one = 'PR' },
      fetch_pr = function()
        error('should not fetch')
      end,
      fetch_pr_details_cmd = function()
        error('should not load details')
      end,
      parse_pr_details = function()
        return {}
      end,
    }, { num = '42' }, { adapter = 'diffview' })

    assert.same({}, captured.calls)
    assert.same({}, captured.cmds)
    assert.same({ 'diffview.nvim not found' }, captured.errors)
  end)
end)
