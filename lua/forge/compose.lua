local M = {}

local submission = require('forge.submission')
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
  return buf
end

local function add_discard_hints(builder)
  builder:add_line('  Write (:w) submits this buffer.')
  builder:add_line('  Quit or delete without ! keeps modified-buffer protection.')
  builder:add_line('  Use :q!, :bd!, or :bwipeout! to discard it.')
end

local function set_clipboard(text)
  local ok = pcall(vim.fn.setreg, '+', text)
  if not ok then
    pcall(vim.fn.setreg, '"', text)
  end
end

local function is_comment_opener(line)
  return vim.trim(line or '') == '<!--'
end

local function is_comment_closer(line)
  return vim.trim(line or '') == '-->'
end

---@param buf_lines string[]
---@return string[] content_lines
local function extract_content(buf_lines)
  local content_lines = {}
  for _, l in ipairs(buf_lines) do
    if is_comment_opener(l) then
      break
    end
    table.insert(content_lines, l)
  end
  return content_lines
end

local function parse_comment_metadata(buf_lines)
  local in_comment = false
  local meta = { labels = {}, assignees = {}, milestone = '', draft = false, reviewers = {} }
  for _, l in ipairs(buf_lines) do
    if is_comment_opener(l) then
      in_comment = true
    elseif is_comment_closer(l) then
      break
    elseif in_comment then
      local draft = l:match('^%s*Draft:%s*(.*)$')
      if draft then
        draft = vim.trim(draft):lower()
        meta.draft = draft == 'yes' or draft == 'true'
      end

      local reviewers = l:match('^%s*Reviewers:%s*(.*)$')
      if reviewers then
        for reviewer in vim.trim(reviewers):gmatch('[^,%s]+') do
          table.insert(meta.reviewers, reviewer)
        end
      end

      local labels = l:match('^%s*Labels:%s*(.*)$')
      if labels then
        for label in vim.trim(labels):gmatch('[^,%s]+') do
          table.insert(meta.labels, label)
        end
      end

      local assignees = l:match('^%s*Assignees:%s*(.*)$')
      if assignees then
        for assignee in vim.trim(assignees):gmatch('[^,%s]+') do
          table.insert(meta.assignees, assignee)
        end
      end

      local milestone = l:match('^%s*Milestone:%s*(.*)$')
      if milestone then
        meta.milestone = vim.trim(milestone)
      end
    end
  end
  return meta
end

local function extract_submission(buf_lines)
  local content_lines = extract_content(buf_lines)
  return {
    title = vim.trim((content_lines[1] or ''):gsub('^#+ *', '')),
    body = vim.trim(table.concat(content_lines, '\n', 3)),
    metadata = parse_comment_metadata(buf_lines),
  }
end

local function add_metadata_line(builder, label, value, value_hl)
  local prefix = '  ' .. label .. ': '
  local ln = builder:add_line('%s%s', prefix, value or '')
  builder:mark(ln, 2, #label, 'ForgeComposeLabel')
  if value_hl and value and value ~= '' then
    builder:mark(ln, #prefix, #value, value_hl)
  end
  return ln
end

local function add_metadata_fields(builder, forge, kind, operation, metadata)
  local fields = submission.fields(forge, kind, operation)
  for _, field in ipairs(fields) do
    if field == 'draft' then
      local draft = metadata.draft == true
      local value_hl = draft and 'ForgeComposeDraft' or 'ForgeDim'
      add_metadata_line(builder, 'Draft', draft and 'true' or 'false', value_hl)
    elseif field == 'reviewers' then
      local reviewers = table.concat(metadata.reviewers or {}, ', ')
      if reviewers ~= '' then
        add_metadata_line(builder, 'Reviewers', reviewers)
      end
    elseif field == 'labels' then
      local labels = table.concat(metadata.labels or {}, ', ')
      if labels ~= '' then
        add_metadata_line(builder, 'Labels', labels)
      end
    elseif field == 'assignees' then
      local assignees = table.concat(metadata.assignees or {}, ', ')
      if assignees ~= '' then
        add_metadata_line(builder, 'Assignees', assignees)
      end
    elseif field == 'milestone' then
      local milestone = metadata.milestone or ''
      if milestone ~= '' then
        add_metadata_line(builder, 'Milestone', milestone)
      end
    end
  end
end

local function add_optional_metadata_fields(builder, forge, kind, operation, metadata)
  local before = #builder.lines
  builder:add_line('')
  add_metadata_fields(builder, forge, kind, operation, metadata)
  if #builder.lines == before + 1 then
    table.remove(builder.lines, #builder.lines)
    return false
  end
  return true
end

local function add_section_gap(builder)
  if builder.lines[#builder.lines] ~= '' then
    builder:add_line('')
  end
end

local function add_pr_header(builder, prefix, forge_name, branch, base)
  local ln = builder:add_line('%s%s.', prefix, forge_name)
  builder:mark(ln, 2, #prefix - 2, 'ForgeComposeHeader')
  builder:mark(ln, #prefix, #forge_name, 'ForgeComposeForge')

  local branch_prefix = '  On branch '
  local against = ' against '
  ln = builder:add_line('%s%s%s%s.', branch_prefix, branch, against, base)
  builder:mark(ln, #branch_prefix, #branch, 'ForgeComposeBranch')
  builder:mark(ln, #branch_prefix + #branch + #against, #base, 'ForgeComposeBranch')
end

---@param f forge.Forge
---@param branch string
---@param title string
---@param body string
---@param pr_base string
---@param pr_draft boolean
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
  buf,
  ref,
  push_target,
  metadata
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
        f:create_pr_cmd(title, body, pr_base, pr_draft, ref, metadata),
        { text = true },
        function(create_result)
          vim.schedule(function()
            if create_result.code == 0 then
              local url = vim.trim(create_result.stdout or '')
              if url ~= '' then
                set_clipboard(url)
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

local function submit_issue(f, title, body, labels, buf, ref, metadata)
  local log = require('forge.logger')
  log.info('creating issue...')
  vim.system(
    f:create_issue_cmd(title, body, labels, ref, metadata),
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          local url = vim.trim(result.stdout or '')
          if url ~= '' then
            set_clipboard(url)
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

local function update_issue(f, num, title, body, buf, ref, metadata, previous)
  local log = require('forge.logger')
  log.info('updating issue #' .. num .. '...')
  vim.system(
    f:update_issue_cmd(num, title, body, ref, metadata, previous),
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
  local template_assignees = result and result.assignees or {}
  local body = result and result.body or ''
  local template_metadata = {
    labels = template_labels,
    assignees = template_assignees,
    milestone = '',
    draft = false,
    reviewers = {},
  }

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

  add_optional_metadata_fields(b, f, 'issue', 'create', template_metadata)
  add_section_gap(b)
  add_discard_hints(b)
  b:add_line('  An empty title aborts creation.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local submission_data = extract_submission(buf_lines)
      local issue_title = submission_data.title

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
      local issue_body = submission_data.body
      if body ~= '' and template.normalize_body(issue_body) == template.normalize_body(body) then
        log.warn('aborting: body unchanged from template')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      submit_issue(f, issue_title, issue_body, template_labels, buf, ref, submission_data.metadata)
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

  add_optional_metadata_fields(b, f, 'issue', 'update', submission.issue_metadata(details))
  add_section_gap(b)
  add_discard_hints(b)
  b:add_line('  An empty title aborts editing.')
  b:add_line('-->')

  b:apply(buf, comment_start)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local submission_data = extract_submission(buf_lines)
      local issue_title = submission_data.title

      local log = require('forge.logger')
      if issue_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      update_issue(
        f,
        num,
        issue_title,
        submission_data.body,
        buf,
        ref,
        submission_data.metadata,
        submission.issue_metadata(details)
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
  local draft_metadata = {
    labels = {},
    assignees = {},
    milestone = '',
    draft = draft == true,
    reviewers = {},
  }

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

  add_pr_header(b, '  Creating ' .. pr_kind .. ' via ', f.name, branch, base)

  add_optional_metadata_fields(b, f, 'pr', 'create', draft_metadata)

  local stat_start, stat_end
  if diff_stat ~= '' then
    add_section_gap(b)
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
  add_section_gap(b)
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
      local submission_data = extract_submission(buf_lines)
      local pr_title = submission_data.title

      local log = require('forge.logger')
      if pr_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = submission_data.body
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

      push_and_create(
        f,
        branch,
        pr_title,
        pr_body,
        base,
        draft,
        buf,
        ref,
        push_target,
        submission_data.metadata
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd('normal! v$h')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

M._extract_content = extract_content
M._parse_comment_metadata = parse_comment_metadata
M._extract_submission = extract_submission

M.push_and_create = push_and_create

---@param f forge.Forge
---@param num string
---@param title string
---@param body string
---@param buf integer?
---@param ref? forge.Scope
local function update_pr(f, num, title, body, buf, ref, metadata, previous)
  local log = require('forge.logger')
  log.info('updating ' .. f.labels.pr_one .. ' #' .. num .. '...')
  vim.system(
    f:update_pr_cmd(num, title, body, ref, metadata, previous),
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
        if
          submission.supports(f, 'pr', 'update', 'draft')
          and previous
          and previous.draft ~= metadata.draft
          and f.draft_toggle_cmd
        then
          local draft_cmd = f:draft_toggle_cmd(num, previous.draft, ref)
          if draft_cmd then
            vim.system(draft_cmd, { text = true }, function(draft_result)
              vim.schedule(function()
                if draft_result.code ~= 0 then
                  local msg = vim.trim(draft_result.stderr or '')
                  if msg == '' then
                    msg = vim.trim(draft_result.stdout or '')
                  end
                  if msg == '' then
                    msg = 'draft toggle failed'
                  end
                  log.error(msg)
                end
              end)
            end)
          end
        end
        log.info(('updated %s #%s'):format(f.labels.pr_one, num))
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

  add_pr_header(b, '  Editing ' .. pr_kind .. ' #' .. num .. ' via ', f.name, branch, base)

  add_optional_metadata_fields(b, f, 'pr', 'update', submission.pr_metadata(details))

  local stat_start, stat_end
  if diff_stat ~= '' then
    add_section_gap(b)
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
  add_section_gap(b)
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
      local submission_data = extract_submission(buf_lines)
      local pr_title = submission_data.title

      local log = require('forge.logger')
      if pr_title == '' then
        log.warn('aborting: empty title')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end
      local pr_body = submission_data.body
      if pr_body == '' then
        log.warn('aborting: empty body')
        vim.bo[buf].modified = false
        vim.api.nvim_buf_delete(buf, { force = true })
        return
      end

      update_pr(
        f,
        num,
        pr_title,
        pr_body,
        buf,
        ref,
        submission_data.metadata,
        submission.pr_metadata(details)
      )
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd('normal! v$h')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-G>', true, false, true), 'n', false)
end

return M
