local gh = require('forge.gh')
local log = require('forge.log')
local map = require('forge.map')
local template = require('forge.template')
local uri = require('forge.uri')
local view = require('forge.view')

local M = {}

local NS = vim.api.nvim_create_namespace('forge.compose')

--- What github writes for an optional answer left blank, so that an issue
--- filed from here is indistinguishable from one filed on the web.
local NO_RESPONSE = '_No response_'

--- What a pull request would merge into, when nobody said otherwise.
local BASE_QUERY = [[
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) { defaultBranchRef { name } }
}
]]

--- @param lines string[]
--- @param text string?
local function append(lines, text)
  for _, line in ipairs(vim.split(text or '', '\n', { plain = true })) do
    lines[#lines + 1] = line
  end
end

--- Guidance is virtual, never text.
---
--- A form's prose belongs on screen but not in the issue, and github drops it
--- when rendering a submission. Holding it as virtual lines means there is
--- nothing to strip on the way out, and so nothing that can strip too much.
--- @param marks table[]
--- @param row integer
--- @param text string?
local function guide(marks, row, text)
  if not text or text == '' then
    return
  end
  local virt = {}
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    virt[#virt + 1] = { { line, 'Comment' } }
  end
  marks[#marks + 1] = { row, 0, { virt_lines = virt, virt_lines_above = true } }
end

--- @param marks table[]
--- @param row integer
local function required_here(marks, row)
  marks[#marks + 1] = { row, 0, { virt_text = { { ' *', 'DiagnosticError' } } } }
end

--- Turn a template into the markdown it will be submitted as.
---
--- The buffer is the body, not a form over it, so what is written is what is
--- filed. Only two things are added on submit: a blank optional answer becomes
--- `_No response_`, and nothing else moves.
--- @param found forge.Template
--- @return string[] lines
--- @return table[] marks
function M.skeleton(found)
  local lines = { found.title or '', '' }
  local marks = {}

  guide(marks, #lines, found.guidance[0])

  if not found.fields then
    append(lines, found.body)
    return lines, marks
  end

  for index, field in ipairs(found.fields) do
    guide(marks, #lines, found.guidance[index])
    lines[#lines + 1] = '### ' .. field.label
    if field.required then
      required_here(marks, #lines - 1)
    end
    lines[#lines + 1] = ''

    if field.kind == 'checkboxes' then
      for at, option in ipairs(field.options or {}) do
        lines[#lines + 1] = '- [ ] ' .. option
        if (field.required_options or {})[at] then
          required_here(marks, #lines - 1)
        end
      end
    elseif field.render then
      lines[#lines + 1] = '```' .. field.render
      append(lines, field.value)
      lines[#lines + 1] = '```'
    elseif field.kind == 'dropdown' and field.default and field.options then
      lines[#lines + 1] = field.options[field.default + 1] or ''
    elseif field.value then
      append(lines, field.value)
    end
    lines[#lines + 1] = ''
  end

  return lines, marks
end

--- The answer written under each heading.
--- @param lines string[]
--- @return table<string, string>
local function answers(lines)
  local found, label, body = {}, nil, {}
  for index = 2, #lines do
    local heading = lines[index]:match('^###%s+(.*)$')
    if heading then
      if label then
        found[label] = vim.trim(table.concat(body, '\n'))
      end
      label, body = vim.trim(heading), {}
    elseif label then
      body[#body + 1] = lines[index]
    end
  end
  if label then
    found[label] = vim.trim(table.concat(body, '\n'))
  end
  return found
end

--- What would be filed, or why it cannot be.
---
--- A form's answers are reassembled rather than sent as typed, because github
--- writes `_No response_` under a heading left blank and an issue filed from
--- here should read the same as one filed on the web.
--- @param lines string[]
--- @param fields forge.Field[]?
--- @return string? title
--- @return string? body
--- @return string? err
function M.contents(lines, fields)
  local title = vim.trim(lines[1] or '')
  if title == '' then
    return nil, nil, 'a title is the one thing github will not invent'
  end

  fields = fields or {}
  if #fields == 0 then
    return title, vim.trim(table.concat(vim.list_slice(lines, 2), '\n'))
  end

  local written = answers(lines)
  for _, field in ipairs(fields) do
    if field.required and (written[field.label] or '') == '' then
      return nil, nil, ('%s is required'):format(field.label)
    end
  end

  local body = {}
  for _, field in ipairs(fields) do
    body[#body + 1] = '### ' .. field.label
    body[#body + 1] = ''
    body[#body + 1] = written[field.label] ~= '' and written[field.label] or NO_RESPONSE
    body[#body + 1] = ''
  end
  return title, vim.trim(table.concat(body, '\n'))
end

--- @param buf integer
local function submit(buf)
  local state = vim.b[buf].forge_compose
  if not state then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local title, body, err = M.contents(lines, state.fields)
  if not title then
    return log.warn(err or 'nothing to file')
  end
  vim.bo[buf].modified = false

  local variables = { title = title, body = body }
  local what = 'issues'
  if state.collection == 'prs' then
    what = 'pulls'
    variables.head = state.head
    variables.base = state.base
  else
    if #state.labels > 0 then
      variables.labels = state.labels
    end
    if #state.assignees > 0 then
      variables.assignees = state.assignees
    end
  end

  gh.rest({
    desc = ('filing in %s/%s'):format(state.owner, state.repo),
    method = 'POST',
    path = ('repos/%s/%s/%s'):format(state.owner, state.repo, what),
    variables = variables,
    cwd = state.cwd,
  }, function(created)
    if not created.number then
      return
    end
    log.info(('#%d filed'):format(created.number))
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    view.open({
      owner = state.owner,
      repo = state.repo,
      collection = state.collection,
      number = created.number,
    }, { cwd = state.cwd })
  end, function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modified = true
    if vim.fn.bufwinid(buf) == -1 then
      vim.api.nvim_win_set_buf(0, buf)
    end
  end)
end

--- @param u forge.Uri
--- @param found forge.Template?
--- @param o forge.Open
--- @param refs { head: string, base: string }? which branches a pull request joins
local function open_buffer(u, found, o, refs)
  view.place(o)

  local name = uri.tostring(u)
  local buf = view.buffer_named(name)
  if not buf then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
  end

  local lines, marks = M.skeleton(found or { name = '', path = '', labels = {}, guidance = {} })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, NS, mark[1], mark[2], mark[3])
  end

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modified = false

  vim.b[buf].forge_compose = {
    owner = u.owner,
    repo = u.repo,
    collection = u.collection,
    labels = found and found.labels or {},
    assignees = found and found.assignees or {},
    fields = found and found.fields or {},
    template = found and vim.fs.basename(found.path) or nil,
    head = refs and refs.head or nil,
    base = refs and refs.base or nil,
    cwd = o.cwd,
  }

  map.buf_default(buf, 'n', 'g?', '<Plug>(forge-help)', 'what the keys in this buffer do')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the list this item is in')
  map.buf_default(buf, 'n', 'gX', '<Plug>(forge-web)', 'open this view on github.com')

  local bar = {
    view.hl('Title', u.collection == 'prs' and 'PR' or 'ISSUE'),
    view.hl('Tag', 'new'),
    view.hl('Directory', ('%s/%s'):format(view.escape(u.owner), view.escape(u.repo))),
  }
  if refs then
    bar[#bar + 1] = view.hl('Comment', view.escape(refs.head) .. ' into ' .. view.escape(refs.base))
  end
  local winbar = table.concat(bar, ' ')

  vim.api.nvim_win_set_buf(0, buf)
  vim.b[buf].forge_winbar = winbar
  vim.wo.winbar = winbar

  vim.api.nvim_clear_autocmds({ event = 'BufWriteCmd', buffer = buf })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      submit(buf)
    end,
  })

  local title = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
  vim.api.nvim_win_set_cursor(0, { 1, #title })
  if title ~= '' then
    vim.cmd('startinsert!')
  end
end

--- @param u forge.Uri
--- @param o forge.Open
--- @param refs { head: string, base: string }?
local function choose(u, o, refs)
  local found, err = template.all(u.collection, o.cwd)
  if err then
    log.warn(err)
  end
  if #found <= 1 then
    return open_buffer(u, found[1], o, refs)
  end

  local choices = {}
  for index, one in ipairs(found) do
    choices[index] = one.name
  end
  choices[#choices + 1] = 'Blank'

  vim.ui.select(choices, { prompt = 'Template' }, function(_, index)
    if not index then
      return
    end
    open_buffer(u, found[index], o, refs)
  end)
end

--- Start something new in the collection being looked at.
---
--- Templates come from the checkout, so a repository you are only browsing
--- offers none and the buffer starts empty. One template is used without
--- asking; several are chosen from; cancelling chooses nothing.
---
--- A pull request also needs two branches. The one you are on is the one you
--- are proposing, and github is asked what it would be merged into, since a
--- repository's default branch is not ours to guess.
--- @param o forge.Open?
function M.start(o)
  local u = view.current()
  if not u or u.draft then
    return
  end
  o = o or {}
  o.cwd = o.cwd or require('forge.vcs').dir()

  local draft = {
    owner = u.owner,
    repo = u.repo,
    collection = u.collection,
    draft = true,
  } --[[@as forge.Uri]]

  if u.collection ~= 'prs' then
    return choose(draft, o)
  end

  local head, err = require('forge.vcs').branch(o.cwd)
  if not head then
    return log.err(err or 'no branch here, so no pull request to open')
  end

  gh.graphql({
    desc = ('what %s/%s merges into'):format(u.owner, u.repo),
    query = BASE_QUERY,
    variables = { owner = u.owner, repo = u.repo },
    cwd = o.cwd,
  }, function(data)
    local base = vim.tbl_get(data, 'repository', 'defaultBranchRef', 'name')
    if not base then
      return log.err('cannot tell which branch to merge into')
    end
    if base == head then
      return log.err(
        ('%s is what would be merged into, so there is nothing to propose'):format(head)
      )
    end
    choose(draft, o, { head = head, base = base })
  end)
end

return M
