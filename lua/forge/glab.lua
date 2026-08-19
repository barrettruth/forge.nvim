--- gitlab, as forge.Backend asks for it: the requests it makes, the words it
--- says them in, and the shape it hands back.
---
--- Everything goes through `glab api`, gitlab's REST API with an authenticated
--- host attached. A project is a percent-encoded path, not an owner and a
--- name. A change is a method and a body, not a document. A view is several
--- small requests, not one large one. The transport is ci.nvim's.

local log = require('forge.log')
local stack = require('forge.stack')

local M = {}

--- gitlab numbers merge requests apart from issues and writes "!" in front of
--- one.
--- @type table<forge.Collection, forge.Nouns>
M.nouns = {
  issues = { one = 'issue', many = 'issues', item = 'ISSUE', list = 'ISSUES', sigil = '#' },
  prs = {
    one = 'merge request',
    many = 'merge requests',
    item = 'MR',
    list = 'MRS',
    sigil = '!',
  },
}

--- What gitlab calls a collection in an api path and in a web address alike.
local PATH = { issues = 'issues', prs = 'merge_requests' }

--- How many a list asks for at once. Must match forge.view's PER_PAGE. The
--- pager divides a total by that to count the pages.
local PER_PAGE = 100

--- gitlab's own access levels, at the two points it lets somebody who did not
--- write an issue or a merge request change it.
local REPORTER, DEVELOPER = 20, 30

--- @param s string
--- @return string
local function enc(s)
  return (s:gsub('[^%w%-%._~]', function(c)
    return ('%%%02X'):format(c:byte())
  end))
end

--- How gitlab addresses a project: its full path with every slash escaped,
--- The whole path occupies one segment of the api path. glab's `:fullpath`
--- placeholder stands in where nothing named a project. ci.nvim's.
--- @param project string? the full path, as the forge spells it
--- @return string
function M.path(project)
  return (project and project ~= '') and enc(project) or ':fullpath'
end

--- What gitlab said, if `s` is one of its error envelopes.
--- @param s string
--- @return string?
local function said(s)
  local ok, body = pcall(vim.json.decode, s)
  if not ok or type(body) ~= 'table' then
    return nil
  end
  if type(body.message) == 'string' then
    return body.message
  end
  return type(body.error) == 'string' and body.error or nil
end

--- `glab api` writes gitlab's answer to stdout and its own "glab: … (HTTP
--- 404)" line to stderr. The body is read first: same sentence, no prefix.
--- ci.nvim's.
--- @param out vim.SystemCompleted
--- @return string
local function errmsg(out)
  local body, err = vim.trim(out.stdout or ''), vim.trim(out.stderr or '')
  local why = said(body) or said(err) or (err ~= '' and err or body)
  if why == '' then
    why = ('glab exited with code %d'):format(out.code)
  end
  return (why:gsub('%s+$', ''))
end

--- Absent rather than `vim.NIL`, as forge.gh does. Objects only. A null
--- dropped from a list leaves a hole `ipairs` stops at.
local DECODE = { luanil = { object = true } }

--- @param text string
--- @return table?
local function decoded(text)
  local ok, body = pcall(vim.json.decode, text, DECODE)
  return (ok and type(body) == 'table') and body or nil
end

--- Split `glab api --include` output into headers and body. The only way to
--- see `X-Total`, where gitlab puts the size of a list.
--- @param out string
--- @return table<string, string> headers by lowercased name
--- @return string body
local function headed(out)
  local head, body = out:match('^(.-)\r?\n\r?\n(.*)$')
  if not head then
    return {}, out
  end
  local headers = {}
  for line in vim.gsplit(head, '\r?\n') do
    local name, value = line:match('^([%w-]+):%s*(.-)%s*$')
    if name then
      headers[name:lower()] = value
    end
  end
  return headers, body
end

--- One call to `glab api`.
--- @class forge.glab.Call
--- @field path string the api path, with the project already encoded into it
--- @field cwd string? where to run glab, which is where it resolves a remote
--- @field host string? which instance to ask, since a buffer may be read from
--- outside the repository it came from
--- @field method 'POST'|'PUT'? anything that is not a plain read
--- @field body table? sent as a json document: `-f` spells a nested key
--- literally and gitlab drops it without a word
--- @field include boolean? ask for the response headers as well as the body
--- @field all boolean? every page of a list rather than the first

--- What one came back with.
--- @class forge.glab.Answer
--- @field body table
--- @field headers table<string, string> empty unless the call asked for them

--- Make one request. Never through a pty: glab spends five seconds a call
--- waiting for a terminal background-colour reply that never arrives.
--- @param call forge.glab.Call
--- @param on_done fun(answer: forge.glab.Answer)
--- @param on_fail fun(why: string)
local function request(call, on_done, on_fail)
  local cmd = { 'glab', 'api' }
  if call.host then
    vim.list_extend(cmd, { '--hostname', call.host })
  end
  if call.method then
    vim.list_extend(cmd, { '--method', call.method })
  end
  if call.body then
    vim.list_extend(cmd, { '--header', 'Content-Type: application/json', '--input', '-' })
  end
  -- `--paginate` alone writes one array per page. That is several documents,
  -- not one. ndjson makes it a row a line instead. ci.nvim's.
  if call.all then
    vim.list_extend(cmd, { '--paginate', '--output', 'ndjson' })
  end
  if call.include then
    cmd[#cmd + 1] = '--include'
  end
  cmd[#cmd + 1] = call.path

  local opts = { text = true, cwd = call.cwd, stdin = call.body and vim.json.encode(call.body) }
  vim.system(cmd, opts, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return on_fail(errmsg(out))
      end
      local headers, text = {}, out.stdout or ''
      if call.include then
        headers, text = headed(text)
      end
      if not call.all then
        local body = decoded(text)
        if not body then
          return on_fail('could not read glab output')
        end
        return on_done({ body = body, headers = headers })
      end
      local rows = {}
      for line in vim.gsplit(text, '\n') do
        if vim.trim(line) ~= '' then
          local row = decoded(line)
          if not row then
            return on_fail('could not read glab output')
          end
          rows[#rows + 1] = row
        end
      end
      on_done({ body = rows, headers = headers })
    end)
  end)
end

--- @alias forge.glab.Job { fail: fun(why: string), ok: fun() }

--- One operation's progress message, however many requests it takes.
---
--- A view is four or five requests. What a reader waits for is the view.
--- Every path out settles this exactly once.
--- @param desc string
--- @param on_fail fun()? for a caller to stop saying it is working
--- @return forge.glab.Job
local function working(desc, on_fail)
  local done = log.progress(desc)
  local settled = false
  return {
    fail = function(why)
      if settled then
        return
      end
      settled = true
      done('failed', why)
      log.err(why)
      if on_fail then
        on_fail()
      end
    end,
    ok = function()
      if settled then
        return
      end
      settled = true
      done('success', desc)
    end,
  }
end

--- Ask for several things at once, and hand them over together.
---
--- gitlab answers a view in pieces where github answers in one document.
--- Chaining would be that many round trips deep before anything is drawn.
--- The first failure stops the rest from answering.
--- @param calls table<string, forge.glab.Call>
--- @param job forge.glab.Job
--- @param on_done fun(answers: table<string, forge.glab.Answer>)
local function together(calls, job, on_done)
  local names = vim.tbl_keys(calls)
  local answers = {}
  local left = #names
  for _, name in ipairs(names) do
    request(calls[name], function(answer)
      answers[name] = answer
      left = left - 1
      if left == 0 then
        on_done(answers)
      end
    end, function(why)
      left = -1
      job.fail(why)
    end)
  end
end

--- gitlab's states in forge's words. Locked is closed to everyone but a
--- maintainer, and reads as closed. A state gitlab adds later is left unsaid.
local STATE = { opened = 'OPEN', closed = 'CLOSED', merged = 'MERGED', locked = 'CLOSED' }

--- A pipeline's state as github's check rollup. That is the shape the badge
--- is drawn from. Only a failure and a wait get one, as on github.
local ROLLUP = {
  failed = 'FAILURE',
  created = 'PENDING',
  waiting_for_resource = 'PENDING',
  preparing = 'PENDING',
  pending = 'PENDING',
  running = 'PENDING',
  scheduled = 'PENDING',
}

--- Mergeability is computed on request, not kept. These three mean gitlab
--- has not looked yet. Only a conflict is read off the field.
local LOOKING = { unchecked = true, checking = true, preparing = true }

--- A note anchored to a diff is a review comment. forge draws none of those.
--- A system note is gitlab narrating itself.
local ANCHORED = { DiffNote = true, LegacyDiffNote = true }

--- A bare gitlab array in the shape the renderers index. github answers every
--- list with nodes and a count. The count is what came. Nothing here is capped.
--- @param values table[]
--- @return table
local function connection(values)
  return { nodes = values, totalCount = #values }
end

--- @param names string[]?
--- @return table
local function labelled(names)
  local out = {}
  for _, name in ipairs(names or {}) do
    out[#out + 1] = { name = name }
  end
  return connection(out)
end

--- @param users table[]?
--- @return table
local function logins(users)
  local out = {}
  for _, user in ipairs(users or {}) do
    if user.username then
      out[#out + 1] = { login = user.username }
    end
  end
  return connection(out)
end

--- @param users table[]?
--- @return table
local function asked(users)
  local out = {}
  for _, one in ipairs(logins(users).nodes) do
    out[#out + 1] = { requestedReviewer = one }
  end
  return connection(out)
end

--- @param notes table[]?
--- @return table
local function conversation(notes)
  local out = {}
  for _, note in ipairs(notes or {}) do
    if note.system ~= true and not ANCHORED[note.type or ''] then
      out[#out + 1] = {
        -- gitlab keeps a deleted account as a user named "ghost". forge puts
        -- that name on one anyway.
        author = { login = vim.tbl_get(note, 'author', 'username') },
        createdAt = note.created_at,
        body = note.body,
      }
    end
  end
  return connection(out)
end

--- One merge request or issue, in the shape forge's renderers read.
---
--- `iid` and never `id`: gitlab's global id 404s on every route that takes a
--- number, and the iid is what its own pages show. A field gitlab has no
--- equivalent for is left out. A renderer draws nothing for what is missing.
--- @param collection forge.Collection
--- @param row table gitlab's own merge request or issue
--- @param notes table[]? its notes, where they were asked for
--- @return table
function M.node(collection, row, notes)
  local node = {
    -- What a write names it by. gitlab is addressed by path. This is the
    -- number again, not an opaque id.
    id = tostring(row.iid),
    number = row.iid,
    title = row.title,
    body = row.description,
    url = row.web_url,
    createdAt = row.created_at,
    state = STATE[row.state or ''],
    author = { login = vim.tbl_get(row, 'author', 'username') },
    labels = labelled(row.labels),
    assignees = logins(row.assignees),
    milestone = row.milestone and { title = row.milestone.title } or nil,
    comments = notes and conversation(notes) or nil,
  }

  if collection == 'issues' then
    -- gitlab types every issue and calls the ordinary one "issue", where
    -- github answers no type at all. Neither is worth a row.
    node.issueType = (row.issue_type and row.issue_type ~= 'issue') and { name = row.issue_type }
      or nil
    return node
  end

  node.isDraft = row.draft == true
  node.baseRefName = row.target_branch
  node.headRefName = row.source_branch
  node.headRefOid = row.sha
  node.isCrossRepository = row.source_project_id ~= row.target_project_id
  -- gitlab names only the first thing blocking a merge. `has_conflicts` means
  -- nothing until it has looked. The two corroborate each other.
  node.mergeable = (row.detailed_merge_status == 'conflict' or row.has_conflicts == true)
      and 'CONFLICTING'
    or (LOOKING[row.detailed_merge_status or ''] and 'UNKNOWN' or 'MERGEABLE')
  -- gitlab does not drop a reviewer once they have answered. This row is
  -- everyone asked, not only those still to answer.
  node.reviewRequests = asked(row.reviewers)
  -- github hangs the checks on the rollup of the last commit. gitlab runs one
  -- pipeline for the merge request and puts the state on the request itself.
  local status = vim.tbl_get(row, 'head_pipeline', 'status')
  if ROLLUP[status or ''] then
    node.commits = { nodes = { { commit = { statusCheckRollup = { state = ROLLUP[status] } } } } }
  end
  return node
end

--- The lines a merge request adds and removes.
---
--- Counted from the patch: gitlab's `changes_count` counts files, is a string,
--- and is capped at "1000+".
--- @param diffs table[]
--- @return integer added
--- @return integer removed
local function counted(diffs)
  local added, removed = 0, 0
  for _, file in ipairs(diffs) do
    for line in vim.gsplit(file.diff or '', '\n') do
      local mark = line:sub(1, 1)
      if mark == '+' and line:sub(1, 3) ~= '+++' then
        added = added + 1
      elseif mark == '-' and line:sub(1, 3) ~= '---' then
        removed = removed + 1
      end
    end
  end
  return added, removed
end

--- Whether gitlab will let you change this.
---
--- There is no field for it: gitlab answers a merge request with whether you
--- may merge, and an issue with nothing at all. What it enforces is the role
--- you hold in the project: reporter for an issue, developer for a merge
--- request. An author may always change their own.
--- @param collection forge.Collection
--- @param project table
--- @param row table
--- @param me string? who you are on this instance
--- @return boolean
local function may_update(collection, project, row, me)
  if me and me == vim.tbl_get(row, 'author', 'username') then
    return true
  end
  local own = vim.tbl_get(project, 'permissions', 'project_access', 'access_level') or 0
  local group = vim.tbl_get(project, 'permissions', 'group_access', 'access_level') or 0
  return math.max(own, group) >= (collection == 'prs' and DEVELOPER or REPORTER)
end

--- The project around an item, in the fields forge reads off one.
--- @param project table
--- @param row table? the merge request, where there is one
--- @return table
local function repository(project, row)
  return {
    -- What "dd" and "dl" fetch from. For a merge request opened from a fork
    -- that is still the project it merges into.
    url = project.http_url_to_repo,
    -- Write access is only ever asked in order to decide whether to offer a
    -- merge, and gitlab answers exactly that question on the merge request.
    viewerPermission = vim.tbl_get(row or {}, 'user', 'can_merge') == true and 'WRITE' or 'READ',
    -- gitlab settles one merge method per project, not three switches.
    -- Fast-forward writes no merge commit. Squashing "always" leaves no other
    -- way in. Its rebase is a separate asynchronous operation, not a merge
    -- method, so `rebaseMergeAllowed` is absent here.
    mergeCommitAllowed = project.merge_method ~= 'ff' and project.squash_option ~= 'always',
    squashMergeAllowed = project.squash_option ~= 'never',
  }
end

--- @param t forge.Target
--- @param f forge.Fetch
--- @param on_done fun(page: forge.Page?)
--- @param on_fail fun()?
function M.list(t, f, on_done, on_fail)
  local job = working(f.desc, on_fail)
  local at = M.path(t.project)
  local member = PATH[t.collection]
  -- Every state, newest first, as github orders its own list. gitlab has no
  -- cursor. The cursor forge carries between pages is the next page number.
  local query = ('state=all&order_by=updated_at&sort=desc&per_page=%d&page=%d'):format(
    PER_PAGE,
    tonumber(f.after) or 1
  )
  -- gitlab has no qualifier language to hand through. Whatever was typed is
  -- looked for in the title and the description.
  if t.query then
    query = ('%s&search=%s&in=title,description'):format(query, enc(t.query))
  end

  --- @type table<string, forge.glab.Call>
  local calls = {
    project = { path = 'projects/' .. at, cwd = f.cwd, host = t.host },
    rows = {
      path = ('projects/%s/%s?%s'):format(at, member, query),
      cwd = f.cwd,
      host = t.host,
      include = true,
    },
  }

  together(calls, job, function(answers)
    local project = answers.project.body
    if not project.path_with_namespace or not project.web_url then
      return job.fail('glab did not say which project that is')
    end
    local nodes = {}
    for _, row in ipairs(answers.rows.body) do
      nodes[#nodes + 1] = M.node(t.collection, row)
    end
    -- Absent above ten thousand. gitlab documents that as the size at which
    -- it stops counting a list. Nothing here fills it in.
    local total = tonumber(answers.rows.headers['x-total'])
    local after = tonumber(answers.rows.headers['x-next-page'])

    job.ok()
    on_done({
      project = project.path_with_namespace,
      nodes = nodes,
      total = total,
      reach = total,
      cursor = after and tostring(after) or nil,
      has_next = after ~= nil,
      url = ('%s/-/%s'):format(project.web_url, member)
        .. (t.query and ('?search=' .. enc(t.query)) or ''),
    })
  end)
end

--- @param t forge.Target
--- @param f forge.Fetch
--- @param on_done fun(one: forge.Item?)
--- @param on_fail fun()?
function M.item(t, f, on_done, on_fail)
  local job = working(f.desc, on_fail)
  local at = M.path(t.project)
  local one = ('projects/%s/%s/%d'):format(at, PATH[t.collection], t.number)

  --- @type table<string, forge.glab.Call>
  local calls = {
    project = { path = 'projects/' .. at, cwd = f.cwd, host = t.host },
    item = { path = one, cwd = f.cwd, host = t.host },
    -- Oldest first, and every page of it. A conversation reads down the
    -- buffer. A note past the first page would be a comment silently lost.
    notes = {
      path = one .. '/notes?per_page=100&sort=asc&order_by=created_at',
      cwd = f.cwd,
      host = t.host,
      all = true,
    },
    -- Who you are. Half of whether you may change this.
    me = { path = 'user', cwd = f.cwd, host = t.host },
  }
  if t.collection == 'prs' then
    calls.diffs = { path = one .. '/diffs?per_page=100', cwd = f.cwd, host = t.host, all = true }
  end

  together(calls, job, function(answers)
    local project, row = answers.project.body, answers.item.body
    if not project.path_with_namespace or not row.iid then
      return job.fail('glab did not say which project that is')
    end

    local node = M.node(t.collection, row, answers.notes.body)
    node.viewerCanUpdate = may_update(t.collection, project, row, answers.me.body.username)
    if answers.diffs then
      node.additions, node.deletions = counted(answers.diffs.body)
    end

    local function finish()
      job.ok()
      on_done({
        project = project.path_with_namespace,
        node = node,
        repo = repository(project, t.collection == 'prs' and row or nil),
      })
    end

    if not node.isCrossRepository then
      return finish()
    end
    -- A merge request opened from a fork lives on the project it merges into.
    -- The fork's id is the only thing on it naming where the branch came from.
    request({
      path = ('projects/%d'):format(row.source_project_id),
      cwd = f.cwd,
      host = t.host,
    }, function(answer)
      node.headRepositoryOwner = { login = answer.body.path_with_namespace }
      finish()
    end, job.fail)
  end)
end

--- @param t forge.Target
--- @param branch string
--- @param f forge.Fetch
--- @param on_done fun(found: forge.Head)
function M.head(t, branch, f, on_done)
  local job = working(f.desc)
  local at = M.path(t.project)
  local query = ('state=opened&source_branch=%s&order_by=updated_at&sort=desc'):format(enc(branch))

  --- @type table<string, forge.glab.Call>
  local calls = {
    project = { path = 'projects/' .. at, cwd = f.cwd, host = t.host },
    -- A merge request opened from a fork still lives on the project it merges
    -- into, and still carries the branch it came from. One list answers for a
    -- fork's as well as for one of your own.
    rows = {
      path = ('projects/%s/merge_requests?%s'):format(at, query),
      cwd = f.cwd,
      host = t.host,
    },
  }

  together(calls, job, function(answers)
    local found = answers.rows.body[1]
    job.ok()
    on_done({
      project = answers.project.body.path_with_namespace,
      number = found and found.iid or nil,
    })
  end)
end

--- How many either direction of a walk asks for. A branch answers one merge
--- request below it and however many above; ten is past where a fork is worth
--- naming rather than ordering.
local EITHER_WAY = 10

--- One row of a list, in the shape forge.stack reads.
--- @param row table
--- @return forge.stack.Pull
local function pulled(row)
  return {
    number = row.iid,
    title = row.title or '',
    state = STATE[row.state or ''],
    isDraft = row.draft == true,
    base = row.target_branch,
    head = row.source_branch,
  }
end

--- The merge request being read, in the same shape. Its node has already been
--- through the item builder, so it speaks forge's words rather than gitlab's.
--- @param node table
--- @return forge.stack.Pull
local function reading(node)
  return {
    number = node.number,
    title = node.title or '',
    state = node.state,
    isDraft = node.isDraft == true,
    base = node.baseRefName,
    head = node.headRefName,
  }
end

--- Only what a chain in this project could be built from. A merge request
--- opened from a fork carries a branch in another project's namespace, so it
--- can neither continue a chain nor be continued.
--- @param rows table?
--- @return table[]
local function ours(rows)
  return vim.tbl_filter(function(row)
    return type(row) == 'table' and row.source_project_id == row.target_project_id
  end, type(rows) == 'table' and rows or {})
end

--- @param at string
--- @param query string
--- @param t forge.Target
--- @param f forge.Fetch
--- @return forge.glab.Call
local function listed(at, query, t, f)
  return {
    path = ('projects/%s/merge_requests?state=opened&%s'):format(at, query),
    cwd = f.cwd,
    host = t.host,
  }
end

--- Follow the chain a layer at a time, in both directions at once.
---
--- Nothing is enumerated, so the size of the project never comes into it. Down
--- and up are independent, so a ring asks for both and costs one round trip.
--- @param t forge.Target
--- @param f forge.Fetch
--- @param at string
--- @param here forge.stack.Pull
--- @param job forge.glab.Job
--- @param on_done fun(s: forge.Stack?)
local function walking(t, f, at, here, job, on_done)
  local found = { [here.number] = here }

  local function step(base, head, depth)
    together(
      {
        under = listed(at, ('source_branch=%s&per_page=%d'):format(enc(base), EITHER_WAY), t, f),
        over = listed(at, ('target_branch=%s&per_page=%d'):format(enc(head), EITHER_WAY), t, f),
      },
      job,
      function(answers)
        local under = ours(answers.under.body)[1]
        local over = ours(answers.over.body)

        local grew = false
        for _, row in ipairs(under and { under } or {}) do
          grew = grew or found[row.iid] == nil
          found[row.iid] = found[row.iid] or pulled(row)
        end
        for _, row in ipairs(over) do
          grew = grew or found[row.iid] == nil
          found[row.iid] = found[row.iid] or pulled(row)
        end

        -- A fork ends the walk upward: there is no single branch to follow past
        -- it, and stack.chain names it out of what was collected.
        local above = #over == 1 and over[1] or nil
        if not grew or depth >= stack.MAX then
          job.ok()
          return on_done(stack.of(vim.tbl_values(found), here.number))
        end
        step(
          under and under.target_branch or base,
          above and above.source_branch or head,
          depth + 1
        )
      end
    )
  end

  step(here.base, here.head, 1)
end

--- @param t forge.Target
--- @param one forge.Item
--- @param f forge.Fetch
--- @param on_done fun(s: forge.Stack?)
function M.stack(t, one, f, on_done)
  local node = one.node
  -- A fork's branch is not in this project's namespace, so there is nothing
  -- here to chain.
  if node.isCrossRepository or not node.headRefName then
    return on_done(nil)
  end
  local at = M.path(t.project)
  local here = reading(node)
  local job = working(f.desc, function()
    on_done(nil)
  end)

  request(listed(at, ('per_page=%d'):format(PER_PAGE), t, f), function(answer)
    local rows = type(answer.body) == 'table' and answer.body or {}
    -- A page that came back short held every open merge request there is, so
    -- the chain is a lookup away and no walk is worth its round trips. A full
    -- one says nothing about what follows it, and gitlab stops counting a
    -- large project at all, so the count is no better than the page.
    if #rows < PER_PAGE then
      job.ok()
      return on_done(stack.of(vim.tbl_map(pulled, ours(rows)), here.number))
    end
    walking(t, f, at, here, job, on_done)
  end, job.fail)
end

--- What gitlab reads as a draft, in the three spellings it accepts. See
--- `MergeRequest::DRAFT_REGEX` in gitlab's own source.
local DRAFTED = {
  '^%s*[Dd][Rr][Aa][Ff][Tt]:%s*',
  '^%s*%[[Dd][Rr][Aa][Ff][Tt]%]%s*',
  '^%s*%([Dd][Rr][Aa][Ff][Tt]%)%s*',
}

--- The title that makes a merge request a draft, or stops it being one.
---
--- There is nothing else to set. gitlab derives the flag from the title, and
--- its rest api refuses a `draft` parameter. Every prefix is stripped before
--- one is put back. gitlab reads a repeated prefix as a draft too.
--- @param title string
--- @param draft boolean which it should be once this is sent
--- @return string
function M.draft(title, draft)
  local plain, before = title, nil
  repeat
    before = plain
    for _, prefix in ipairs(DRAFTED) do
      plain = plain:gsub(prefix, '', 1)
    end
  until plain == before
  return draft and ('Draft: %s'):format(plain) or plain
end

--- What each change sends, in the word gitlab spells it with.
---
--- A word rather than a document. gitlab is written to by method and path.
--- There is nothing to hand over whole the way a github mutation is. `draft`
--- and `ready` are not constants at all. `M.write` builds those from the
--- title, unknown until the merge request is.
--- @type table<forge.Collection, table<string, string>>
M.writes = {
  issues = {
    -- gitlab keeps no reason an issue closed. The two named closings go
    -- unanswered, and forge.collection never offers them.
    close = 'close',
    reopen = 'reopen',
  },
  prs = {
    draft = 'draft',
    ready = 'ready',
    close = 'close',
    reopen = 'reopen',
  },
}

--- @param w forge.Write
--- @param on_done fun()
--- @param on_fail fun()?
function M.write(w, on_done, on_fail)
  local var = w.var
  -- The instance the item came from rather than the one this directory points
  -- at. On a self-hosted install those differ.
  local host = (var.url or ''):match('^https?://([^/]+)')
  local at = ('projects/%s/%s/%s'):format(M.path(var.repo), PATH[w.collection], var.id or '')

  local path, body = at, nil
  if w.kind == 'edit' then
    body = { title = w.title, description = w.body }
  elseif w.kind == 'merge' then
    path = at .. '/merge'
    -- gitlab takes one message where github takes a headline and a body. The
    -- two are joined back into the commit they describe.
    local message = vim.trim(w.body or '') ~= '' and ('%s\n\n%s'):format(w.headline, w.body)
      or w.headline
    -- `sha` refuses the merge if the branch moved since the view was drawn.
    -- github's `expectedHeadOid` under another name.
    body = { sha = var.oid, squash = w.method == 'SQUASH' }
    body[w.method == 'SQUASH' and 'squash_commit_message' or 'merge_commit_message'] = message
  elseif w.query == 'draft' or w.query == 'ready' then
    body = { title = M.draft(var.title or '', w.query == 'draft') }
  else
    body = { state_event = w.query }
  end

  local job = working(w.desc, on_fail)
  request({ path = path, method = 'PUT', body = body, cwd = w.cwd, host = host }, function()
    job.ok()
    on_done()
  end, job.fail)
end

--- Open gitlab's own page for a new item, leaving templates and required
--- fields for gitlab to enforce.
---
--- An address for both collections, where github hands a pull request to gh:
--- `glab mr create` prompts for whatever it cannot infer and has no terminal
--- to prompt in. The current branch is put in the form, not pushed first. The
--- form will not offer a branch gitlab has never seen.
--- @param t forge.Target what to add to
--- @param host string the host that answered, which on a self-hosted instance
--- is not the one a name defaults to
function M.create(t, host)
  if not host or not t.project then
    log.warn('no url for this buffer')
    return
  end
  local at = ('https://%s/%s/-/%s/new'):format(host, t.project, PATH[t.collection])
  if t.collection == 'issues' then
    vim.ui.open(at)
    return
  end

  local vcs = require('forge.vcs')
  local branch = vcs.branch(vcs.dir())
  vim.ui.open(branch and ('%s?merge_request%%5Bsource_branch%%5D=%s'):format(at, enc(branch)) or at)
end

--- What gitlab writes in front of each numbered path once it is short.
local SIGIL = { issues = '#', work_items = '#', merge_requests = '!' }

--- The tabs of a merge request that gitlab still shortens. It names two of
--- them in the suffix and says nothing for the third.
local TAB = { diffs = 'diffs', commits = 'commits', pipelines = '' }

--- How much of a project's path survives into a reference read from `project`.
---
--- Three deep, where github's is two: gitlab drops the namespace as well when
--- both sit under it, leaving a project on its own.
--- @param path string
--- @param project string
--- @return string
local function prefix(path, project)
  if path == project then
    return ''
  end
  local ns = path:match('^(.+)/[^/]+$')
  local mine = project:match('^(.+)/[^/]+$')
  if ns and ns == mine then
    return (path:match('([^/]+)$'))
  end
  return path
end

--- What gitlab draws in place of one of its own addresses.
---
--- The note id gitlab puts in the suffix is dropped. It is eighteen digits of
--- database key inside a form whose whole purpose is brevity, and nothing in
--- the buffer can address it.
--- @param url string
--- @param project string the project the view belongs to
--- @return string?
function M.shorten(url, project)
  local rest = url:match('^https://[^/]+/(.+)$')
  if not rest then
    return nil
  end
  local body, fragment = rest:match('^([^#?]*)#?([^?]*)')
  local where, tail = body:gsub('/$', ''):match('^(.-)/%-/(.+)$')
  if not where then
    return nil
  end
  local noted = fragment:match('^note_%d+$') ~= nil

  -- An epic belongs to a group, so it is the project's own namespace that
  -- decides whether the group is worth naming.
  local group = where:match('^groups/(.+)$')
  if group then
    local number = tail:match('^epics/(%d+)$')
    if not number then
      return nil
    end
    local mine = project:match('^(.+)/[^/]+$')
    local at = group == mine and '' or group
    return ('%s&%s%s'):format(at, number, noted and ' (comment)' or '')
  end

  local kind, number, tab = tail:match('^([%a_]+)/(%d+)/?(%a*)$')
  if not kind or not SIGIL[kind] then
    return nil
  end
  local about = {}
  if tab ~= '' then
    if kind ~= 'merge_requests' or not TAB[tab] then
      return nil
    end
    if TAB[tab] ~= '' then
      about[#about + 1] = TAB[tab]
    end
  end
  if noted then
    about[#about + 1] = 'comment'
  end
  return ('%s%s%s%s'):format(
    prefix(where, project),
    SIGIL[kind],
    number,
    #about > 0 and (' (%s)'):format(table.concat(about, ', ')) or ''
  )
end

--- Where gitlab publishes a merge request's head. Served on the project it
--- merges into, even for one opened from a fork. `refs/merge-requests/N/merge`
--- beside it is the merged result, not the head.
--- @param number integer
--- @return string
function M.pull_ref(number)
  return ('refs/merge-requests/%d/head'):format(number)
end

return M
