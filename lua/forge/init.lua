local M = {}

---@class forge.Config
---@field ci forge.CIConfig
---@field sources table<string, forge.SourceConfig>
---@field keys forge.KeysConfig|false
---@field picker_keys forge.PickerKeysConfig|false
---@field display forge.DisplayConfig

---@class forge.CIConfig
---@field lines integer

---@class forge.SourceConfig
---@field hosts string[]

---@class forge.KeysConfig
---@field picker string|false
---@field next_qf string|false
---@field prev_qf string|false
---@field next_loc string|false
---@field prev_loc string|false
---@field review_toggle string|false
---@field terminal_open string|false
---@field fugitive forge.FugitiveKeysConfig|false

---@class forge.FugitiveKeysConfig
---@field create string|false
---@field create_draft string|false
---@field create_fill string|false
---@field create_web string|false

---@class forge.PickerKeysConfig
---@field pr forge.PRPickerKeys
---@field issue forge.IssuePickerKeys
---@field checks forge.ChecksPickerKeys
---@field ci forge.CIPickerKeys
---@field commits forge.CommitsPickerKeys
---@field branches forge.BranchesPickerKeys

---@class forge.PRPickerKeys
---@field checkout string|false
---@field diff string|false
---@field worktree string|false
---@field checks string|false
---@field browse string|false
---@field manage string|false
---@field create string|false
---@field toggle string|false
---@field refresh string|false

---@class forge.IssuePickerKeys
---@field browse string|false
---@field close_reopen string|false
---@field toggle string|false
---@field refresh string|false

---@class forge.ChecksPickerKeys
---@field log string|false
---@field browse string|false
---@field failed string|false
---@field passed string|false
---@field running string|false
---@field all string|false

---@class forge.CIPickerKeys
---@field log string|false
---@field browse string|false
---@field refresh string|false

---@class forge.CommitsPickerKeys
---@field checkout string|false
---@field diff string|false
---@field browse string|false
---@field yank string|false

---@class forge.BranchesPickerKeys
---@field diff string|false
---@field browse string|false

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

---@type forge.Config
local DEFAULTS = {
  ci = { lines = 10000 },
  sources = {},
  keys = {
    picker = '<c-g>',
    next_qf = ']q',
    prev_qf = '[q',
    next_loc = ']l',
    prev_loc = '[l',
    review_toggle = 's',
    terminal_open = 'gx',
    fugitive = {
      create = 'cpr',
      create_draft = 'cpd',
      create_fill = 'cpf',
      create_web = 'cpw',
    },
  },
  picker_keys = {
    pr = {
      checkout = 'default',
      diff = 'ctrl-d',
      worktree = 'ctrl-w',
      checks = 'ctrl-t',
      browse = 'ctrl-x',
      manage = 'ctrl-e',
      create = 'ctrl-a',
      toggle = 'ctrl-o',
      refresh = 'ctrl-r',
    },
    issue = { browse = 'default', close_reopen = 'ctrl-s', toggle = 'ctrl-o', refresh = 'ctrl-r' },
    checks = {
      log = 'default',
      browse = 'ctrl-x',
      failed = 'ctrl-f',
      passed = 'ctrl-p',
      running = 'ctrl-n',
      all = 'ctrl-a',
    },
    ci = { log = 'default', browse = 'ctrl-x', refresh = 'ctrl-r' },
    commits = { checkout = 'default', diff = 'ctrl-d', browse = 'ctrl-x', yank = 'ctrl-y' },
    branches = { diff = 'ctrl-d', browse = 'ctrl-x' },
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
  ForgeComposeComment = 'Comment',
  ForgeComposeBranch = 'Special',
  ForgeComposeForge = 'Type',
  ForgeComposeDraft = 'DiagnosticWarn',
  ForgeComposeFile = 'Directory',
  ForgeComposeAdded = 'Added',
  ForgeComposeRemoved = 'Removed',
}

for group, link in pairs(hl_defaults) do
  vim.api.nvim_set_hl(0, group, { default = true, link = link })
end

local compose_ns = vim.api.nvim_create_namespace('forge_compose')

---@param msg string
---@param level integer?
function M.log(msg, level)
  vim.schedule(function()
    vim.notify('[forge.nvim]: ' .. msg, level or vim.log.levels.INFO)
    vim.cmd.redraw()
  end)
end

---@param msg string
---@param level integer?
function M.log_now(msg, level)
  vim.notify('[forge.nvim]: ' .. msg, level or vim.log.levels.INFO)
  vim.cmd.redraw()
end

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

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string, pr_one: string, pr_full: string, ci: string }
---@field list_pr_json_cmd fun(self: forge.Forge, state: string): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string): string[]
---@field pr_json_fields fun(self: forge.Forge): { number: string, title: string, branch: string, state: string, author: string, created_at: string }
---@field issue_json_fields fun(self: forge.Forge): { number: string, title: string, state: string, author: string, created_at: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string)
---@field browse fun(self: forge.Forge, loc: string, branch: string)
---@field browse_root fun(self: forge.Forge)
---@field browse_branch fun(self: forge.Forge, branch: string)
---@field browse_commit fun(self: forge.Forge, sha: string)
---@field checkout_cmd fun(self: forge.Forge, num: string): string[]
---@field yank_branch fun(self: forge.Forge, loc: string)
---@field yank_commit fun(self: forge.Forge, loc: string)
---@field fetch_pr fun(self: forge.Forge, num: string): string[]
---@field pr_base_cmd fun(self: forge.Forge, num: string): string[]
---@field pr_for_branch_cmd fun(self: forge.Forge, branch: string): string[]
---@field checks_cmd fun(self: forge.Forge, num: string): string
---@field check_log_cmd fun(self: forge.Forge, run_id: string, failed_only: boolean): string[]
---@field check_tail_cmd fun(self: forge.Forge, run_id: string): string[]
---@field list_runs_json_cmd fun(self: forge.Forge, branch: string?): string[]
---@field list_runs_cmd fun(self: forge.Forge, branch: string?): string
---@field normalize_run fun(self: forge.Forge, entry: table): forge.CIRun
---@field run_log_cmd fun(self: forge.Forge, id: string, failed_only: boolean): string[]
---@field run_tail_cmd fun(self: forge.Forge, id: string): string[]
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
---@field template_paths fun(self: forge.Forge): string[]

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
  local root = git_root()
  if not root then
    return nil
  end
  if forge_cache[root] then
    return forge_cache[root]
  end
  local remote = vim.trim(vim.fn.system('git remote get-url origin'))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local name = detect_from_remote(remote)
  if not name then
    return nil
  end
  local source = resolve_source(name)
  if not source then
    return nil
  end
  if vim.fn.executable(source.cli) ~= 1 then
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
  if not iso or iso == '' then
    return nil
  end
  local y, mo, d, h, mi, s = iso:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then
    return nil
  end
  local ok, ts = pcall(os.time, {
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
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

---@param iso string?
---@return string
local function compact_date(iso)
  local ts = parse_iso(iso)
  if not ts then
    return ''
  end
  local current_year = os.date('%Y')
  local entry_year = os.date('%Y', ts)
  if entry_year == current_year then
    return os.date('%d/%m %H:%M', ts)
  end
  return os.date('%d/%m/%y %H:%M', ts)
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

---@param entry table
---@param fields table
---@param show_state boolean
---@return string
function M.format_pr(entry, fields, show_state)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = extract_author(entry, fields.author)
  local age = relative_time(entry[fields.created_at])
  local prefix = ''
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, color
    if state == 'open' or state == 'opened' then
      icon, color = icons.open, '\27[34m'
    elseif state == 'merged' then
      icon, color = icons.merged, '\27[35m'
    else
      icon, color = icons.closed, '\27[31m'
    end
    prefix = color .. icon .. '\27[0m  '
  end
  return ('%s\27[34m#%-5s\27[0m %s \27[2m%-' .. widths.author .. 's %3s\27[0m'):format(
    prefix,
    num,
    pad_or_truncate(title, widths.title),
    pad_or_truncate(author, widths.author),
    age
  )
end

---@param entry table
---@param fields table
---@param show_state boolean
---@return string
function M.format_issue(entry, fields, show_state)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local num = tostring(entry[fields.number] or '')
  local title = entry[fields.title] or ''
  local author = extract_author(entry, fields.author)
  local age = relative_time(entry[fields.created_at])
  local prefix = ''
  if show_state then
    local state = (entry[fields.state] or ''):lower()
    local icon, color
    if state == 'open' or state == 'opened' then
      icon, color = icons.open, '\27[34m'
    else
      icon, color = icons.closed, '\27[2m'
    end
    prefix = color .. icon .. '\27[0m  '
  end
  return ('%s\27[34m#%-5s\27[0m %s \27[2m%-' .. widths.author .. 's %3s\27[0m'):format(
    prefix,
    num,
    pad_or_truncate(title, widths.title),
    pad_or_truncate(author, widths.author),
    age
  )
end

---@param check table
---@return string
function M.format_check(check)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local bucket = (check.bucket or 'pending'):lower()
  local name = check.name or ''
  local icon, color
  if bucket == 'pass' then
    icon, color = icons.pass, '\27[32m'
  elseif bucket == 'fail' then
    icon, color = icons.fail, '\27[31m'
  elseif bucket == 'pending' then
    icon, color = icons.pending, '\27[33m'
  elseif bucket == 'skipping' or bucket == 'cancel' then
    icon, color = icons.skip, '\27[2m'
  else
    icon, color = icons.unknown, '\27[2m'
  end
  local elapsed = ''
  if check.startedAt and check.completedAt and check.completedAt ~= '' then
    local ok_s, ts = pcall(vim.fn.strptime, '%Y-%m-%dT%H:%M:%SZ', check.startedAt)
    local ok_e, te = pcall(vim.fn.strptime, '%Y-%m-%dT%H:%M:%SZ', check.completedAt)
    if ok_s and ok_e and ts > 0 and te > 0 then
      local secs = te - ts
      if secs >= 60 then
        elapsed = ('%dm%ds'):format(math.floor(secs / 60), secs % 60)
      else
        elapsed = ('%ds'):format(secs)
      end
    end
  end
  return ('%s%s\27[0m  %s \27[2m%s\27[0m'):format(
    color,
    icon,
    pad_or_truncate(name, widths.name),
    elapsed
  )
end

---@param run forge.CIRun
---@return string
function M.format_run(run)
  local display = M.config().display
  local icons = display.icons
  local widths = display.widths
  local icon, color
  local s = run.status:lower()
  if s == 'success' then
    icon, color = icons.pass, '\27[32m'
  elseif s == 'failure' or s == 'failed' then
    icon, color = icons.fail, '\27[31m'
  elseif s == 'in_progress' or s == 'running' or s == 'pending' or s == 'queued' then
    icon, color = icons.pending, '\27[33m'
  elseif s == 'cancelled' or s == 'canceled' or s == 'skipped' then
    icon, color = icons.skip, '\27[2m'
  else
    icon, color = icons.unknown, '\27[2m'
  end
  local event = abbreviate_event(run.event)
  local date = compact_date(run.created_at)
  if run.branch ~= '' then
    local name_w = widths.name - widths.branch + 10
    return ('%s%s\27[0m  %s \27[36m%s\27[0m \27[2m%-6s %s\27[0m'):format(
      color,
      icon,
      pad_or_truncate(run.name, name_w),
      pad_or_truncate(run.branch, widths.branch),
      event,
      date
    )
  end
  return ('%s%s\27[0m  %s \27[2m%-6s %s\27[0m'):format(
    color,
    icon,
    pad_or_truncate(run.name, widths.name),
    event,
    date
  )
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
  if user.picker_keys == false then
    cfg.picker_keys = false
  end
  return cfg
end

---@param args string[]
function M.yank_url(args)
  vim.system(args, { text = true }, function(result)
    if result.code == 0 then
      local url = vim.trim(result.stdout or '')
      if url ~= '' then
        vim.schedule(function()
          vim.fn.setreg('+', url)
        end)
      end
    end
  end)
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

---@param f forge.Forge
---@param repo_root string
---@return string?
local function discover_template(f, repo_root)
  local paths = f:template_paths()
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
            prompt = 'PR template: ',
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
  M.log_now('pushing and creating ' .. f.labels.pr_one .. '...')
  vim.system({ 'git', 'push', '-u', 'origin', branch }, { text = true }, function(push_result)
    if push_result.code ~= 0 then
      local msg = vim.trim(push_result.stderr or '')
      if msg == '' then
        msg = 'push failed'
      end
      M.log(msg, vim.log.levels.ERROR)
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
            M.log_now(('created %s → %s'):format(f.labels.pr_one, url))
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
            M.log_now(msg, vim.log.levels.ERROR)
          end
          vim.cmd.redraw()
        end)
      end
    )
  end)
end

---@param f forge.Forge
---@param branch string
---@param base string
---@param draft boolean
local function open_compose_buffer(f, branch, base, draft)
  local root = git_root() or ''
  local title, commit_body = fill_from_commits(branch, base)
  local template = discover_template(f, root)
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
  ---@param hl string
  local function mark(ln, start, len, hl)
    table.insert(marks, { line = ln, col = start, end_col = start + len, hl = hl })
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
  local draft_val = draft and 'yes' or ''
  local draft_prefix = '  Draft: '
  ln = add_line('%s%s', draft_prefix, draft_val)
  if draft_val ~= '' then
    mark(ln, #draft_prefix, #draft_val, 'ForgeComposeDraft')
  end

  local reviewers_prefix = '  Reviewers: '
  add_line('%s', reviewers_prefix)

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
            local hl = run:sub(1, 1) == '+' and 'ForgeComposeAdded' or 'ForgeComposeRemoved'
            mark(i, pos - 1, #run, hl)
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
        M.log_now('aborting: empty title', vim.log.levels.WARN)
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = vim.trim(table.concat(content_lines, '\n', 3))
      if pr_body == '' then
        M.log_now('aborting: empty body', vim.log.levels.WARN)
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

  local f = M.detect()
  if not f then
    M.log_now('no forge detected', vim.log.levels.WARN)
    return
  end

  local branch = vim.trim(vim.fn.system('git branch --show-current'))
  if branch == '' then
    M.log_now('detached HEAD', vim.log.levels.WARN)
    return
  end

  M.log_now('checking for existing ' .. f.labels.pr_one .. '...')

  vim.system(f:pr_for_branch_cmd(branch), { text = true }, function(result)
    local num = vim.trim(result.stdout or '')
    vim.schedule(function()
      if num ~= '' and num ~= 'null' then
        M.log_now(
          ('%s #%s already exists for branch %s'):format(f.labels.pr_one, num, branch),
          vim.log.levels.WARN
        )
        return
      end

      if opts.web then
        M.log_now('pushing...')
        vim.system({ 'git', 'push', '-u', 'origin', branch }, { text = true }, function(push_result)
          vim.schedule(function()
            if push_result.code ~= 0 then
              M.log_now('push failed', vim.log.levels.ERROR)
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

      M.log_now('resolving base branch...')
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
            M.log_now('no changes from origin/' .. base, vim.log.levels.WARN)
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

return M
