vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require('forge.config')

describe('config validation', function()
  after_each(function()
    vim.g.forge = nil
  end)

  local function config_error(cfg)
    vim.g.forge = cfg
    local ok, err = pcall(config.config)
    assert.is_false(ok)
    return err
  end

  it('rejects non-table top-level config', function()
    local ok, err = pcall(function()
      vim.g.forge = 'oops'
      config.config()
    end)

    assert.is_false(ok)
    assert.matches('vim%.g%.forge', err)
  end)

  it('rejects fractional and negative numeric values', function()
    assert.matches('forge%.ci%.lines', config_error({ ci = { lines = -1 } }))
    assert.matches('forge%.ci%.refresh', config_error({ ci = { refresh = 1.5 } }))
    assert.matches(
      'forge%.display%.limits%.pulls',
      config_error({ display = { limits = { pulls = 0 } } })
    )
  end)

  it('allows zero-valued CI settings where disabled behavior is supported', function()
    vim.g.forge = {
      ci = {
        lines = 0,
        refresh = 0,
      },
    }

    local cfg = config.config()

    assert.equals(0, cfg.ci.lines)
    assert.equals(0, cfg.ci.refresh)
  end)

  it('configures unknown forge detection warnings', function()
    vim.g.forge = {
      detect = {
        unknown = 'silent',
      },
    }

    local cfg = config.config()

    assert.equals('silent', cfg.detect.unknown)
    assert.matches('forge%.detect%.unknown', config_error({ detect = { unknown = 'quiet' } }))
  end)

  it('rejects unknown route names', function()
    assert.matches(
      'forge%.routes%.prs',
      config_error({
        routes = {
          prs = 'prs.missing',
        },
      })
    )
  end)

  it('accepts GitLab route aliases as route values', function()
    vim.g.forge = {
      routes = {
        prs = 'mrs.closed',
        ci = 'pipelines.current_branch',
      },
    }

    local cfg = config.config()

    assert.equals('mrs.closed', cfg.routes.prs)
    assert.equals('pipelines.current_branch', cfg.routes.ci)
  end)

  it('rejects malformed key notation strings', function()
    assert.matches(
      'forge%.keys%.pr%.edit',
      config_error({
        keys = {
          pr = {
            edit = '<not-a-real-key>',
          },
        },
      })
    )

    assert.matches(
      'forge%.keys%.log%.refresh',
      config_error({
        keys = {
          log = {
            refresh = '<c->',
          },
        },
      })
    )
  end)

  it('accepts valid special-key notation strings', function()
    vim.g.forge = {
      keys = {
        pr = {
          edit = '<c-e>',
        },
        log = {
          filter = '<tab>',
          refresh = '<leader>r',
        },
      },
    }

    local cfg = config.config()

    assert.equals('<c-e>', cfg.keys.pr.edit)
    assert.equals('<tab>', cfg.keys.log.filter)
    assert.equals('<leader>r', cfg.keys.log.refresh)
  end)

  it('accepts a non-empty review adapter name', function()
    vim.g.forge = {
      review = {
        adapter = 'worktree',
      },
    }

    local cfg = config.config()

    assert.equals('worktree', cfg.review.adapter)
  end)

  it('rejects blank source hosts and non-list host tables', function()
    assert.matches(
      'forge%.sources%.github%.hosts',
      config_error({
        sources = {
          github = {
            hosts = {
              internal = 'git.example.com',
            },
          },
        },
      })
    )

    assert.matches(
      'forge%.sources%.github%.hosts%[%d+%]',
      config_error({
        sources = {
          github = {
            hosts = { '' },
          },
        },
      })
    )
  end)

  it('ships built-in source host aliases and merges user hosts', function()
    vim.g.forge = {
      sources = {
        forgejo = {
          hosts = { 'git.example.com' },
        },
        sourcehut = {
          hosts = { 'git.sr.ht' },
        },
      },
    }

    local cfg = config.config()

    assert.same(
      { 'codeberg.org', 'gitea.com', 'forgejo', 'gitea', 'codeberg', 'git.example.com' },
      cfg.sources.forgejo.hosts
    )
    assert.same({ 'git.sr.ht' }, cfg.sources.sourcehut.hosts)
    assert.truthy(vim.tbl_contains(cfg.sources.github.hosts, 'github'))
    assert.truthy(vim.tbl_contains(cfg.sources.gitlab.hosts, 'gitlab'))
  end)

  it('rejects invalid target aliases and default repos', function()
    assert.matches(
      'forge%.targets%.aliases%.work',
      config_error({
        targets = {
          aliases = {
            work = 'upstream',
          },
        },
      })
    )

    assert.matches(
      'forge%.targets%.default_repo',
      config_error({
        targets = {
          default_repo = 'owner/repo@bad',
        },
      })
    )
  end)

  it('accepts valid target aliases and default repos', function()
    vim.g.forge = {
      targets = {
        default_repo = 'upstream',
        aliases = {
          work = 'github.com/example/work',
          collab = 'remote:upstream',
        },
      },
    }

    local cfg = config.config()

    assert.equals('upstream', cfg.targets.default_repo)
    assert.equals('github.com/example/work', cfg.targets.aliases.work)
    assert.equals('remote:upstream', cfg.targets.aliases.collab)
  end)
end)
