--- gitlab, as forge.Backend asks for it: the requests it makes, the words it
--- says them in, and the shape it hands back.
---
--- Everything goes through `glab api`, which is gitlab's REST API with an
--- authenticated host already attached. A project is a percent-encoded path
--- rather than an owner and a name, a change is a method and a body rather
--- than a document, and a view is several small requests rather than one
--- large one. The transport is ci.nvim's, which speaks to the same CLI.

local log = require('forge.log')

local M = {}

--- gitlab numbers merge requests apart from issues and writes "!" in front of
--- one, so unlike github the two collections have no word in common.
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

--- What gitlab calls a collection in an api path, which is also what it calls
--- it in a web address.
local PATH = { issues = 'issues', prs = 'merge_requests' }

--- How many a list asks for at once, which has to be forge.view's PER_PAGE:
--- that is what the pager divides a total by to say how many pages there are.
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
--- since the whole path is one segment of the api's own and a project nests
--- under as many groups as it likes. glab's placeholder stands in where
--- nothing named a project, and resolves from the remote in `cwd`. ci.nvim's.
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
--- 404)" line to stderr, so the body is read first: it is the same sentence
--- without the prefix. ci.nvim's.
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

--- Absent rather than `vim.NIL`, as forge.gh does: a null that reads as
--- present is worse than a field that is missing. Objects only, since a null
--- dropped from a list leaves a hole `ipairs` stops at.
local DECODE = { luanil = { object = true } }

--- @param text string
--- @return table?
local function decoded(text)
  local ok, body = pcall(vim.json.decode, text, DECODE)
  return (ok and type(body) == 'table') and body or nil
end

--- `glab api --include` prints the status line and the headers, a blank line,
--- then the body. It is the only way to see `X-Total`, which is where gitlab
--- puts the size of a list, and it costs no second request.
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
--- @field host string? which instance to ask, since a buffer is read wherever
--- you happen to be standing rather than in the repository it came from
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
  --- A list forge draws whole is asked for whole: `--paginate` alone writes
  --- one array a page, which is several documents and no json reader's idea
  --- of one, and ndjson makes it a row a line instead. ci.nvim's.
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
--- Owned here rather than by a request, because a view is four or five of them
--- and what a reader is waiting for is the view. Every path out settles it
--- exactly once, so none can dangle and none can report twice.
--- @param desc string
--- @param on_fail fun()? so a caller that said it was working can stop saying it
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
--- gitlab answers a view in pieces where github answers it in one document, so
--- chaining them would be that many round trips deep before anything is drawn.
--- The first failure stops the rest from ever answering.
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

--- gitlab's states in forge's words. A locked item is closed to everyone but a
--- maintainer, which is closed as far as a reader is concerned; a state gitlab
--- adds later is left unsaid rather than guessed at.
local STATE = { opened = 'OPEN', closed = 'CLOSED', merged = 'MERGED', locked = 'CLOSED' }

--- A pipeline's state as github's check rollup, which is the shape the badge
--- is drawn from. Only a failure and a wait are worth one: github says nothing
--- for a rollup that passed, and neither does this.
local ROLLUP = {
  failed = 'FAILURE',
  created = 'PENDING',
  waiting_for_resource = 'PENDING',
  preparing = 'PENDING',
  pending = 'PENDING',
  running = 'PENDING',
  scheduled = 'PENDING',
}

--- Mergeability is computed when a merge request is asked for rather than
--- kept, so these three are gitlab saying it has not looked yet. Only a
--- conflict is ever read off the field, and not one of them is one.
local LOOKING = { unchecked = true, checking = true, preparing = true }

--- A note anchored to a diff is a review comment, which forge's item view does
--- not draw on github either, and a system note is gitlab narrating itself
--- rather than anybody having said anything.
local ANCHORED = { DiffNote = true, LegacyDiffNote = true }

--- A connection, as the renderers index one: github answers every list of
--- these with nodes and a count, and gitlab with a bare array. The count is
--- what came, because nothing here is capped.
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
        --- gitlab keeps a deleted account as a user named "ghost", which is
        --- the name forge puts on one anyway.
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
--- equivalent for is left out rather than filled in, since a renderer draws
--- nothing for what is missing and something wrong for what was guessed.
--- @param collection forge.Collection
--- @param row table gitlab's own merge request or issue
--- @param notes table[]? its notes, where they were asked for
--- @return table
function M.node(collection, row, notes)
  local node = {
    --- What a write names it by. gitlab is addressed by path, so this is the
    --- number again rather than an opaque id.
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
    --- gitlab types every issue and calls the ordinary one "issue", which is
    --- github answering no type at all rather than a type worth a row.
    node.issueType = (row.issue_type and row.issue_type ~= 'issue') and { name = row.issue_type }
      or nil
    return node
  end

  node.isDraft = row.draft == true
  node.baseRefName = row.target_branch
  node.headRefName = row.source_branch
  node.headRefOid = row.sha
  node.isCrossRepository = row.source_project_id ~= row.target_project_id
  --- gitlab names the first thing blocking a merge rather than everything, and
  --- `has_conflicts` means nothing until it has looked, so the two corroborate
  --- each other.
  node.mergeable = (row.detailed_merge_status == 'conflict' or row.has_conflicts == true)
      and 'CONFLICTING'
    or (LOOKING[row.detailed_merge_status or ''] and 'UNKNOWN' or 'MERGEABLE')
  --- gitlab does not drop a reviewer once they have answered, so this row is
  --- everyone asked rather than only those still to answer.
  node.reviewRequests = asked(row.reviewers)
  --- What the author asked for, and where they asked for nothing, what the
  --- project settled: gitlab answers the first as null and folds the second
  --- into the flag it would act on.
  node.deletesBranch = row.should_remove_source_branch
  if node.deletesBranch == nil then
    node.deletesBranch = row.force_remove_source_branch == true
  end
  --- Where github hangs the checks: on the rollup of the last commit. gitlab
  --- runs one pipeline for the merge request and puts its state on the merge
  --- request, and only a single one carries it.
  local status = vim.tbl_get(row, 'head_pipeline', 'status')
  if ROLLUP[status or ''] then
    node.commits = { nodes = { { commit = { statusCheckRollup = { state = ROLLUP[status] } } } } }
  end
  return node
end

--- The lines a merge request adds and removes.
---
--- Counted rather than read: gitlab's rest api answers with `changes_count`,
--- which counts files, is a string, and is capped at "1000+". The patch itself
--- is the only place the lines are.
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
--- may merge and an issue with nothing at all. What it enforces is the role
--- you hold in the project — reporter for an issue, developer for a merge
--- request — and that an author may always change their own.
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
    --- What "dd" and "dl" fetch from, which for a merge request opened from a
    --- fork is still the project it merges into.
    url = project.http_url_to_repo,
    --- Write access is only ever asked in order to decide whether to offer a
    --- merge, and gitlab answers exactly that question on the merge request.
    viewerPermission = vim.tbl_get(row or {}, 'user', 'can_merge') == true and 'WRITE' or 'READ',
    --- gitlab settles one merge method for a whole project rather than
    --- offering three switches: fast-forward writes no merge commit, and
    --- squashing "always" leaves no other way in. Its rebase is a separate,
    --- asynchronous operation and not a way of merging at all, so
    --- rebaseMergeAllowed is absent and no rebase is ever offered.
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
  --- Every state, newest first, as github's own list is ordered. gitlab has no
  --- cursor, so the cursor forge carries from one page to the next is the
  --- number of the next one.
  local query = ('state=all&order_by=updated_at&sort=desc&per_page=%d&page=%d'):format(
    PER_PAGE,
    tonumber(f.after) or 1
  )
  --- Whatever was typed, looked for in the title and the description. gitlab
  --- has no qualifier language to hand through the way github's search does,
  --- so a search here narrows and never widens.
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
    --- Absent above ten thousand, which gitlab documents as the size at which
    --- it stops counting a list. Nothing here fills that in.
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
    --- Oldest first, so a conversation reads down the buffer, and all of it:
    --- a note past the first page is a comment forge would silently lose.
    notes = {
      path = one .. '/notes?per_page=100&sort=asc&order_by=created_at',
      cwd = f.cwd,
      host = t.host,
      all = true,
    },
    --- Who you are, which is half of whether you may change this.
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
    --- A merge request opened from a fork lives on the project it merges into,
    --- and nothing on it names where the branch came from but the fork's id.
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
    --- A merge request opened from a fork still lives on the project it merges
    --- into and still carries the branch it came from, so one list answers for
    --- a fork's as well as for one of your own.
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

--- What gitlab reads as a draft, in the three spellings it accepts. See
--- `MergeRequest::DRAFT_REGEX` in gitlab's own source.
local DRAFTED = {
  '^%s*[Dd][Rr][Aa][Ff][Tt]:%s*',
  '^%s*%[[Dd][Rr][Aa][Ff][Tt]%]%s*',
  '^%s*%([Dd][Rr][Aa][Ff][Tt]%)%s*',
}

--- The title that makes a merge request a draft, or stops it being one.
---
--- There is nothing else to set: gitlab derives the flag from the title, and
--- its rest api refuses a `draft` parameter outright. Every prefix is stripped
--- before one is put back, because gitlab reads a repeated one as a draft too.
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
--- A word rather than a document: gitlab is written to by method and path, so
--- there is nothing to hand over whole the way a github mutation is, and two
--- of these are not a constant at all — a draft is a prefix on the title,
--- which is not known until the merge request is.
---
--- Both closings are the one closing. gitlab keeps no reason an issue closed,
--- so "not planned" names something it does not record, and the menu offers
--- both because an action is offered on what may be asked of an item rather
--- than on which writes the forge answered with.
--- @type table<forge.Collection, table<string, string>>
M.writes = {
  issues = {
    --- One close, and no reason kept for it: the two that name a reason go
    --- unanswered and are never offered.
    close = 'close',
    reopen = 'reopen',
  },
  prs = {
    draft = 'draft',
    ready = 'ready',
    --- gitlab keeps this on the merge request rather than on the project, so
    --- it is a change to the merge request like any other.
    delete_branch = 'remove_source_branch',
    keep_branch = 'keep_source_branch',
    close = 'close',
    reopen = 'reopen',
  },
}

--- @param w forge.Write
--- @param on_done fun()
--- @param on_fail fun()?
function M.write(w, on_done, on_fail)
  local var = w.var
  --- The instance the item came from rather than the one this directory points
  --- at, which on an enterprise install are two different places.
  local host = (var.url or ''):match('^https?://([^/]+)')
  local at = ('projects/%s/%s/%s'):format(M.path(var.repo), PATH[w.collection], var.id or '')

  local path, body = at, nil
  if w.kind == 'edit' then
    body = { title = w.title, description = w.body }
  elseif w.kind == 'merge' then
    path = at .. '/merge'
    --- One message where github takes a headline and a body, so the two are
    --- joined back into the commit they describe.
    local message = vim.trim(w.body or '') ~= '' and ('%s\n\n%s'):format(w.headline, w.body)
      or w.headline
    --- `sha` refuses the merge if the branch moved since the view was drawn,
    --- which is github's `expectedHeadOid` under another name.
    body = { sha = var.oid, squash = w.method == 'SQUASH' }
    body[w.method == 'SQUASH' and 'squash_commit_message' or 'merge_commit_message'] = message
  elseif w.query == 'draft' or w.query == 'ready' then
    body = { title = M.draft(var.title or '', w.query == 'draft') }
  elseif w.query == 'remove_source_branch' or w.query == 'keep_source_branch' then
    body = { remove_source_branch = w.query == 'remove_source_branch' }
  else
    body = { state_event = w.query }
  end

  local job = working(w.desc, on_fail)
  request({ path = path, method = 'PUT', body = body, cwd = w.cwd, host = host }, function()
    job.ok()
    on_done()
  end, job.fail)
end

--- gitlab's own page is the form, so templates and required fields stay theirs
--- to enforce.
---
--- An address for both collections, where github hands a pull request to gh:
--- `glab mr create` prompts for whatever it cannot infer and has no terminal
--- to prompt in, which is the same defect that took gh off this path. The
--- branch you are on is put in the form rather than pushed first, so a branch
--- gitlab has never seen is one the form will not offer.
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

--- Where gitlab publishes a merge request's head.
---
--- On the project it merges into, even for one opened from a fork, so a merge
--- request nobody has fetched is still one fetch away. `refs/merge-requests/
--- N/merge` beside it is the merged result; forge wants the head, as it does
--- on github.
--- @param number integer
--- @return string
function M.pull_ref(number)
  return ('refs/merge-requests/%d/head'):format(number)
end

return M
