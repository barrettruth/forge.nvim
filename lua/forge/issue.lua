local gh = require('forge.gh')
local log = require('forge.log')
local uri = require('forge.uri')

local M = {}

local LIST_QUERY = [[
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    issues(first: 100, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      nodes { number title comments { totalCount } }
    }
  }
}
]]

local ISSUE_QUERY = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      number title state body createdAt
      author { login }
      authorAssociation
      labels(first: 20) { totalCount nodes { name } }
      comments(first: 100) {
        totalCount
        nodes { author { login } authorAssociation createdAt body }
      }
    }
  }
}
]]

--- @param iso string?
--- @return string
local function age(iso)
  if not iso then
    return 'unknown'
  end
  local year, month, day = iso:match('^(%d+)-(%d+)-(%d+)')
  if not year then
    return iso
  end
  local then_ = os.time({
    year = assert(tonumber(year)),
    month = assert(tonumber(month)),
    day = assert(tonumber(day)),
  })
  local days = math.floor(os.difftime(os.time(), then_) / 86400)
  if days <= 0 then
    return 'today'
  elseif days == 1 then
    return 'yesterday'
  elseif days < 30 then
    return days .. ' days ago'
  end
  return math.floor(days / 30) .. ' months ago'
end

--- @param lines string[]
--- @param body string?
local function append_body(lines, body)
  for _, line in ipairs(vim.split(vim.trim(body or ''), '\n', { plain = true })) do
    lines[#lines + 1] = line
  end
end

--- Show `lines` as the view named by `u`, reusing its buffer if it exists.
---
--- A single issue is markdown, because that is what GitHub gave us and
--- markdown already knows how to draw it. A list is not markdown, so it gets a
--- filetype of its own.
---
--- Mappings are set here rather than in an ftplugin: a viewer is markdown, and
--- an ftplugin/markdown.lua would reach every markdown file you open.
---
--- The buffer is replaced in place rather than wiped and rebuilt, so a window
--- handle held by a caller stays valid across a refresh.
--- @param u forge.Uri
--- @param lines string[]
--- @return integer buf
local function render(u, lines)
  local name = uri.tostring(u)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = u.kind == 'issue' and 'markdown' or 'forge'

  local map = require('forge.map')
  map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the issue list')
  if u.kind == 'issues' then
    map.buf_default(buf, 'n', '<CR>', '<Plug>(forge-issue-open)', 'open the issue under the cursor')
  end

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

--- @param u forge.Uri
local function open_list(u)
  local desc = ('%s/%s issues'):format(u.owner, u.repo)
  gh.graphql(desc, LIST_QUERY, { owner = u.owner, repo = u.repo }, function(data)
    local issues = vim.tbl_get(data, 'repository', 'issues')
    if not issues then
      log.err(('no such repository: %s/%s'):format(u.owner, u.repo))
      return
    end
    local lines = {}
    for _, issue in ipairs(issues.nodes or {}) do
      local comments = issue.comments and issue.comments.totalCount or 0
      lines[#lines + 1] = ('#%-6d %s%s'):format(
        issue.number,
        issue.title,
        comments > 0 and ('  (%d)'):format(comments) or ''
      )
    end
    if #lines == 0 then
      lines = { 'No open issues.' }
    end
    render(u, lines)
    gh.check_truncated(issues, 'issues')
  end)
end

--- @param u forge.Uri
local function open_issue(u)
  gh.graphql(
    ('%s/%s#%d'):format(u.owner, u.repo, u.number),
    ISSUE_QUERY,
    { owner = u.owner, repo = u.repo, number = u.number },
    function(data)
      local issue = vim.tbl_get(data, 'repository', 'issue')
      if not issue then
        log.err(('no such issue: %s/%s#%d'):format(u.owner, u.repo, u.number))
        return
      end

      local labels = {}
      for _, label in ipairs(vim.tbl_get(issue, 'labels', 'nodes') or {}) do
        labels[#labels + 1] = label.name
      end

      local lines = {
        ('# %s #%d'):format(issue.title, issue.number),
        '',
        ('- Author: %s (%s)'):format(
          vim.tbl_get(issue, 'author', 'login') or 'ghost',
          issue.authorAssociation or 'NONE'
        ),
        ('- State: %s, opened %s'):format(issue.state or '?', age(issue.createdAt)),
      }
      if #labels > 0 then
        lines[#lines + 1] = ('- Labels: %s'):format(table.concat(labels, ', '))
      end
      lines[#lines + 1] = ''
      append_body(lines, issue.body)

      local comments = issue.comments or {}
      local nodes = comments.nodes or {}
      if #nodes > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('## Comments (%d)'):format(comments.totalCount or #nodes)
        for _, comment in ipairs(nodes) do
          lines[#lines + 1] = ''
          lines[#lines + 1] = ('*%s (%s) — %s*'):format(
            vim.tbl_get(comment, 'author', 'login') or 'ghost',
            comment.authorAssociation or 'NONE',
            age(comment.createdAt)
          )
          lines[#lines + 1] = ''
          append_body(lines, comment.body)
        end
      end

      render(u, lines)
      gh.check_truncated(comments, 'comments')
    end
  )
end

--- Open whatever `target` names.
--- @param target string?
function M.open(target)
  local u, err = uri.resolve(target)
  if not u then
    log.err(err or 'cannot resolve target')
    return
  end
  if u.kind == 'issue' then
    open_issue(u)
  else
    open_list(u)
  end
end

--- Leave an issue for the list it belongs to.
---
--- The list is the top: there is nothing above it to go up to.
function M.up()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u or u.kind ~= 'issue' then
    return
  end
  open_list({ owner = u.owner, repo = u.repo, kind = 'issues' })
end

--- Open the issue under the cursor in an issue list.
function M.open_at_cursor()
  local u = uri.parse(vim.api.nvim_buf_get_name(0))
  if not u or u.kind ~= 'issues' then
    return
  end
  local number = vim.api.nvim_get_current_line():match('^#(%d+)')
  if not number then
    return
  end
  open_issue({ owner = u.owner, repo = u.repo, kind = 'issue', number = tonumber(number) })
end

return M
