local M = {}

local template = require('forge.template')

local compose_ns = vim.api.nvim_create_namespace('forge_compose')

---@class forge.ComposeBuilder
---@field lines string[]
---@field marks {line: integer, col: integer, end_col: integer, hl: string}[]
local ComposeBuilder = {}
ComposeBuilder.__index = ComposeBuilder

---@return forge.ComposeBuilder
function ComposeBuilder.new()
  return setmetatable({ lines = {}, marks = {} }, ComposeBuilder)
end

---@param fmt string
---@param ... any
---@return integer
function ComposeBuilder:add_line(fmt, ...)
  local text = fmt:format(...)
  table.insert(self.lines, text)
  return #self.lines
end

---@param ln integer
---@param start integer
---@param len integer
---@param hl_group string
function ComposeBuilder:mark(ln, start, len, hl_group)
  table.insert(self.marks, { line = ln, col = start, end_col = start + len, hl = hl_group })
end

---@param buf integer
---@param comment_start integer
function ComposeBuilder:apply(buf, comment_start)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, self.lines)
  vim.bo[buf].modified = false
  vim.api.nvim_set_current_buf(buf)
  for _, m in ipairs(self.marks) do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, m.line - 1, m.col, {
      end_col = m.end_col,
      hl_group = m.hl,
      priority = 200,
    })
  end
  for i = comment_start, #self.lines do
    vim.api.nvim_buf_set_extmark(buf, compose_ns, i - 1, 0, {
      end_col = #self.lines[i],
      hl_group = 'ForgeComposeComment',
      line_hl_group = 'ForgeComposeComment',
      priority = 150,
    })
  end
end

---@return integer
local function create_compose_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].swapfile = false
  vim.bo[buf].omnifunc = 'v:lua.require("forge.completion").omnifunc'
  return buf
end

local function add_discard_hints(builder)
  builder:add_line('  Write (:w) submits this buffer.')
  builder:add_line('  Quit or delete without ! keeps modified-buffer protection.')
  builder:add_line('  Use :q!, :bd!, or :bwipeout! to discard it.')
end

---@param buf_lines string[]
---@return string[] content_lines
local function extract_content(buf_lines)
  local content_lines = {}
  for _, l in ipairs(buf_lines) do
    if l:match('^<!--') then
      break
    end
    table.insert(content_lines, l)
  end
  return content_lines
end

---@class forge.CommentMetadata
---@field labels string[]
---@field assignees string[]
---@field milestone string
---@field draft boolean
---@field reviewers string[]

---@param buf_lines string[]
---@return forge.CommentMetadata
local function parse_comment_metadata(buf_lines)
  local in_comment = false
  local meta = { labels = {}, assignees = {}, milestone = '', draft = false, reviewers = {} }
  for _, l in ipairs(buf_lines) do
    if l:match('^<!--') then
      in_comment = true
    elseif l:match('^%-%->') then
      break
    elseif in_comment then
      local dv = l:match('^%s*Draft:%s*(.*)$')
      if dv then
        dv = vim.trim(dv):lower()
        meta.draft = dv == 'yes' or dv == 'true'
      end
      local rv = l:match('^%s*Reviewers:%s*(.*)$')
      if rv then
        for r in vim.trim(rv):gmatch('[^,%s]+') do
          table.insert(meta.reviewers, r)
        end
      end
      local lv = l:match('^%s*Labels:%s*(.*)$')
      if lv then
        for label in vim.trim(lv):gmatch('[^,%s]+') do
          table.insert(meta.labels, label)
        end
      end
      local av = l:match('^%s*Assignees:%s*(.*)$')
      if av then
        for assignee in vim.trim(av):gmatch('[^,%s]+') do
          table.insert(meta.assignees, assignee)
        end
      end
      local mv = l:match('^%s*Milestone:%s*(.*)$')
      if mv then
        meta.milestone = vim.trim(mv)
      end
    end
  end
  return meta
end

---@param f forge.Forge
---@param branch string
---@param title string
---@param body string
---@param pr_base string
---@param pr_draft boolean
---@param pr_reviewers string[]?
---@param pr_labels string[]?
---@param pr_assignees string[]?
---@param pr_milestone string?
---@param buf integer?
---@param ref? forge.Scope
---@param push_target string?
local function push_and_create(
  f,
  branch,
  title,
  body,
  pr_base,
  pr_draft,
  pr_reviewers,
  pr_labels,
  pr_assignees,
  pr_milestone,
  buf,
  ref,
  push_target
)
  local log = require('forge.logger')
  log.info('pushing and creating ' .. f.labels.pr_one .. '...')
  vim.system(
    { 'git', 'push', '-u', push_target ~= '' and push_target or 'origin', branch },
    { text = true },
    function(push_result)
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
        f:create_pr_cmd(
          title,
          body,
          pr_base,
          pr_draft,
          pr_reviewers,
          pr_labels,
          pr_assignees,
          pr_milestone,
          ref
        ),
        { text = true },
        function(create_result)
          vim.schedule(function()
            if create_result.code == 0 then
              local url = vim.trim(create_result.stdout or '')
              if url ~= '' then
                vim.fn.setreg('+', url)
              end
              log.info(('created %s -> %s'):format(f.labels.pr_one, url))
              require('forge').clear_list()
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
    end
  )
end

local function submit_issue(f, title, body, labels, assignees, milestone, buf, ref)
  local log = require('forge.logger')
  log.info('creating issue...')
  vim.system(
    f:create_issue_cmd(title, body, labels, assignees, milestone, ref),
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          local url = vim.trim(result.stdout or '')
          if url ~= '' then
            vim.fn.setreg('+', url)
          end
          log.info(('created issue -> %s'):format(url))
          require('forge').clear_list()
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
    end
  )
end

local function update_issue(f, num, title, body, labels, assignees, milestone, original, buf, ref)
  local log = require('forge.logger')
  log.info('updating issue #' .. num .. '...')
  vim.system(
    f:update_issue_cmd(num, title, body, labels, assignees, milestone, original, ref),
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          log.info(('updated issue #%s'):format(num))
          require('forge').clear_list()
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
            msg = 'update failed'
          end
          log.error(msg)
        end
      end)
    end
  )
end

---@param f forge.Forge
---@param result forge.TemplateResult?
---@param ref? forge.Scope
function M.open_issue(f, result, ref)
  local buf = create_compose_buf('forge://issue/new')
  vim.b[buf].forge_scope = ref

  local template_title = result and result.title or ''
  local title_prefix = '# ' .. template_title
  local template_labels = result and result.labels or {}
  local body = result and result.body or ''

  local b = ComposeBuilder.new()
  b.lines = { title_prefix, '' }
  if body ~= '' then
    for _, line in ipairs(vim.split(body, '\n', { plain = true })) do
      table.insert(b.lines, line)
    end
  else
    table.insert(b.lines, '')
  end

  table.insert(b.lines, '')
  local comment_start = #b.lines + 1

  b:add_line('<!--')

  local creating_prefix = '  Creating issue via '
  local ln = b:add_line('%s%s.', creating_prefix, f.name)
  b:mark(ln, #creating_prefix, #f.name, 'ForgeComposeForge')

  b:add_line('')
  local labels_prefix = '  Labels: '
  local labels_val = #template_labels > 0 and table.concat(template_labels, ', ') or ''
  b:add_line('%s%s', labels_prefix, labels_val)

  local assignees_prefix = '  Assignees: '
  b:add_line('%s', assignees_prefix)

  local milestone_prefix = '  Milestone: '
  b:add_line('%s', milestone_prefix)

  b:add_line('')
  add_discard_hints(b)
  b:add_line('  An empty title aborts creation.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = extract_content(buf_lines)
      local issue_title = vim.trim((content_lines[1] or ''):gsub('^#+ *', ''))

      local log = require('forge.logger')
      if
        issue_title == ''
        or template.normalize_body(issue_title) == template.normalize_body(template_title)
      then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local issue_body = vim.trim(table.concat(content_lines, '\n', 3))
      if body ~= '' and template.normalize_body(issue_body) == template.normalize_body(body) then
        log.warn('aborting: body unchanged from template')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local meta = parse_comment_metadata(buf_lines)
      submit_issue(
        f,
        issue_title,
        issue_body,
        meta.labels,
        meta.assignees,
        meta.milestone,
        buf,
        ref
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd.startinsert({ bang = true })
end

function M.open_issue_edit(f, num, details, ref)
  local buf = create_compose_buf(('forge://issue/%s/edit'):format(num))
  vim.b[buf].forge_scope = ref

  local b = ComposeBuilder.new()
  b.lines = { '# ' .. details.title, '' }
  if details.body ~= '' then
    for _, line in ipairs(vim.split(details.body, '\n', { plain = true })) do
      table.insert(b.lines, line)
    end
  else
    table.insert(b.lines, '')
  end

  table.insert(b.lines, '')
  local comment_start = #b.lines + 1

  b:add_line('<!--')

  local editing_prefix = '  Editing issue #' .. num .. ' via '
  local ln = b:add_line('%s%s.', editing_prefix, f.name)
  b:mark(ln, 2, #editing_prefix - 2, 'ForgeComposeHeader')
  b:mark(ln, #editing_prefix, #f.name, 'ForgeComposeForge')

  b:add_line('')
  local labels_prefix = '  Labels: '
  ln = b:add_line('%s%s', labels_prefix, table.concat(details.labels, ', '))
  b:mark(ln, 2, 7, 'ForgeComposeLabel')

  local assignees_prefix = '  Assignees: '
  ln = b:add_line('%s%s', assignees_prefix, table.concat(details.assignees, ', '))
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  local milestone_prefix = '  Milestone: '
  ln = b:add_line('%s%s', milestone_prefix, details.milestone)
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  b:add_line('')
  add_discard_hints(b)
  b:add_line('  An empty title aborts editing.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = extract_content(buf_lines)
      local issue_title = vim.trim((content_lines[1] or ''):gsub('^#+ *', ''))

      local log = require('forge.logger')
      if issue_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local issue_body = vim.trim(table.concat(content_lines, '\n', 3))
      local meta = parse_comment_metadata(buf_lines)
      update_issue(
        f,
        num,
        issue_title,
        issue_body,
        meta.labels,
        meta.assignees,
        meta.milestone,
        details,
        buf,
        ref
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd('normal! v$h')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

---@param f forge.Forge
---@param branch string
---@param base string
---@param draft boolean
---@param tmpl forge.TemplateResult?
---@param ref? forge.Scope
---@param push_target string?
---@param base_ref string?
---@param head_ref string?
function M.open_pr(f, branch, base, draft, tmpl, ref, push_target, base_ref, head_ref)
  base_ref = base_ref or ('origin/' .. base)
  head_ref = head_ref or 'HEAD'
  local title, commit_body = template.fill_from_commits(branch, base_ref, head_ref)
  local body = (tmpl and tmpl.body) or commit_body

  local buf = create_compose_buf('forge://pr/new')
  vim.b[buf].forge_scope = ref

  local b = ComposeBuilder.new()
  b.lines = { '# ' .. title, '' }
  if body ~= '' then
    for _, line in ipairs(vim.split(body, '\n', { plain = true })) do
      table.insert(b.lines, line)
    end
  else
    table.insert(b.lines, '')
  end

  table.insert(b.lines, '')
  local comment_start = #b.lines + 1

  local pr_kind = f.labels.pr_full:gsub('s$', '')
  local diff_stat =
    vim.fn.system('git diff --stat ' .. base_ref .. '..' .. head_ref):gsub('%s+$', '')

  b:add_line('<!--')

  local branch_prefix = '  On branch '
  local against = ' against '
  local ln = b:add_line('%s%s%s%s.', branch_prefix, branch, against, base)
  b:mark(ln, #branch_prefix, #branch, 'ForgeComposeBranch')
  b:mark(ln, #branch_prefix + #branch + #against, #base, 'ForgeComposeBranch')

  local creating_prefix = '  Creating ' .. pr_kind .. ' via '
  ln = b:add_line('%s%s.', creating_prefix, f.name)
  b:mark(ln, 2, #creating_prefix - 2, 'ForgeComposeHeader')
  b:mark(ln, #creating_prefix, #f.name, 'ForgeComposeForge')

  b:add_line('')
  if f.capabilities.draft then
    local draft_val = draft and 'true' or 'false'
    local draft_prefix = '  Draft: '
    ln = b:add_line('%s%s', draft_prefix, draft_val)
    b:mark(ln, 2, 6, 'ForgeComposeLabel')
    b:mark(ln, #draft_prefix, #draft_val, draft and 'ForgeComposeDraft' or 'ForgeDim')
  end

  if f.capabilities.reviewers then
    local reviewers_prefix = '  Reviewers: '
    ln = b:add_line('%s', reviewers_prefix)
    b:mark(ln, 2, 10, 'ForgeComposeLabel')
  end

  local labels_prefix = '  Labels: '
  ln = b:add_line('%s', labels_prefix)
  b:mark(ln, 2, 7, 'ForgeComposeLabel')

  local assignees_prefix = '  Assignees: '
  ln = b:add_line('%s', assignees_prefix)
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  local milestone_prefix = '  Milestone: '
  ln = b:add_line('%s', milestone_prefix)
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  local stat_start, stat_end
  if diff_stat ~= '' then
    b:add_line('')
    local changes_prefix = '  Changes not in '
    ln = b:add_line('%s%s:', changes_prefix, base_ref)
    b:mark(ln, 2, #changes_prefix - 2, 'ForgeComposeHeader')
    b:mark(ln, #changes_prefix, #base_ref, 'ForgeComposeBranch')
    b:add_line('')
    stat_start = #b.lines + 1
    for _, sl in ipairs(vim.split(diff_stat, '\n', { plain = true })) do
      table.insert(b.lines, '  ' .. sl)
    end
    stat_end = #b.lines
  end
  b:add_line('')
  add_discard_hints(b)
  b:add_line('  An empty title or body aborts creation.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  if stat_start and stat_end then
    for i = stat_start, stat_end do
      local line = b.lines[i]
      local pipe = line:find('|')
      if pipe then
        local fname_start = line:find('%S')
        if fname_start then
          b:mark(i, fname_start - 1, pipe - fname_start - 1, 'ForgeComposeFile')
        end
        for pos, run in line:gmatch('()([+-]+)') do
          if pos > pipe then
            local stat_hl = run:sub(1, 1) == '+' and 'ForgeComposeAdded' or 'ForgeComposeRemoved'
            b:mark(i, pos - 1, #run, stat_hl)
          end
        end
      end
    end
    for _, m in ipairs(b.marks) do
      if m.line >= stat_start then
        vim.api.nvim_buf_set_extmark(buf, compose_ns, m.line - 1, m.col, {
          end_col = m.end_col,
          hl_group = m.hl,
          priority = 200,
        })
      end
    end
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = extract_content(buf_lines)
      local pr_title = vim.trim((content_lines[1] or ''):gsub('^#+ *', ''))

      local log = require('forge.logger')
      if pr_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = vim.trim(table.concat(content_lines, '\n', 3))
      if pr_body == '' then
        log.warn('aborting: empty body')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      if body ~= '' and template.normalize_body(pr_body) == template.normalize_body(body) then
        log.warn('aborting: body unchanged from template')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local meta = parse_comment_metadata(buf_lines)
      push_and_create(
        f,
        branch,
        pr_title,
        pr_body,
        base,
        meta.draft,
        meta.reviewers,
        meta.labels,
        meta.assignees,
        meta.milestone,
        buf,
        ref,
        push_target
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd('normal! v$h')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

M.push_and_create = push_and_create

---@param f forge.Forge
---@param num string
---@param title string
---@param body string
---@param pr_draft boolean
---@param original_draft boolean
---@param pr_reviewers string[]?
---@param pr_labels string[]?
---@param pr_assignees string[]?
---@param pr_milestone string?
---@param buf integer?
---@param ref? forge.Scope
local function update_pr(
  f,
  num,
  title,
  body,
  pr_draft,
  original_draft,
  pr_reviewers,
  pr_labels,
  pr_assignees,
  pr_milestone,
  buf,
  ref
)
  local log = require('forge.logger')
  log.info('updating ' .. f.labels.pr_one .. ' #' .. num .. '...')
  vim.system(
    f:update_pr_cmd(num, title, body, pr_reviewers, pr_labels, pr_assignees, pr_milestone, ref),
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local msg = vim.trim(result.stderr or '')
          if msg == '' then
            msg = vim.trim(result.stdout or '')
          end
          if msg == '' then
            msg = 'update failed'
          end
          log.error(msg)
          return
        end
        if pr_draft ~= original_draft then
          local draft_cmd = f:draft_toggle_cmd(num, original_draft, ref)
          if draft_cmd then
            vim.system(draft_cmd, { text = true }, function(dr)
              vim.schedule(function()
                if dr.code ~= 0 then
                  log.warn('updated ' .. f.labels.pr_one .. ' but draft toggle failed')
                else
                  log.info(('updated %s #%s'):format(f.labels.pr_one, num))
                end
              end)
            end)
          else
            log.info(('updated %s #%s'):format(f.labels.pr_one, num))
          end
        else
          log.info(('updated %s #%s'):format(f.labels.pr_one, num))
        end
        require('forge').clear_list()
        if buf and vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modified = false
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end
  )
end

---@param f forge.Forge
---@param num string
---@param details forge.PRDetails
---@param current_branch string
---@param ref? forge.Scope
function M.open_pr_edit(f, num, details, current_branch, ref)
  local buf = create_compose_buf(('forge://pr/%s/edit'):format(num))
  vim.b[buf].forge_scope = ref

  local b = ComposeBuilder.new()
  b.lines = { '# ' .. details.title, '' }
  if details.body ~= '' then
    for _, line in ipairs(vim.split(details.body, '\n', { plain = true })) do
      table.insert(b.lines, line)
    end
  else
    table.insert(b.lines, '')
  end

  table.insert(b.lines, '')
  local comment_start = #b.lines + 1

  local pr_kind = f.labels.pr_full:gsub('s$', '')
  local branch = details.head_branch ~= '' and details.head_branch or current_branch
  local base = details.base_branch ~= '' and details.base_branch or 'main'
  local diff_stat = ''
  if current_branch ~= '' and branch == current_branch then
    diff_stat = vim.fn.system('git diff --stat origin/' .. base .. '..HEAD'):gsub('%s+$', '')
  end

  b:add_line('<!--')

  local branch_prefix = '  On branch '
  local against = ' against '
  local ln = b:add_line('%s%s%s%s.', branch_prefix, branch, against, base)
  b:mark(ln, #branch_prefix, #branch, 'ForgeComposeBranch')
  b:mark(ln, #branch_prefix + #branch + #against, #base, 'ForgeComposeBranch')

  local editing_prefix = '  Editing ' .. pr_kind .. ' #' .. num .. ' via '
  ln = b:add_line('%s%s.', editing_prefix, f.name)
  b:mark(ln, 2, #editing_prefix - 2, 'ForgeComposeHeader')
  b:mark(ln, #editing_prefix, #f.name, 'ForgeComposeForge')

  b:add_line('')
  local original_draft = details.draft
  if f.capabilities.draft then
    local draft_val = details.draft and 'true' or 'false'
    local draft_prefix = '  Draft: '
    ln = b:add_line('%s%s', draft_prefix, draft_val)
    b:mark(ln, 2, 6, 'ForgeComposeLabel')
    b:mark(ln, #draft_prefix, #draft_val, details.draft and 'ForgeComposeDraft' or 'ForgeDim')
  end

  if f.capabilities.reviewers then
    local reviewers_prefix = '  Reviewers: '
    local reviewers_val = table.concat(details.reviewers, ', ')
    ln = b:add_line('%s%s', reviewers_prefix, reviewers_val)
    b:mark(ln, 2, 10, 'ForgeComposeLabel')
  end

  local labels_prefix = '  Labels: '
  local labels_val = table.concat(details.labels, ', ')
  ln = b:add_line('%s%s', labels_prefix, labels_val)
  b:mark(ln, 2, 7, 'ForgeComposeLabel')

  local assignees_prefix = '  Assignees: '
  local assignees_val = table.concat(details.assignees, ', ')
  ln = b:add_line('%s%s', assignees_prefix, assignees_val)
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  local milestone_prefix = '  Milestone: '
  ln = b:add_line('%s%s', milestone_prefix, details.milestone)
  b:mark(ln, 2, 10, 'ForgeComposeLabel')

  local stat_start, stat_end
  if diff_stat ~= '' then
    b:add_line('')
    local changes_prefix = '  Changes not in origin/'
    ln = b:add_line('%s%s:', changes_prefix, base)
    b:mark(ln, 2, #changes_prefix - 2, 'ForgeComposeHeader')
    b:mark(ln, #changes_prefix, #base, 'ForgeComposeBranch')
    b:add_line('')
    stat_start = #b.lines + 1
    for _, sl in ipairs(vim.split(diff_stat, '\n', { plain = true })) do
      table.insert(b.lines, '  ' .. sl)
    end
    stat_end = #b.lines
  end
  b:add_line('')
  add_discard_hints(b)
  b:add_line('  An empty title or body aborts editing.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  if stat_start and stat_end then
    for i = stat_start, stat_end do
      local line = b.lines[i]
      local pipe = line:find('|')
      if pipe then
        local fname_start = line:find('%S')
        if fname_start then
          b:mark(i, fname_start - 1, pipe - fname_start - 1, 'ForgeComposeFile')
        end
        for pos, run in line:gmatch('()([+-]+)') do
          if pos > pipe then
            local stat_hl = run:sub(1, 1) == '+' and 'ForgeComposeAdded' or 'ForgeComposeRemoved'
            b:mark(i, pos - 1, #run, stat_hl)
          end
        end
      end
    end
    for _, m in ipairs(b.marks) do
      if m.line >= stat_start then
        vim.api.nvim_buf_set_extmark(buf, compose_ns, m.line - 1, m.col, {
          end_col = m.end_col,
          hl_group = m.hl,
          priority = 200,
        })
      end
    end
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content_lines = extract_content(buf_lines)
      local pr_title = vim.trim((content_lines[1] or ''):gsub('^#+ *', ''))

      local log = require('forge.logger')
      if pr_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = vim.trim(table.concat(content_lines, '\n', 3))
      if pr_body == '' then
        log.warn('aborting: empty body')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      local meta = parse_comment_metadata(buf_lines)
      update_pr(
        f,
        num,
        pr_title,
        pr_body,
        meta.draft,
        original_draft,
        meta.reviewers,
        meta.labels,
        meta.assignees,
        meta.milestone,
        buf,
        ref
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd('normal! v$h')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

return M
