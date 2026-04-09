local M = {}

---@type { base: string?, mode: 'unified'|'split' }
M.state = { base = nil, mode = 'unified' }

local log = require('forge.logger')
local review_augroup = vim.api.nvim_create_augroup('ForgeReview', { clear = true })
local active_session = nil
local current_file = nil

local function repo_root()
  return vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
end

local function git_output(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or '')
end

local function normalize_mode(mode)
  if mode == 'split' or mode == 'context' then
    return 'context'
  end
  return 'patch'
end

local function state_mode(mode)
  if normalize_mode(mode) == 'context' then
    return 'split'
  end
  return 'unified'
end

local function base_ref()
  if active_session and active_session.subject then
    return active_session.subject.base_ref
  end
  return M.state.base
end

local function open_unified(base, root)
  local ok, commands = pcall(require, 'diffs.commands')
  if ok then
    commands.greview(base, { repo_root = root })
  end
end

local function normalize_base(base)
  if not base or base == '' then
    return nil
  end
  base = base:gsub('^refs/remotes/', '')
  if not base:match('^origin/') then
    base = 'origin/' .. base
  end
  return base
end

local function default_base(ctx)
  if ctx.forge and ctx.forge.default_branch_cmd then
    local branch = git_output(ctx.forge:default_branch_cmd())
    branch = normalize_base(branch)
    if branch then
      return branch
    end
  end
  local branch = git_output({ 'git', '-C', ctx.root, 'symbolic-ref', 'refs/remotes/origin/HEAD' })
  branch = normalize_base(branch)
  if branch then
    return branch
  end
  for _, fallback in ipairs({ 'origin/main', 'origin/master' }) do
    local ok = git_output({ 'git', '-C', ctx.root, 'rev-parse', '--verify', fallback })
    if ok then
      return fallback
    end
  end
  return nil
end

local function temp_worktree(root, ref)
  local path = vim.fn.tempname()
  local result = vim
    .system({ 'git', '-C', root, 'worktree', 'add', '--detach', path, ref }, { text = true })
    :wait()
  if result.code ~= 0 then
    return nil
  end
  return path
end

local function empty_tree(root)
  return git_output({
    'sh',
    '-c',
    ('git -C %s hash-object -t tree /dev/null'):format(vim.fn.shellescape(root)),
  })
end

local function commit_base(root, sha)
  local line = git_output({ 'git', '-C', root, 'rev-list', '--parents', '-n', '1', sha })
  if not line then
    return nil
  end
  local parts = vim.split(line, ' ', { plain = true, trimempty = true })
  if #parts > 1 then
    return parts[2]
  end
  return empty_tree(root)
end

local function review_root()
  if active_session and active_session.worktree_path then
    return active_session.worktree_path
  end
  if active_session and active_session.repo_root then
    return active_session.repo_root
  end
  return repo_root()
end

local function placeholder_entry(text)
  return {
    display = { { text, 'ForgeDim' } },
    value = nil,
    ordinal = text,
    placeholder = true,
  }
end

local function status_hl(status)
  local kind = status:sub(1, 1)
  if kind == 'A' or kind == 'C' then
    return 'DiffAdd'
  end
  if kind == 'D' then
    return 'DiffDelete'
  end
  if kind == 'R' then
    return 'DiffText'
  end
  return 'DiffChange'
end

local function file_display(item)
  local display = {
    { item.status, status_hl(item.status) },
    { ' ' .. item.path },
  }
  if item.old_path and item.old_path ~= item.path then
    display[#display + 1] = { ' <- ' .. item.old_path, 'ForgeDim' }
  end
  return display
end

local function parse_changed_files(output)
  local files = {}
  for _, line in ipairs(vim.split(output or '', '\n', { plain = true, trimempty = true })) do
    local fields = vim.split(line, '\t', { plain = true })
    if #fields >= 2 then
      local item = {
        status = fields[1],
        path = fields[#fields],
      }
      if #fields >= 3 then
        item.old_path = fields[2]
      end
      files[#files + 1] = item
    end
  end
  return files
end

local function close_view()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match('^fugitive://') or name:match('^diffs://') then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(vim.cmd, 'diffoff!')
end

function M.stop()
  if
    active_session
    and active_session.materialization == 'worktree'
    and active_session.worktree_path
  then
    vim.system({
      'git',
      '-C',
      active_session.repo_root,
      'worktree',
      'remove',
      '--force',
      active_session.worktree_path,
    }, { text = true })
  end
  active_session = nil
  current_file = nil
  M.state.base = nil
  M.state.mode = 'unified'
  vim.api.nvim_clear_autocmds({ group = review_augroup })
end

function M.current()
  return active_session
end

function M.open_file(path)
  local session = active_session
  local base = base_ref()
  if not session or not base or not path or path == '' then
    return
  end

  session.current_file = path
  current_file = path

  close_view()

  local root = review_root()
  local abs_path = root .. '/' .. path
  if vim.fn.filereadable(abs_path) == 1 then
    vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))
  else
    vim.cmd('enew')
    vim.api.nvim_buf_set_name(0, abs_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
  end

  if normalize_mode(session.mode) == 'context' then
    pcall(vim.cmd, 'Gvdiffsplit ' .. base)
    return
  end

  local ok, commands = pcall(require, 'diffs.commands')
  if ok then
    commands.gdiff(base, false)
  end
end

function M.open_index()
  local session = active_session
  local base = base_ref()
  if not session or not base then
    return
  end

  local picker = require('forge.picker')

  local function open_picker(files)
    session.files = files
    local entries = {}
    for _, item in ipairs(files) do
      entries[#entries + 1] = {
        display = file_display(item),
        value = item,
        ordinal = item.path .. ' ' .. (item.old_path or ''),
      }
    end
    if #entries == 0 then
      entries = { placeholder_entry('No changed files') }
    end

    picker.pick({
      prompt = ('Review Files: %s (%d)> '):format(
        normalize_mode(session.mode):gsub('^%l', string.upper),
        #files
      ),
      entries = entries,
      actions = {
        {
          name = 'default',
          label = 'open',
          fn = function(entry)
            if entry then
              M.open_file(entry.value.path)
            end
          end,
        },
      },
      picker_name = '_menu',
    })
  end

  if session.files and #session.files > 0 then
    open_picker(session.files)
    return
  end

  vim.system({
    'git',
    '-C',
    review_root(),
    'diff',
    '--name-status',
    '--find-renames',
    '--find-copies',
    '--no-ext-diff',
    base,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        log.error('failed to load review files')
        return
      end
      open_picker(parse_changed_files(result.stdout or ''))
    end)
  end)
end

function M.toggle()
  local session = active_session
  local base = base_ref()
  if not base then
    return
  end
  if session then
    if normalize_mode(session.mode) == 'patch' then
      session.mode = 'context'
      M.state.mode = 'split'
    else
      session.mode = 'patch'
      M.state.mode = 'unified'
    end
    if session.current_file then
      M.open_file(session.current_file)
    else
      M.open_index()
    end
    return
  end
  if M.state.mode == 'unified' then
    local ok, commands = pcall(require, 'diffs.commands')
    if not ok or type(commands.review_file_at_line) ~= 'function' then
      if session then
        session.mode = 'split'
      end
      M.state.mode = 'split'
      return
    end
    local file = commands.review_file_at_line(vim.api.nvim_get_current_buf(), vim.fn.line('.'))
    if session then
      session.current_file = file
      current_file = file
      session.mode = 'context'
    end
    M.state.mode = 'split'
    if file then
      M.open_file(file)
    end
  else
    local file = vim.fn.expand('%:.')
    if session and file ~= '' then
      session.current_file = file
    end
    if file ~= '' then
      current_file = file
    end
    close_view()
    if session then
      session.mode = 'patch'
    end
    M.state.mode = 'unified'
    if session and session.current_file then
      M.open_file(session.current_file)
      return
    end
    open_unified(base, session and session.repo_root or repo_root())
    local target = session and session.current_file or current_file
    if target and target ~= '' then
      vim.fn.search('diff %-%-git a/' .. vim.pesc(target), 'cw')
    end
  end
end

function M.start_session(session)
  M.stop()
  session = vim.deepcopy(session)
  session.files = session.files or {}
  session.mode = normalize_mode(session.mode)
  session.current_file = session.current_file or nil
  session.materialization = session.materialization or 'current'
  session.repo_root = session.repo_root or repo_root()
  active_session = session
  current_file = session.current_file
  if session.subject and session.subject.base_ref then
    M.state.base = session.subject.base_ref
  else
    M.state.base = nil
  end
  M.state.mode = state_mode(session.mode)
  vim.api.nvim_clear_autocmds({ group = review_augroup })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = review_augroup,
    pattern = 'diffs://review:*',
    callback = M.stop,
  })
end

---@param base string
---@param mode string?
function M.start(base, mode)
  M.start_session({
    subject = {
      kind = 'ref',
      id = base,
      label = base,
      base_ref = base,
      head_ref = vim.trim(vim.fn.system('git rev-parse --show-current')),
    },
    mode = mode or 'patch',
    files = {},
    current_file = nil,
    materialization = 'current',
    repo_root = repo_root(),
  })
end

function M.files()
  M.open_index()
end

function M.start_branch(ctx, branch)
  branch = branch or ctx.branch
  if not branch or branch == '' then
    log.warn('missing branch')
    return
  end
  local base = default_base(ctx)
  if not base then
    log.warn('failed to resolve branch review base')
    return
  end

  local session = {
    subject = {
      kind = 'branch',
      id = branch,
      label = 'Branch ' .. branch,
      base_ref = base,
      head_ref = branch,
    },
    mode = 'patch',
    files = {},
    current_file = nil,
    materialization = 'current',
    repo_root = ctx.root,
  }

  if ctx.branch ~= branch then
    local worktree = temp_worktree(ctx.root, branch)
    if not worktree then
      log.error('failed to materialize branch review')
      return
    end
    session.materialization = 'worktree'
    session.worktree_path = worktree
  end

  M.start_session(session)
  M.open_index()
end

function M.start_commit(ctx, sha)
  sha = sha or ctx.head
  if not sha or sha == '' then
    log.warn('missing commit')
    return
  end
  local base = commit_base(ctx.root, sha)
  if not base then
    log.error('failed to resolve commit review base')
    return
  end
  local worktree = temp_worktree(ctx.root, sha)
  if not worktree then
    log.error('failed to materialize commit review')
    return
  end

  M.start_session({
    subject = {
      kind = 'commit',
      id = sha,
      label = 'Commit ' .. sha:sub(1, 7),
      base_ref = base,
      head_ref = sha,
    },
    mode = 'patch',
    files = {},
    current_file = nil,
    materialization = 'worktree',
    repo_root = ctx.root,
    worktree_path = worktree,
  })
  M.open_index()
end

local function jump_file(step)
  local session = active_session
  if not session then
    return
  end
  local files = session.files or {}
  if #files == 0 then
    M.open_index()
    return
  end

  local index = step > 0 and 1 or #files
  if session.current_file then
    for i, item in ipairs(files) do
      if item.path == session.current_file then
        index = i + step
        break
      end
    end
  end

  if index < 1 then
    index = #files
  elseif index > #files then
    index = 1
  end

  M.open_file(files[index].path)
end

function M.next_file()
  jump_file(1)
end

function M.prev_file()
  jump_file(-1)
end

local function jump_hunk(step)
  if M.state.mode == 'split' then
    pcall(vim.cmd, step > 0 and 'normal ]c' or 'normal [c')
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local hunks = {}
  for i, line in ipairs(lines) do
    if line:match('^@@') then
      hunks[#hunks + 1] = i
    end
  end
  if #hunks == 0 then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local target
  if step > 0 then
    for _, hunk in ipairs(hunks) do
      if hunk > cursor then
        target = hunk
        break
      end
    end
    target = target or hunks[1]
  else
    for i = #hunks, 1, -1 do
      if hunks[i] < cursor then
        target = hunks[i]
        break
      end
    end
    target = target or hunks[#hunks]
  end

  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

function M.next_hunk()
  jump_hunk(1)
end

function M.prev_hunk()
  jump_hunk(-1)
end

---@param nav_cmd string
---@return function
function M.nav(nav_cmd)
  return function()
    local session = active_session
    local base = base_ref()
    if base and M.state.mode == 'split' then
      close_view()
    end
    local wrap = {
      cnext = 'cfirst',
      cprev = 'clast',
      lnext = 'lfirst',
      lprev = 'llast',
    }
    if not pcall(vim.cmd, nav_cmd) then
      if not pcall(vim.cmd, wrap[nav_cmd]) then
        return
      end
    end
    if base and M.state.mode == 'split' then
      pcall(vim.cmd, 'Gvdiffsplit ' .. base)
      if session and session.repo_root then
        local file = vim.fn.expand('%:.')
        if file ~= '' then
          session.current_file = file
          current_file = file
        end
      end
    end
  end
end

return M
