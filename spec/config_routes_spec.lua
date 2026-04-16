vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

local forge = require('forge')

describe('route config', function()
  after_each(function()
    vim.g.forge = nil
  end)

  it('exposes route foundation helpers from the public module', function()
    assert.is_function(forge.open)
    assert.is_function(forge.current_context)
  end)

  it('returns route foundation defaults', function()
    vim.g.forge = nil
    local cfg = forge.config()
    assert.equals('picker', cfg.client)
    assert.equals('current', cfg.context)
    assert.is_true(cfg.sections.prs)
    assert.is_true(cfg.sections.issues)
    assert.is_true(cfg.sections.ci)
    assert.is_true(cfg.sections.browse)
    assert.is_true(cfg.sections.releases)
    assert.equals('prs.open', cfg.routes.prs)
    assert.equals('issues.open', cfg.routes.issues)
    assert.equals('ci.current_branch', cfg.routes.ci)
    assert.equals('browse.contextual', cfg.routes.browse)
    assert.equals('releases.all', cfg.routes.releases)
    assert.is_true(cfg.contexts.current)
  end)

  it('deep-merges route defaults and section toggles', function()
    vim.g.forge = {
      client = 'custom',
      context = 'workspace',
      sections = {
        issues = false,
      },
      routes = {
        prs = 'prs.closed',
        browse = 'browse.branch',
      },
      contexts = {
        current = true,
        workspace = true,
      },
    }
    local cfg = forge.config()
    assert.equals('custom', cfg.client)
    assert.equals('workspace', cfg.context)
    assert.equals('prs.closed', cfg.routes.prs)
    assert.equals('browse.branch', cfg.routes.browse)
    assert.is_false(cfg.sections.issues)
    assert.is_true(cfg.sections.prs)
    assert.is_true(cfg.contexts.workspace)
  end)

  it('validates section toggles as booleans', function()
    vim.g.forge = {
      sections = {
        prs = 'yes',
      },
    }
    assert.has_error(function()
      forge.config()
    end)
  end)

  it('validates route defaults as strings', function()
    vim.g.forge = {
      routes = {
        prs = false,
      },
    }
    assert.has_error(function()
      forge.config()
    end)
  end)
end)
