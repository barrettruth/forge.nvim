local M = {}

---@alias forge.Split 'horizontal'|'vertical'

---@class forge.Config
---@field picker 'fzf-lua'|'telescope'|'snacks'|'auto'
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
---@field pr forge.PRPickerKeys?
---@field issue forge.IssuePickerKeys?
---@field ci forge.CIPickerKeys?
---@field release forge.ReleasePickerKeys?
---@field log forge.LogViewerKeys?

---@class forge.PRPickerKeys
---@field checkout string|false
---@field diff string|false
---@field worktree string|false
---@field ci string|false
---@field browse string|false
---@field manage string|false
---@field create string|false
---@field filter string|false
---@field refresh string|false

---@class forge.IssuePickerKeys
---@field browse string|false
---@field close string|false
---@field create string|false
---@field filter string|false
---@field refresh string|false

---@class forge.CIPickerKeys
---@field log string|false
---@field watch string|false
---@field browse string|false
---@field failed string|false
---@field passed string|false
---@field running string|false
---@field all string|false
---@field refresh string|false

---@class forge.ReleasePickerKeys
---@field browse string|false
---@field yank string|false
---@field delete string|false
---@field filter string|false
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
  debug = false,
  split = 'horizontal',
  ci = { lines = 1000, refresh = 5 },
  sources = {},
  keys = {
    pr = {
      checkout = '<cr>',
      diff = '<c-d>',
      worktree = '<c-w>',
      ci = '<c-t>',
      browse = '<c-x>',
      manage = '<c-e>',
      create = '<c-a>',
      filter = '<c-o>',
      refresh = '<c-r>',
    },
    issue = {
      browse = '<cr>',
      close = '<c-s>',
      filter = '<c-o>',
      refresh = '<c-r>',
      create = '<c-a>',
    },
    ci = {
      log = '<cr>',
      watch = '<c-w>',
      browse = '<c-x>',
      failed = '<c-f>',
      passed = '<c-p>',
      running = '<c-n>',
      all = '<c-a>',
      refresh = '<c-r>',
    },
    release = {
      browse = '<cr>',
      yank = '<c-y>',
      delete = '<c-d>',
      filter = '<c-o>',
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
      open = '+',
      merged = 'm',
      closed = 'x',
      pass = '*',
      fail = 'x',
      pending = '~',
      skip = '-',
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

---@type table<string, forge.Forge>
local sources = {}

---@param name string
---@param source forge.Forge
function M.register(name, source)
  sources[name] = source
end

---@return table<string, forge.Forge>
function M.registered_sources()
  return sources
end

local hl_defaults = {
  ForgeComposeComment = { italic = true },
  ForgeComposeBranch = 'Special',
  ForgeComposeForge = 'Type',
  ForgeComposeDraft = 'DiagnosticWarn',
  ForgeComposeFile = 'Directory',
  ForgeComposeAdded = 'Added',
  ForgeComposeRemoved = 'Removed',
  ForgeNumber = 'Number',
  ForgeOpen = 'DiagnosticInfo',
  ForgeMerged = 'Constant',
  ForgeClosed = 'Comment',
  ForgePass = 'DiagnosticOk',
  ForgeFail = 'DiagnosticError',
  ForgePending = 'DiagnosticWarn',
  ForgeSkip = 'Comment',
  ForgeBranch = 'Special',
  ForgeDim = 'Comment',
  ForgeLogJob = 'Title',
  ForgeLogStep = 'Function',
  ForgeLogError = 'DiagnosticVirtualTextError',
  ForgeLogErrorLabel = { bold = true },
  ForgeLogWarning = 'DiagnosticVirtualTextWarn',
  ForgeLogWarningLabel = { bold = true },
  ForgeLogSection = 'Function',
  ForgeLogCommand = 'Special',
  ForgeLogDim = 'Comment',
}

for group, val in pairs(hl_defaults) do
  if type(val) == 'string' then
    vim.api.nvim_set_hl(0, group, { default = true, link = val })
  else
    vim.api.nvim_set_hl(0, group, vim.tbl_extend('keep', { default = true }, val))
  end
end

local compose_ns = vim.api.nvim_create_namespace('forge_compose')

---@class forge.PRState
---@field state string
---@field mergeable string
---@field review_decision string
---@field is_draft boolean

---@class forge.Check
---@field name string
---@field status string
---@field elapsed string
---@field run_id string

---@class forge.CIRun
---@field id string
---@field name string
---@field branch string
---@field status string
---@field event string
---@field url string
---@field created_at string

---@class forge.RepoInfo
---@field permission string
---@field merge_methods string[]

---@class forge.Capabilities
---@field draft boolean
---@field reviewers boolean
---@field per_pr_checks boolean
---@field ci_json boolean

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string, pr_one: string, pr_full: string, ci: string }
---@field capabilities forge.Capabilities
---@field list_pr_json_cmd fun(self: forge.Forge, state: string): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string): string[]
---@field pr_json_fields fun(self: forge.Forge): { number: string, title: string, branch: string, state: string, author: string, created_at: string }
---@field issue_json_fields fun(self: forge.Forge): { number: string, title: string, state: string, author: string, created_at: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string)
---@field browse fun(self: forge.Forge, loc: string, branch: string)
---@field browse_branch fun(self: forge.Forge, branch: string)
---@field browse_commit fun(self: forge.Forge, sha: string)
---@field checkout_cmd fun(self: forge.Forge, num: string): string[]
---@field fetch_pr fun(self: forge.Forge, num: string): string[]
---@field pr_base_cmd fun(self: forge.Forge, num: string): string[]
---@field pr_for_branch_cmd fun(self: forge.Forge, branch: string): string[]
---@field checks_cmd fun(self: forge.Forge, num: string): string
---@field check_log_cmd fun(self: forge.Forge, run_id: string, failed_only: boolean, job_id: string?): string[]
---@field steps_cmd (fun(self: forge.Forge, run_id: string): string[])?
---@field view_cmd (fun(self: forge.Forge, id: string, opts?: { job_id?: string, log?: boolean, failed?: boolean }): string[])?
---@field watch_cmd (fun(self: forge.Forge, id: string): string[])?
---@field run_status_cmd (fun(self: forge.Forge, id: string): string[])?
---@field live_tail_cmd (fun(self: forge.Forge, run_id: string, job_id: string?): string[])?
---@field list_runs_json_cmd fun(self: forge.Forge, branch: string?): string[]
---@field list_runs_cmd fun(self: forge.Forge, branch: string?): string
---@field normalize_run fun(self: forge.Forge, entry: table): forge.CIRun
---@field run_log_cmd fun(self: forge.Forge, id: string, failed_only: boolean): string[]
---@field merge_cmd fun(self: forge.Forge, num: string, method: string): string[]
---@field approve_cmd fun(self: forge.Forge, num: string): string[]
---@field repo_info fun(self: forge.Forge): forge.RepoInfo
---@field pr_state fun(self: forge.Forge, num: string): forge.PRState
---@field close_cmd fun(self: forge.Forge, num: string): string[]
---@field reopen_cmd fun(self: forge.Forge, num: string): string[]
---@field close_issue_cmd fun(self: forge.Forge, num: string): string[]
---@field reopen_issue_cmd fun(self: forge.Forge, num: string): string[]
---@field draft_toggle_cmd fun(self: forge.Forge, num: string, is_draft: boolean): string[]?
---@field create_pr_cmd fun(self: forge.Forge, title: string, body: string, base: string, draft: boolean, reviewers: string[]?): string[]
---@field create_pr_web_cmd fun(self: forge.Forge): string[]?
---@field default_branch_cmd fun(self: forge.Forge): string[]
---@field checks_json_cmd (fun(self: forge.Forge, num: string): string[])?
---@field template_paths fun(self: forge.Forge): string[]
---@field list_releases_json_cmd fun(self: forge.Forge): string[]
---@field release_json_fields fun(self: forge.Forge): { tag: string, title: string, is_draft: string?, is_prerelease: string?, is_latest: string?, published_at: string }
---@field browse_release fun(self: forge.Forge, tag: string)
---@field delete_release_cmd fun(self: forge.Forge, tag: string): string[]
---@field create_issue_cmd fun(self: forge.Forge, title: string, body: string, labels: string[]?, assignees: string[]?): string[]
---@field issue_template_paths fun(self: forge.Forge): string[]
---@field create_issue_web_cmd (fun(self: forge.Forge): string[]?)?

---@type table<string, forge.Forge>
local forge_cache = {}

---@type table<string, forge.RepoInfo>
local repo_info_cache = {}

---@type table<string, string>
local root_cache = {}

---@type table<string, table[]>
local list_cache = {}

---@return string?
local function git_root()
  local cwd = vim.fn.getcwd()
  if root_cache[cwd] then
    return root_cache[cwd]
  end
  local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  root_cache[cwd] = root
  return root
end

local builtin_hosts = {
  github = { 'github' },
  gitlab = { 'gitlab' },
  codeberg = { 'codeberg', 'gitea', 'forgejo' },
}

local function resolve_source(name)
  if sources[name] then
    return sources[name]
  end
  local ok, mod = pcall(require, 'forge.' .. name)
  if ok then
    sources[name] = mod
    return mod
  end
  return nil
end

---@param remote string
---@return string? forge_name
local function detect_from_remote(remote)
  local cfg = M.config().sources

  for name, opts in pairs(cfg) do
    for _, host in ipairs(opts.hosts or {}) do
      if remote:find(host, 1, true) then
        return name
      end
    end
  end

  for name, patterns in pairs(builtin_hosts) do
    for _, pattern in ipairs(patterns) do
      if remote:find(pattern, 1, true) then
        return name
      end
    end
  end

  return nil
end

---@return forge.Forge?
function M.detect()
  local log = require('forge.logger')
  local root = git_root()
  if not root then
    log.debug('detect: not a git repository')
    return nil
  end
  if forge_cache[root] then
    return forge_cache[root]
  end
  local remote = vim.trim(vim.fn.system('git remote get-url origin'))
  if vim.v.shell_error ~= 0 then
    log.debug('detect: no origin remote')
    return nil
  end
  local name = detect_from_remote(remote)
  if not name then
    log.debug('detect: no forge matched remote ' .. remote)
    return nil
  end
  local source = resolve_source(name)
  if not source then
    log.debug('detect: failed to load source module ' .. name)
    return nil
  end
  if vim.fn.executable(source.cli) ~= 1 then
    log.debug('detect: CLI ' .. source.cli .. ' not found')
    return nil
  end
  forge_cache[root] = source
  return source
end

---@param f forge.Forge
---@return forge.RepoInfo
function M.repo_info(f)
  local root = git_root()
  if root and repo_info_cache[root] then
    return repo_info_cache[root]
  end
  local info = f:repo_info()
  if root then
    repo_info_cache[root] = info
  end
  return info
end

---@param kind string
---@param state string
---@return string
function M.list_key(kind, state)
  local root = git_root() or ''
  return root .. ':' .. kind .. ':' .. state
end

---@param key string
---@return table[]?
function M.get_list(key)
  return list_cache[key]
end

---@param key string
---@param data table[]
function M.set_list(key, data)
  list_cache[key] = data
end

---@param key string?
function M.clear_list(key)
  if key then
    list_cache[key] = nil
  else
    list_cache = {}
  end
end

function M.clear_cache()
  forge_cache = {}
  repo_info_cache = {}
  root_cache = {}
  list_cache = {}
end

---@return string
function M.file_loc()
  local root = git_root()
  if not root then
    return vim.fn.expand('%:t')
  end
  local file = vim.api.nvim_buf_get_name(0):sub(#root + 2)
  local mode = vim.fn.mode()
  if mode:match('[vV]') or mode == '\22' then
    local s = vim.fn.line('v')
    local e = vim.fn.line('.')
    if s > e then
      s, e = e, s
    end
    if s == e then
      return ('%s:%d'):format(file, s)
    end
    return ('%s:%d-%d'):format(file, s, e)
  end
  return ('%s:%d'):format(file, vim.fn.line('.'))
end

---@return string
function M.remote_web_url()
  local root = git_root()
  if not root then
    return ''
  end
  local remote = vim.trim(vim.fn.system('git remote get-url origin'))
  remote = remote:gsub('%.git$', '')
  remote = remote:gsub('^ssh://git@', 'https://')
  remote = remote:gsub('^git@([^:]+):', 'https://%1/')
  return remote
end

---@param s string
---@param width integer
---@return string
local function pad_or_truncate(s, width)
  local len = #s
  if len > width then
    return s:sub(1, width - 1) .. '…'
  end
  return s .. string.rep(' ', width - len)
end

---@param iso string?
---@return integer?
local function parse_iso(iso)
  if not iso or type(iso) ~= 'string' or iso == '' then
    return nil
  end
  local y, mo, d, h, mi, s = iso:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then
    return nil
  end
  local ok, ts = pcall(os.time, {
    year = tonumber(y) --[[@as integer]],
    month = tonumber(mo) --[[@as integer]],
    day = tonumber(d) --[[@as integer]],
    hour = tonumber(h) --[[@as integer]],
    min = tonumber(mi) --[[@as integer]],
    sec = tonumber(s) --[[@as integer]],
  })
  if ok and ts then
    return ts
  end
  return nil
end

---@param iso string?
---@return string
local function relative_time(iso)
  local ts = parse_iso(iso)
  if not ts then
    return ''
  end
  local diff = os.time() - ts
  if diff < 0 then
    diff = 0
  end
  if diff < 3600 then
    return ('%dm'):format(math.max(1, math.floor(diff / 60)))
  end
  if diff < 86400 then
    return ('%dh'):format(math.floor(diff / 3600))
  end
  if diff < 2592000 then
    return ('%dd'):format(math.floor(diff / 86400))
  end
  if diff < 31536000 then
    return ('%dmo'):format(math.floor(diff / 2592000))
  end
  return ('%dy'):format(math.floor(diff / 31536000))
end

local event_map = {
  merge_request_event = 'mr',
  external_pull_request_event = 'ext',
  pull_request = 'pr',
  workflow_dispatch = 'manual',
  schedule = 'cron',
  pipeline = 'child',
  push = 'push',
  web = 'web',
  api = 'api',
  trigger = 'trigger',
}

---@param event string
---@return string
local function abbreviate_event(event)
  return event_map[event] or event
end

---@param entry table
---@param field string
---@return string
local function extract_author(entry, field)
  local v = entry[field]
  if type(v) == 'table' then
    return v.login or v.username or v.name or ''
  end
  return tostring(v or '')
end

---@param secs integer
---@return string
local function format_duration(secs)
  if secs < 0 then
    secs = 0
  end
  if secs >= 3600 then
    return ('%dh%dm'):format(math.floor(secs / 3600), math.floor(secs % 3600 / 60))
  end
  if secs >= 60 then
    return ('%dm%ds'):format(math.floor(secs / 60), secs % 60)
  end
  return ('%ds'):format(secs)
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_pr(entry, fields, show_state)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = extract_author(entry, fields.author)
  local age = relative_time(entry[fields.created_at])
  local segments = {}
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, group
    if state == 'open' or state == 'opened' then
      icon, group = icons.open, 'ForgeOpen'
    elseif state == 'merged' then
      icon, group = icons.merged, 'ForgeMerged'
    else
      icon, group = icons.closed, 'ForgeClosed'
    end
    table.insert(segments, { icon, group })
    table.insert(segments, { '  ' })
  end
  table.insert(segments, { ('#%-5s'):format(num), 'ForgeNumber' })
  table.insert(segments, { ' ' .. pad_or_truncate(title, widths.title) .. ' ' })
  table.insert(segments, {
    pad_or_truncate(author, widths.author) .. (' %3s'):format(age),
    'ForgeDim',
  })
  return segments
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return forge.Segment[]
function M.format_issue(entry, fields, show_state)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = extract_author(entry, fields.author)
  local age = relative_time(entry[fields.created_at])
  local segments = {}
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, group
    if state == 'open' or state == 'opened' then
      icon, group = icons.open, 'ForgeOpen'
    else
      icon, group = icons.closed, 'ForgeClosed'
    end
    table.insert(segments, { icon, group })
    table.insert(segments, { '  ' })
  end
  table.insert(segments, { ('#%-5s'):format(num), 'ForgeNumber' })
  table.insert(segments, { ' ' .. pad_or_truncate(title, widths.title) .. ' ' })
  table.insert(segments, {
    pad_or_truncate(author, widths.author) .. (' %3s'):format(age),
    'ForgeDim',
  })
  return segments
end

---@param check table
---@return forge.Segment[]
function M.format_check(check)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local bucket = (check.bucket or 'pending'):lower()
  local name = check.name or ''
  local icon, group
  if bucket == 'pass' then
    icon, group = icons.pass, 'ForgePass'
  elseif bucket == 'fail' then
    icon, group = icons.fail, 'ForgeFail'
  elseif bucket == 'pending' then
    icon, group = icons.pending, 'ForgePending'
  elseif bucket == 'skipping' or bucket == 'cancel' then
    icon, group = icons.skip, 'ForgeSkip'
  else
    icon, group = icons.unknown, 'ForgeSkip'
  end
  local elapsed = ''
  local ts = parse_iso(check.startedAt)
  local te = parse_iso(check.completedAt)
  if ts and te then
    elapsed = format_duration(te - ts)
  end
  return {
    { icon, group },
    { '  ' .. pad_or_truncate(name, widths.name) .. ' ' },
    { elapsed, 'ForgeDim' },
  }
end

---@param run forge.CIRun
---@return forge.Segment[]
function M.format_run(run)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local icon, group
  local s = run.status:lower()
  if s == 'success' then
    icon, group = icons.pass, 'ForgePass'
  elseif s == 'failure' or s == 'failed' then
    icon, group = icons.fail, 'ForgeFail'
  elseif s == 'in_progress' or s == 'running' or s == 'pending' or s == 'queued' then
    icon, group = icons.pending, 'ForgePending'
  elseif s == 'cancelled' or s == 'canceled' or s == 'skipped' then
    icon, group = icons.skip, 'ForgeSkip'
  else
    icon, group = icons.unknown, 'ForgeSkip'
  end
  local event = abbreviate_event(run.event)
  local age = relative_time(run.created_at)
  if run.branch ~= '' then
    local name_w = widths.name - widths.branch + 10
    return {
      { icon, group },
      { '  ' .. pad_or_truncate(run.name, name_w) .. ' ' },
      { pad_or_truncate(run.branch, widths.branch), 'ForgeBranch' },
      { ' ' .. ('%-6s'):format(event) .. ' ' .. age, 'ForgeDim' },
    }
  end
  return {
    { icon, group },
    { '  ' .. pad_or_truncate(run.name, widths.name) .. ' ' },
    { ('%-6s'):format(event) .. ' ' .. age, 'ForgeDim' },
  }
end

---@param entry table
---@param fields table
---@return forge.Segment[]
function M.format_release(entry, fields)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local tag = entry[fields.tag] or ''
  local title = entry[fields.title] or ''
  local is_draft = fields.is_draft and entry[fields.is_draft]
  local is_pre = fields.is_prerelease and entry[fields.is_prerelease]
  local is_latest = fields.is_latest and entry[fields.is_latest]
  local age = relative_time(entry[fields.published_at])

  local icon, group
  if is_draft then
    icon, group = icons.pending, 'ForgePending'
  elseif is_pre then
    icon, group = icons.skip, 'ForgeSkip'
  elseif is_latest then
    icon, group = icons.pass, 'ForgePass'
  else
    icon, group = icons.open, 'ForgeOpen'
  end

  local tag_w = 20
  local title_w = widths.title
  if title == '' or title == tag then
    title_w = 0
  end

  local segments = {
    { icon, group },
    { '  ' .. pad_or_truncate(tag, tag_w), 'ForgeBranch' },
  }
  if title_w > 0 then
    table.insert(segments, { ' ' .. pad_or_truncate(title, title_w) .. ' ' })
  else
    table.insert(segments, { ' ' })
  end
  table.insert(segments, { ('%3s'):format(age), 'ForgeDim' })
  return segments
end

---@param checks table[]
---@param filter string?
---@return table[]
function M.filter_checks(checks, filter)
  if not filter or filter == 'all' then
    table.sort(checks, function(a, b)
      local order = { fail = 1, pending = 2, pass = 3, skipping = 4, cancel = 5 }
      local oa = order[(a.bucket or ''):lower()] or 9
      local ob = order[(b.bucket or ''):lower()] or 9
      return oa < ob
    end)
    return checks
  end
  local filtered = {}
  for _, c in ipairs(checks) do
    if (c.bucket or ''):lower() == filter then
      table.insert(filtered, c)
    end
  end
  return filtered
end

---@return forge.Config
function M.config()
  local user = vim.g.forge or {}
  local cfg = vim.tbl_deep_extend('force', DEFAULTS, user)
  if user.keys == false then
    cfg.keys = false
  end

  local picker_backends = require('forge.picker').backends
  vim.validate('forge.picker', cfg.picker, function(v)
    return v == 'auto' or picker_backends[v] ~= nil
  end, "'auto', 'fzf-lua', 'telescope', or 'snacks'")
  vim.validate('forge.debug', cfg.debug, function(v)
    return v == false or v == true or type(v) == 'string'
  end, 'boolean or string')
  vim.validate('forge.sources', cfg.sources, 'table')
  vim.validate('forge.keys', cfg.keys, function(v)
    return v == false or type(v) == 'table'
  end, 'table or false')
  vim.validate('forge.split', cfg.split, function(v)
    return v == 'horizontal' or v == 'vertical'
  end, "'horizontal' or 'vertical'")
  vim.validate('forge.display', cfg.display, 'table')
  vim.validate('forge.ci', cfg.ci, 'table')
  vim.validate('forge.ci.lines', cfg.ci.lines, 'number')
  vim.validate('forge.ci.refresh', cfg.ci.refresh, 'number')
  if cfg.ci.split ~= nil then
    vim.validate('forge.ci.split', cfg.ci.split, function(v)
      return v == 'horizontal' or v == 'vertical'
    end, "'horizontal' or 'vertical'")
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
  vim.validate('forge.display.widths.title', cfg.display.widths.title, 'number')
  vim.validate('forge.display.widths.author', cfg.display.widths.author, 'number')
  vim.validate('forge.display.widths.name', cfg.display.widths.name, 'number')
  vim.validate('forge.display.widths.branch', cfg.display.widths.branch, 'number')

  vim.validate('forge.display.limits', cfg.display.limits, 'table')
  vim.validate('forge.display.limits.pulls', cfg.display.limits.pulls, 'number')
  vim.validate('forge.display.limits.issues', cfg.display.limits.issues, 'number')
  vim.validate('forge.display.limits.runs', cfg.display.limits.runs, 'number')
  vim.validate('forge.display.limits.releases', cfg.display.limits.releases, 'number')

  local key_or_false = function(v)
    return v == false or type(v) == 'string'
  end
  if type(cfg.keys) == 'table' then
    local keys = cfg.keys --[[@as forge.KeysConfig]]
    if keys.pr ~= nil then
      vim.validate('forge.keys.pr', keys.pr, 'table')
      for _, k in ipairs({
        'checkout',
        'diff',
        'worktree',
        'ci',
        'browse',
        'manage',
        'create',
        'filter',
        'refresh',
      }) do
        vim.validate('forge.keys.pr.' .. k, keys.pr[k], key_or_false, 'string or false')
      end
    end
    if keys.issue ~= nil then
      vim.validate('forge.keys.issue', keys.issue, 'table')
      for _, k in ipairs({ 'browse', 'close', 'create', 'filter', 'refresh' }) do
        vim.validate('forge.keys.issue.' .. k, keys.issue[k], key_or_false, 'string or false')
      end
    end
    if keys.ci ~= nil then
      vim.validate('forge.keys.ci', keys.ci, 'table')
      for _, k in ipairs({ 'log', 'browse', 'failed', 'passed', 'running', 'all', 'refresh' }) do
        vim.validate('forge.keys.ci.' .. k, keys.ci[k], key_or_false, 'string or false')
      end
    end
    if keys.release ~= nil then
      vim.validate('forge.keys.release', keys.release, 'table')
      for _, k in ipairs({ 'browse', 'yank', 'delete', 'filter', 'refresh' }) do
        vim.validate('forge.keys.release.' .. k, keys.release[k], key_or_false, 'string or false')
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
        vim.validate('forge.keys.log.' .. k, keys.log[k], key_or_false, 'string or false')
      end
    end
  end

  for name, source in pairs(cfg.sources) do
    vim.validate('forge.sources.' .. name, source, 'table')
    if source.hosts ~= nil then
      vim.validate('forge.sources.' .. name .. '.hosts', source.hosts, 'table')
    end
  end

  return cfg
end

---@param branch string
---@param base string
---@return string title, string body
local function fill_from_commits(branch, base)
  local result = vim
    .system({ 'git', 'log', 'origin/' .. base .. '..HEAD', '--format=%s%n%b%x00' }, { text = true })
    :wait()
  local raw = vim.trim(result.stdout or '')
  if raw == '' then
    local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
    return clean, ''
  end

  local commits = {}
  for chunk in raw:gmatch('([^%z]+)') do
    local lines = vim.split(vim.trim(chunk), '\n', { plain = true })
    local subject = lines[1] or ''
    local body = vim.trim(table.concat(lines, '\n', 2))
    table.insert(commits, { subject = subject, body = body })
  end

  if #commits == 0 then
    local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
    return clean, ''
  end

  if #commits == 1 then
    return commits[1].subject, commits[1].body
  end

  local clean = branch:gsub('^%w+/', ''):gsub('[/-]', ' ')
  local lines = {}
  for _, c in ipairs(commits) do
    table.insert(lines, '- ' .. c.subject)
  end
  return clean, table.concat(lines, '\n')
end

---@param paths string[]
---@param repo_root string
---@param label string
---@return string?
local function discover_template(paths, repo_root, label)
  for _, p in ipairs(paths) do
    local full = repo_root .. '/' .. p
    local stat = vim.uv.fs_stat(full)
    if stat and stat.type == 'file' then
      local fd = vim.uv.fs_open(full, 'r', 438)
      if fd then
        local content = vim.uv.fs_read(fd, stat.size, 0)
        vim.uv.fs_close(fd)
        if content then
          return vim.trim(content)
        end
      end
    elseif stat and stat.type == 'directory' then
      local handle = vim.uv.fs_scandir(full)
      if handle then
        local templates = {}
        while true do
          local name, typ = vim.uv.fs_scandir_next(handle)
          if not name then
            break
          end
          if (typ == 'file' or not typ) and name:match('%.md$') then
            table.insert(templates, name)
          end
        end
        if #templates == 1 then
          local tpath = full .. '/' .. templates[1]
          local tstat = vim.uv.fs_stat(tpath)
          if tstat then
            local fd = vim.uv.fs_open(tpath, 'r', 438)
            if fd then
              local content = vim.uv.fs_read(fd, tstat.size, 0)
              vim.uv.fs_close(fd)
              if content then
                return vim.trim(content)
              end
            end
          end
        elseif #templates > 1 then
          table.sort(templates)
          local chosen
          vim.ui.select(templates, {
            prompt = label .. ' template: ',
          }, function(choice)
            chosen = choice
          end)
          if chosen then
            local tpath = full .. '/' .. chosen
            local tstat = vim.uv.fs_stat(tpath)
            if tstat then
              local fd = vim.uv.fs_open(tpath, 'r', 438)
              if fd then
                local content = vim.uv.fs_read(fd, tstat.size, 0)
                vim.uv.fs_close(fd)
                if content then
                  return vim.trim(content)
                end
              end
            end
          end
        end
      end
    end
  end
  return nil
end

---@param f forge.Forge
---@param branch string
---@param title string
---@param body string
---@param pr_base string
---@param pr_draft boolean
---@param pr_reviewers string[]?
---@param buf integer?
local function push_and_create(f, branch, title, body, pr_base, pr_draft, pr_reviewers, buf)
  local log = require('forge.logger')
  log.info('pushing and creating ' .. f.labels.pr_one .. '...')
  vim.system({ 'git', 'push', '-u', 'origin', branch }, { text = true }, function(push_result)
    if push_result.code ~= 0 then
      local msg = vim.trim(push_result.stderr or '')
      if msg == '' then
        msg = 'push failed'
      end
      vim.schedule(function()
        log.error(msg)
      end)
      return
    end
    vim.system(
      f:create_pr_cmd(title, body, pr_base, pr_draft, pr_reviewers),
      { text = true },
      function(create_result)
        vim.schedule(function()
          if create_result.code == 0 then
            local url = vim.trim(create_result.stdout or '')
            if url ~= '' then
              vim.fn.setreg('+', url)
            end
            log.info(('created %s → %s'):format(f.labels.pr_one, url))
            M.clear_list()
            if buf and vim.api.nvim_buf_is_valid(buf) then
              vim.bo[buf].modified = false
              vim.api.nvim_buf_delete(buf, { force = true })
            end
          else
            local msg = vim.trim(create_result.stderr or '')
            if msg == '' then
              msg = vim.trim(create_result.stdout or '')
            end
            if msg == '' then
              msg = 'creation failed'
            end
            log.error(msg)
          end
        end)
      end
    )
  end)
end

local function submit_issue(f, title, body, labels, assignees, buf)
  local log = require('forge.logger')
  log.info('creating issue...')
  vim.system(f:create_issue_cmd(title, body, labels, assignees), { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local url = vim.trim(result.stdout or '')
        if url ~= '' then
          vim.fn.setreg('+', url)
        end
        log.info(('created issue → %s'):format(url))
        M.clear_list()
        if buf and vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modified = false
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      else
        local msg = vim.trim(result.stderr or '')
        if msg == '' then
          msg = vim.trim(result.stdout or '')
        end
        if msg == '' then
          msg = 'creation failed'
        end
        log.error(msg)
      end
    end)
  end)
end

local function open_issue_compose_buffer(f)
  local root = git_root() or ''
  local template = discover_template(f:issue_template_paths(), root, 'Issue')

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'forge://issue/new')
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].swapfile = false

  local lines = { '', '' }
  if template and template ~= '' then
    for _, line in ipairs(vim.split(template, '\n', { plain = true })) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, '')
  end

  table.insert(lines, '')
  local comment_start = #lines + 1

  local marks = {}

  local function add_line(fmt, ...)
    local text = fmt:format(...)
    table.insert(lines, text)
    return #lines
  end

  local function mark(ln, start, len, hl_group)
    table.insert(marks, { line = ln, col = start, end_col = start + len, hl = hl_group })
  end

  add_line('<!--')

  local creating_prefix = '  Creating issue via '
  local ln = add_line('%s%s.', creating_prefix, f.name)
  mark(ln, #creating_prefix, #f.name, 'ForgeComposeForge')

  add_line('')
  local labels_prefix = '  Labels: '
  add_line('%s', labels_prefix)

  local assignees_prefix = '  Assignees: '
  add_line('%s', assignees_prefix)

  add_line('')
  add_line('  An empty title or body aborts creation.')
  add_line('-->')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  vim.api.nvim_set_current_buf(buf)

  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, m.line - 1, m.col, {
      end_col = m.end_col,
      hl_group = m.hl,
      priority = 200,
    })
  end
  for i = comment_start, #lines do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, i - 1, 0, {
      line_hl_group = 'ForgeComposeComment',
      priority = 200,
    })
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = {}
      for _, l in ipairs(buf_lines) do
        if l:match('^<!--') then
          break
        end
        table.insert(content_lines, l)
      end
      local issue_title = vim.trim(content_lines[1] or '')
      if issue_title == '' then
        require('forge.logger').warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local issue_body = vim.trim(table.concat(content_lines, '\n', 3))
      if issue_body == '' then
        require('forge.logger').warn('aborting: empty body')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local in_comment = false
      local issue_labels = {}
      local issue_assignees = {}
      for _, l in ipairs(buf_lines) do
        if l:match('^<!--') then
          in_comment = true
        elseif l:match('^%-%->') then
          break
        elseif in_comment then
          local lv = l:match('^%s*Labels:%s*(.*)$')
          if lv then
            for label in vim.trim(lv):gmatch('[^,%s]+') do
              table.insert(issue_labels, label)
            end
          end
          local av = l:match('^%s*Assignees:%s*(.*)$')
          if av then
            for assignee in vim.trim(av):gmatch('[^,%s]+') do
              table.insert(issue_assignees, assignee)
            end
          end
        end
      end

      submit_issue(f, issue_title, issue_body, issue_labels, issue_assignees, buf)
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.startinsert()
end

---@param f forge.Forge
---@param branch string
---@param base string
---@param draft boolean
local function open_compose_buffer(f, branch, base, draft)
  local root = git_root() or ''
  local title, commit_body = fill_from_commits(branch, base)
  local template = discover_template(f:template_paths(), root, f.labels.pr_one)
  local body = template or commit_body

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'forge://pr/new')
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].swapfile = false

  local lines = { title, '' }
  if body ~= '' then
    for _, line in ipairs(vim.split(body, '\n', { plain = true })) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, '')
  end

  table.insert(lines, '')
  local comment_start = #lines + 1

  local pr_kind = f.labels.pr_full:gsub('s$', '')
  local diff_stat = vim.fn.system('git diff --stat origin/' .. base .. '..HEAD'):gsub('%s+$', '')

  ---@type {line: integer, col: integer, end_col: integer, hl: string}[]
  local marks = {}

  local function add_line(fmt, ...)
    local text = fmt:format(...)
    table.insert(lines, text)
    return #lines
  end

  ---@param ln integer
  ---@param start integer
  ---@param len integer
  ---@param hl_group string
  local function mark(ln, start, len, hl_group)
    table.insert(marks, { line = ln, col = start, end_col = start + len, hl = hl_group })
  end

  add_line('<!--')

  local branch_prefix = '  On branch '
  local against = ' against '
  local ln = add_line('%s%s%s%s.', branch_prefix, branch, against, base)
  mark(ln, #branch_prefix, #branch, 'ForgeComposeBranch')
  mark(ln, #branch_prefix + #branch + #against, #base, 'ForgeComposeBranch')

  local creating_prefix = '  Creating ' .. pr_kind .. ' via '
  ln = add_line('%s%s.', creating_prefix, f.name)
  mark(ln, #creating_prefix, #f.name, 'ForgeComposeForge')

  add_line('')
  if f.capabilities.draft then
    local draft_val = draft and 'true' or 'false'
    local draft_prefix = '  Draft: '
    ln = add_line('%s%s', draft_prefix, draft_val)
    mark(ln, #draft_prefix, #draft_val, draft and 'ForgeComposeDraft' or 'ForgeDim')
  end

  if f.capabilities.reviewers then
    local reviewers_prefix = '  Reviewers: '
    add_line('%s', reviewers_prefix)
  end

  local stat_start, stat_end
  if diff_stat ~= '' then
    add_line('')
    local changes_prefix = '  Changes not in origin/'
    ln = add_line('%s%s:', changes_prefix, base)
    mark(ln, #changes_prefix, #base, 'ForgeComposeBranch')
    add_line('')
    stat_start = #lines + 1
    for _, sl in ipairs(vim.split(diff_stat, '\n', { plain = true })) do
      table.insert(lines, '  ' .. sl)
    end
    stat_end = #lines
  end
  add_line('')
  add_line('  An empty title or body aborts creation.')
  add_line('-->')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  vim.api.nvim_set_current_buf(buf)

  if stat_start and stat_end then
    for i = stat_start, stat_end do
      local line = lines[i]
      local pipe = line:find('|')
      if pipe then
        local fname_start = line:find('%S')
        if fname_start then
          mark(i, fname_start - 1, pipe - fname_start - 1, 'ForgeComposeFile')
        end
        for pos, run in line:gmatch('()([+-]+)') do
          if pos > pipe then
            local stat_hl = run:sub(1, 1) == '+' and 'ForgeComposeAdded' or 'ForgeComposeRemoved'
            mark(i, pos - 1, #run, stat_hl)
          end
        end
      end
    end
  end

  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, m.line - 1, m.col, {
      end_col = m.end_col,
      hl_group = m.hl,
      priority = 200,
    })
  end
  for i = comment_start, #lines do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, i - 1, 0, {
      line_hl_group = 'ForgeComposeComment',
      priority = 200,
    })
  end

  ---@return boolean, string[], string
  local function parse_comment()
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local in_comment = false
    local pr_draft = false
    local pr_reviewers = {}
    for _, l in ipairs(buf_lines) do
      if l:match('^<!--') then
        in_comment = true
      elseif l:match('^%-%->') then
        break
      elseif in_comment then
        local dv = l:match('^%s*Draft:%s*(.*)$')
        if dv then
          dv = vim.trim(dv):lower()
          pr_draft = dv == 'yes' or dv == 'true'
        end
        local rv = l:match('^%s*Reviewers:%s*(.*)$')
        if rv then
          for r in vim.trim(rv):gmatch('[^,%s]+') do
            table.insert(pr_reviewers, r)
          end
        end
      end
    end
    return pr_draft, pr_reviewers, base
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = {}
      for _, l in ipairs(buf_lines) do
        if l:match('^<!--') then
          break
        end
        table.insert(content_lines, l)
      end
      local pr_title = vim.trim(content_lines[1] or '')
      if pr_title == '' then
        require('forge.logger').warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = vim.trim(table.concat(content_lines, '\n', 3))
      if pr_body == '' then
        require('forge.logger').warn('aborting: empty body')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local pr_draft, pr_reviewers, pr_base = parse_comment()

      push_and_create(f, branch, pr_title, pr_body, pr_base, pr_draft, pr_reviewers, buf)
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('normal! 0vg_')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

---@class forge.CreatePROpts
---@field draft boolean?
---@field instant boolean?
---@field web boolean?

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end

  local branch = vim.trim(vim.fn.system('git branch --show-current'))
  if branch == '' then
    log.warn('detached HEAD')
    return
  end

  log.info('checking for existing ' .. f.labels.pr_one .. '...')

  vim.system(f:pr_for_branch_cmd(branch), { text = true }, function(result)
    local num = vim.trim(result.stdout or '')
    vim.schedule(function()
      if num ~= '' and num ~= 'null' then
        log.warn(('%s #%s already exists for branch %s'):format(f.labels.pr_one, num, branch))
        return
      end

      if opts.web then
        log.info('pushing...')
        vim.system({ 'git', 'push', '-u', 'origin', branch }, { text = true }, function(push_result)
          vim.schedule(function()
            if push_result.code ~= 0 then
              log.error('push failed')
              return
            end
            local web_cmd = f:create_pr_web_cmd()
            if web_cmd then
              vim.system(web_cmd)
            end
          end)
        end)
        return
      end

      log.info('resolving base branch...')
      vim.system(f:default_branch_cmd(), { text = true }, function(base_result)
        local base = vim.trim(base_result.stdout or '')
        if base == '' then
          base = 'main'
        end
        vim.schedule(function()
          local has_diff = vim
            .system({ 'git', 'diff', '--quiet', 'origin/' .. base .. '..HEAD' }, { text = true })
            :wait().code ~= 0
          if not has_diff then
            log.warn('no changes from origin/' .. base)
            return
          end
          if opts.instant then
            local title, body = fill_from_commits(branch, base)
            push_and_create(f, branch, title, body, base, opts.draft or false)
          else
            open_compose_buffer(f, branch, base, opts.draft or false)
          end
        end)
      end)
    end)
  end)
end

---@class forge.CreateIssueOpts
---@field web boolean?

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  opts = opts or {}
  local log = require('forge.logger')

  local f = M.detect()
  if not f then
    log.warn('no forge detected')
    return
  end

  if opts.web then
    if f.create_issue_web_cmd then
      local cmd = f:create_issue_web_cmd()
      if cmd then
        vim.system(cmd)
      end
    else
      local url = M.remote_web_url() .. '/issues/new'
      vim.ui.open(url)
    end
    return
  end

  open_issue_compose_buffer(f)
end

return M
