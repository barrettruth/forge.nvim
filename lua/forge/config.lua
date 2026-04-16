local M = {}

---@alias forge.Split 'horizontal'|'vertical'

---@class forge.Config
---@field picker 'fzf-lua'|'auto'
---@field debug boolean|string?
---@field split forge.Split
---@field ci forge.CIConfig
---@field sources table<string, forge.SourceConfig>
---@field keys forge.KeysConfig|false
---@field display forge.DisplayConfig

---@class forge.CIConfig
---@field lines integer
---@field split forge.Split?
---@field refresh integer

---@class forge.SourceConfig
---@field hosts string[]

---@class forge.KeysConfig
---@field back string|false?
---@field pr forge.PRPickerKeys?
---@field issue forge.IssuePickerKeys?
---@field ci forge.CIPickerKeys?
---@field release forge.ReleasePickerKeys?
---@field log forge.LogViewerKeys?

---@class forge.PRPickerKeys
---@field worktree string|false
---@field ci string|false
---@field browse string|false
---@field edit string|false
---@field approve string|false
---@field merge string|false
---@field create string|false
---@field close string|false
---@field draft string|false
---@field filter string|false
---@field filter_prev string|false
---@field refresh string|false

---@class forge.IssuePickerKeys
---@field browse string|false
---@field edit string|false
---@field close string|false
---@field create string|false
---@field filter string|false
---@field filter_prev string|false
---@field refresh string|false

---@class forge.CIPickerKeys
---@field log string|false
---@field watch string|false
---@field browse string|false
---@field filter string|false
---@field filter_prev string|false
---@field failed? string|false
---@field passed? string|false
---@field running? string|false
---@field all? string|false
---@field refresh string|false

---@class forge.ReleasePickerKeys
---@field browse string|false
---@field yank string|false
---@field delete string|false
---@field filter string|false
---@field filter_prev string|false
---@field refresh string|false

---@class forge.LogViewerKeys
---@field close string|false
---@field next_step string|false
---@field prev_step string|false
---@field next_error string|false
---@field prev_error string|false
---@field browse string|false
---@field refresh string|false

---@class forge.DisplayConfig
---@field icons forge.IconsConfig
---@field widths forge.WidthsConfig
---@field limits forge.LimitsConfig

---@class forge.IconsConfig
---@field open string
---@field merged string
---@field closed string
---@field pass string
---@field fail string
---@field pending string
---@field skip string
---@field unknown string

---@class forge.WidthsConfig
---@field title integer
---@field author integer
---@field name integer
---@field branch integer

---@class forge.LimitsConfig
---@field pulls integer
---@field issues integer
---@field runs integer
---@field releases integer

---@type forge.Config
local DEFAULTS = {
  picker = 'auto',
  client = 'picker',
  context = 'current',
  debug = false,
  split = 'horizontal',
  ci = { lines = 1000, refresh = 5 },
  targets = {
    aliases = {},
  },
  sources = {},
  contexts = {
    current = true,
  },
  sections = {
    prs = true,
    issues = true,
    ci = true,
    browse = true,
    releases = true,
  },
  routes = {
    prs = 'prs.open',
    issues = 'issues.open',
    ci = 'ci.current_branch',
    browse = 'browse.contextual',
    releases = 'releases.all',
  },
  keys = {
    back = '<c-o>',
    pr = {
      worktree = '<c-w>',
      ci = '<c-t>',
      browse = '<c-x>',
      edit = '<c-e>',
      approve = '<c-y>',
      merge = '<c-g>',
      create = '<c-a>',
      close = '<c-s>',
      draft = '<c-d>',
      filter = '<tab>',
      filter_prev = false,
      refresh = '<c-r>',
    },
    issue = {
      browse = '<c-x>',
      edit = '<c-e>',
      close = '<c-s>',
      filter = '<tab>',
      filter_prev = false,
      refresh = '<c-r>',
      create = '<c-a>',
    },
    ci = {
      log = '<cr>',
      watch = '<c-w>',
      browse = '<c-x>',
      filter = '<tab>',
      filter_prev = false,
      refresh = '<c-r>',
    },
    release = {
      browse = '<cr>',
      yank = '<c-y>',
      delete = '<c-d>',
      filter = '<tab>',
      filter_prev = false,
      refresh = '<c-r>',
    },
    log = {
      close = 'q',
      next_step = ']]',
      prev_step = '[[',
      next_error = ']e',
      prev_error = '[e',
      browse = 'gx',
      refresh = '<c-r>',
    },
  },
  display = {
    icons = {
      open = 'o',
      merged = 'm',
      closed = 'c',
      pass = 'p',
      fail = 'f',
      pending = '~',
      skip = 's',
      unknown = '?',
    },
    widths = {
      title = 45,
      author = 15,
      name = 35,
      branch = 25,
    },
    limits = {
      pulls = 100,
      issues = 100,
      runs = 30,
      releases = 30,
    },
  },
}

local hl_defaults = {
  -- TODO: https://github.com/barrettruth/forge.nvim/issues/33
  -- ForgeComposeComment = 'Comment',
  ForgeComposeBranch = 'Special',
  ForgeComposeForge = 'Label',
  ForgeComposeFile = 'Directory',
  ForgeComposeAdded = 'Added',
  ForgeComposeRemoved = 'Removed',
  ForgeNumber = 'Number',
  ForgeOpen = 'DiagnosticOk',
  ForgeMerged = 'Special',
  ForgeClosed = 'Comment',
  ForgePass = 'DiagnosticOk',
  ForgeFail = 'DiagnosticError',
  ForgePending = 'DiagnosticWarn',
  ForgeSkip = 'Comment',
  ForgeBranch = 'Special',
  ForgeBranchCurrent = function()
    local hl = vim.api.nvim_get_hl(0, { name = 'Special', link = false })
    return vim.tbl_extend('force', hl, { bold = true })
  end,
  ForgeAuthor = 'Identifier',
  ForgeTime = 'Comment',
  ForgeCommitHash = 'Number',
  ForgeCommitTime = 'Comment',
  ForgeCommitAuthor = 'Identifier',
  ForgeDim = 'Comment',
  ForgeLogJob = 'Title',
  ForgeLogStep = 'Function',
  ForgeLogError = 'DiagnosticError',
  ForgeLogErrorLabel = { bold = true },
  ForgeLogWarning = 'DiagnosticWarn',
  ForgeLogWarningLabel = { bold = true },
  ForgeLogSection = 'Function',
  ForgeLogCommand = 'Special',
  ForgeLogDim = 'Comment',
}

local valid_routes = {
  ['prs.all'] = true,
  ['prs.open'] = true,
  ['prs.closed'] = true,
  ['issues.all'] = true,
  ['issues.open'] = true,
  ['issues.closed'] = true,
  ['ci.all'] = true,
  ['ci.current_branch'] = true,
  ['browse.contextual'] = true,
  ['browse.branch'] = true,
  ['browse.commit'] = true,
  ['releases.all'] = true,
  ['releases.draft'] = true,
  ['releases.prerelease'] = true,
}

local function nonempty_string(v)
  return type(v) == 'string' and vim.trim(v) ~= ''
end

local function integer_at_least(min)
  return function(v)
    return type(v) == 'number' and v >= min and v == math.floor(v)
  end
end

local function valid_route(v)
  return nonempty_string(v) and valid_routes[v] == true
end

local function valid_repo_target(v)
  if not nonempty_string(v) then
    return false
  end
  return require('forge.target').parse_repo(vim.trim(v)) ~= nil
end

local function valid_repo_alias_target(v)
  if not nonempty_string(v) then
    return false
  end
  local value = vim.trim(v)
  local remote = value:match('^remote:(.+)$')
  if remote then
    return vim.trim(remote) ~= ''
  end
  local parsed = require('forge.target').parse_repo(value)
  return parsed ~= nil and parsed.form ~= 'symbolic'
end

local function valid_key_notation(v)
  if type(v) ~= 'string' or v == '' then
    return false
  end
  local from = 1
  while true do
    local start_idx, end_idx = v:find('<[^>]+>', from)
    if not start_idx then
      return true
    end
    local token = v:sub(start_idx, end_idx)
    if token:lower() ~= '<lt>' then
      local rendered = vim.fn.keytrans(vim.keycode(token))
      if rendered:find('<lt>', 1, true) == 1 then
        return false
      end
    end
    from = end_idx + 1
  end
end

function M.setup_highlights()
  for group, val in pairs(hl_defaults) do
    if type(val) == 'string' then
      vim.api.nvim_set_hl(0, group, { default = true, link = val })
    elseif type(val) == 'function' then
      vim.api.nvim_set_hl(0, group, vim.tbl_extend('keep', { default = true }, val()))
    else
      vim.api.nvim_set_hl(0, group, vim.tbl_extend('keep', { default = true }, val))
    end
  end
end

---@return forge.Config
function M.config()
  local user = vim.g.forge or {}
  vim.validate('vim.g.forge', user, 'table')
  local cfg = vim.tbl_deep_extend('force', DEFAULTS, user)
  if user.keys == false then
    cfg.keys = false
  end

  local picker_backends = require('forge.picker').backends
  vim.validate('forge.picker', cfg.picker, function(v)
    return v == 'auto' or picker_backends[v] ~= nil
  end, "'auto' or 'fzf-lua'")
  vim.validate('forge.client', cfg.client, nonempty_string, 'non-empty string')
  vim.validate('forge.context', cfg.context, nonempty_string, 'non-empty string')
  vim.validate('forge.debug', cfg.debug, function(v)
    return v == false or v == true or nonempty_string(v)
  end, 'boolean or non-empty string')
  vim.validate('forge.sources', cfg.sources, 'table')
  vim.validate('forge.contexts', cfg.contexts, 'table')
  vim.validate('forge.sections', cfg.sections, 'table')
  vim.validate('forge.routes', cfg.routes, 'table')
  vim.validate('forge.keys', cfg.keys, function(v)
    return v == false or type(v) == 'table'
  end, 'table or false')
  vim.validate('forge.split', cfg.split, function(v)
    return v == 'horizontal' or v == 'vertical'
  end, "'horizontal' or 'vertical'")
  vim.validate('forge.display', cfg.display, 'table')
  vim.validate('forge.ci', cfg.ci, 'table')
  vim.validate('forge.ci.lines', cfg.ci.lines, integer_at_least(0), 'integer >= 0')
  vim.validate('forge.ci.refresh', cfg.ci.refresh, integer_at_least(0), 'integer >= 0')
  vim.validate('forge.targets', cfg.targets, 'table')
  if cfg.ci.split ~= nil then
    vim.validate('forge.ci.split', cfg.ci.split, function(v)
      return v == 'horizontal' or v == 'vertical'
    end, "'horizontal' or 'vertical'")
  end
  vim.validate('forge.targets.aliases', cfg.targets.aliases, 'table')
  if cfg.targets.default_repo ~= nil then
    vim.validate(
      'forge.targets.default_repo',
      cfg.targets.default_repo,
      valid_repo_target,
      'repo target'
    )
  end

  vim.validate('forge.display.icons', cfg.display.icons, 'table')
  vim.validate('forge.display.icons.open', cfg.display.icons.open, 'string')
  vim.validate('forge.display.icons.merged', cfg.display.icons.merged, 'string')
  vim.validate('forge.display.icons.closed', cfg.display.icons.closed, 'string')
  vim.validate('forge.display.icons.pass', cfg.display.icons.pass, 'string')
  vim.validate('forge.display.icons.fail', cfg.display.icons.fail, 'string')
  vim.validate('forge.display.icons.pending', cfg.display.icons.pending, 'string')
  vim.validate('forge.display.icons.skip', cfg.display.icons.skip, 'string')
  vim.validate('forge.display.icons.unknown', cfg.display.icons.unknown, 'string')

  vim.validate('forge.display.widths', cfg.display.widths, 'table')
  vim.validate(
    'forge.display.widths.title',
    cfg.display.widths.title,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.widths.author',
    cfg.display.widths.author,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.widths.name',
    cfg.display.widths.name,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.widths.branch',
    cfg.display.widths.branch,
    integer_at_least(1),
    'integer >= 1'
  )

  vim.validate('forge.display.limits', cfg.display.limits, 'table')
  vim.validate(
    'forge.display.limits.pulls',
    cfg.display.limits.pulls,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.limits.issues',
    cfg.display.limits.issues,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.limits.runs',
    cfg.display.limits.runs,
    integer_at_least(1),
    'integer >= 1'
  )
  vim.validate(
    'forge.display.limits.releases',
    cfg.display.limits.releases,
    integer_at_least(1),
    'integer >= 1'
  )

  local key_or_false = function(v)
    return v == nil or v == false or valid_key_notation(v)
  end
  if type(cfg.keys) == 'table' then
    local keys = cfg.keys --[[@as forge.KeysConfig]]
    vim.validate('forge.keys.back', keys.back, key_or_false, 'valid key string or false')
    if keys.pr ~= nil then
      vim.validate('forge.keys.pr', keys.pr, 'table')
      for _, k in ipairs({
        'worktree',
        'ci',
        'browse',
        'edit',
        'approve',
        'merge',
        'create',
        'close',
        'draft',
        'filter',
        'filter_prev',
        'refresh',
      }) do
        vim.validate('forge.keys.pr.' .. k, keys.pr[k], key_or_false, 'valid key string or false')
      end
    end
    if keys.issue ~= nil then
      vim.validate('forge.keys.issue', keys.issue, 'table')
      for _, k in ipairs({ 'browse', 'edit', 'close', 'create', 'filter', 'filter_prev', 'refresh' }) do
        vim.validate(
          'forge.keys.issue.' .. k,
          keys.issue[k],
          key_or_false,
          'valid key string or false'
        )
      end
    end
    if keys.ci ~= nil then
      vim.validate('forge.keys.ci', keys.ci, 'table')
      for _, k in ipairs({
        'log',
        'watch',
        'browse',
        'filter',
        'filter_prev',
        'failed',
        'passed',
        'running',
        'all',
        'refresh',
      }) do
        vim.validate('forge.keys.ci.' .. k, keys.ci[k], key_or_false, 'valid key string or false')
      end
    end
    if keys.release ~= nil then
      vim.validate('forge.keys.release', keys.release, 'table')
      for _, k in ipairs({ 'browse', 'yank', 'delete', 'filter', 'filter_prev', 'refresh' }) do
        vim.validate(
          'forge.keys.release.' .. k,
          keys.release[k],
          key_or_false,
          'valid key string or false'
        )
      end
    end
    if keys.log ~= nil then
      vim.validate('forge.keys.log', keys.log, 'table')
      for _, k in ipairs({
        'close',
        'next_step',
        'prev_step',
        'next_error',
        'prev_error',
        'browse',
        'refresh',
      }) do
        vim.validate('forge.keys.log.' .. k, keys.log[k], key_or_false, 'valid key string or false')
      end
    end
  end

  for name, source in pairs(cfg.sources) do
    vim.validate('forge.sources key', name, nonempty_string, 'non-empty string')
    vim.validate('forge.sources.' .. name, source, 'table')
    if source.hosts ~= nil then
      vim.validate('forge.sources.' .. name .. '.hosts', source.hosts, vim.islist, 'list')
      for i, host in ipairs(source.hosts) do
        vim.validate(
          'forge.sources.' .. name .. '.hosts[' .. i .. ']',
          host,
          nonempty_string,
          'non-empty string'
        )
      end
    end
  end

  for name, target in pairs(cfg.targets.aliases) do
    vim.validate('forge.targets.aliases key', name, nonempty_string, 'non-empty string')
    vim.validate(
      'forge.targets.aliases.' .. name,
      target,
      valid_repo_alias_target,
      'repo address or remote:<name>'
    )
  end

  for name, enabled in pairs(cfg.contexts) do
    vim.validate('forge.contexts key', name, nonempty_string, 'non-empty string')
    vim.validate('forge.contexts.' .. name, enabled, 'boolean')
  end

  for name, enabled in pairs(cfg.sections) do
    vim.validate('forge.sections key', name, nonempty_string, 'non-empty string')
    vim.validate('forge.sections.' .. name, enabled, 'boolean')
  end

  for name, route in pairs(cfg.routes) do
    vim.validate('forge.routes key', name, nonempty_string, 'non-empty string')
    vim.validate('forge.routes.' .. name, route, valid_route, 'known route')
  end

  return cfg
end

M.setup_highlights()

return M
