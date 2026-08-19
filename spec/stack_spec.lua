local gh = require('forge.gh')
local github = require('forge.github')
local glab = require('forge.glab')
local stack = require('forge.stack')

--- @param rows table[] number, base, head
--- @return forge.stack.Pull[]
local function pulls(rows)
  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = {
      number = row[1],
      base = row[2],
      head = row[3],
      title = row[4] or ('pull ' .. row[1]),
      state = row[5] or 'OPEN',
    }
  end
  return out
end

--- Stack A of the fixture: #147 -> #148 -> #149 -> #150, rooted on main.
local FOUR = pulls({
  { 150, 'c', 'd' },
  { 148, 'a', 'b' },
  { 147, 'main', 'a' },
  { 149, 'b', 'c' },
})

--- @param ordered forge.stack.Pull[]?
--- @return integer[]
local function numbers(ordered)
  return vim.tbl_map(function(pull)
    return pull.number
  end, ordered or {})
end

describe('stack.chain', function()
  it('orders a chain bottom first, whatever order it was given in', function()
    assert.same({ 147, 148, 149, 150 }, numbers(stack.chain(FOUR, 149)))
  end)

  it('finds the same chain from any layer of it', function()
    for _, from in ipairs({ 147, 148, 149, 150 }) do
      assert.same({ 147, 148, 149, 150 }, numbers(stack.chain(FOUR, from)))
    end
  end)

  it('stops below at a base no open pull request heads', function()
    -- The fixture's stack B: its bottom was squash-merged and its branch
    -- deleted, so what is left starts partway up.
    local left = pulls({ { 152, 'main', 'a' }, { 153, 'a', 'b' } })
    assert.same({ 152, 153 }, numbers(stack.chain(left, 153)))
  end)

  it('refuses to guess above a fork, and names what it forks into', function()
    -- #157 is the base of both #158 and #159.
    local forked = pulls({
      { 157, 'main', 'a' },
      { 159, 'a', 'c' },
      { 158, 'a', 'b' },
    })
    local ordered, forks = stack.chain(forked, 157)
    assert.same({ 157 }, numbers(ordered))
    assert.same({ 158, 159 }, forks)
  end)

  it('still walks down out of a fork', function()
    local forked = pulls({
      { 157, 'main', 'a' },
      { 158, 'a', 'b' },
      { 159, 'a', 'c' },
      { 160, 'b', 'd' },
    })
    assert.same({ 157, 158, 160 }, numbers(stack.chain(forked, 158)))
  end)

  it('answers for a pull request that is in no chain at all', function()
    local alone = pulls({ { 161, 'main', 'solo' } })
    assert.same({ 161 }, numbers(stack.chain(alone, 161)))
    assert.is_nil(select(2, stack.chain(alone, 161)))
  end)

  it('is nil for a number it was not given', function()
    assert.is_nil(stack.chain(FOUR, 999))
  end)

  it('keeps the first of two pull requests sharing a head', function()
    -- One branch may have two open pull requests where they merge into
    -- different bases. Only the first may continue the chain.
    local twice = pulls({
      { 10, 'main', 'a' },
      { 11, 'a', 'b' },
      { 12, 'release', 'b' },
    })
    assert.same({ 10, 11 }, numbers(stack.chain(twice, 10)))
  end)

  it('does not loop on a cycle', function()
    local cyclic = pulls({ { 1, 'b', 'a' }, { 2, 'a', 'b' } })
    local ordered = stack.chain(cyclic, 1)
    assert.equals(2, #(ordered or {}))
  end)

  it('gives up past its own limit', function()
    local rows = {}
    for i = 1, stack.MAX + 20 do
      rows[#rows + 1] = { i, i == 1 and 'main' or ('b' .. (i - 1)), 'b' .. i }
    end
    assert.equals(stack.MAX, #(stack.chain(pulls(rows), 1) or {}))
  end)
end)

describe('stack.position', function()
  it('counts from the bottom, as the forge counts', function()
    local ordered = assert(stack.chain(FOUR, 149))
    assert.equals(1, stack.position(ordered, 147))
    assert.equals(3, stack.position(ordered, 149))
    assert.equals(4, stack.position(ordered, 150))
  end)
end)

describe('stack.of', function()
  it('draws nothing for a pull request standing on its own', function()
    assert.is_nil(stack.of(pulls({ { 161, 'main', 'solo' } }), 161))
  end)

  it('draws a fork even where the chain is one layer', function()
    local forked = pulls({
      { 157, 'main', 'a' },
      { 158, 'a', 'b' },
      { 159, 'a', 'c' },
    })
    local of = assert(stack.of(forked, 157))
    assert.same({ 158, 159 }, of.forks)
    assert.equals(1, of.position)
  end)

  it('carries the position of the layer asked for', function()
    local of = assert(stack.of(FOUR, 149))
    assert.equals(3, of.position)
    assert.equals(4, #of.layers)
    assert.is_nil(of.forks)
  end)
end)

--- Answer every document with whatever `replies` says, and record what was
--- asked. A reply of nil is a request that failed.
--- @param replies fun(req: forge.Request): table?
local function answering(replies)
  local sent = {}
  local real = gh.graphql
  --- @diagnostic disable-next-line: duplicate-set-field
  gh.graphql = function(req, on_done, on_fail)
    sent[#sent + 1] = req
    local reply = replies(req)
    if reply == nil then
      if on_fail then
        on_fail()
      end
    else
      on_done(reply)
    end
  end
  return sent, function()
    gh.graphql = real
  end
end

--- @param over table? what to say about the pull request being read
local function item(over)
  return {
    project = 'a/b',
    repo = {},
    node = vim.tbl_extend('force', {
      number = 149,
      baseRefName = 'b',
      headRefName = 'c',
      isCrossRepository = false,
    }, over or {}),
  }
end

local function layer(number, base, head, over)
  return vim.tbl_extend('force', {
    number = number,
    title = 'pull ' .. number,
    state = 'OPEN',
    isDraft = false,
    baseRefName = base,
    headRefName = head,
    isCrossRepository = false,
  }, over or {})
end

--- @param req forge.Request
local function asking(req)
  if req.query:find('stack {', 1, true) then
    return 'entry'
  end
  if req.query:find('under:', 1, true) then
    return 'walk'
  end
  return 'list'
end

--- @param one table
--- @param replies fun(req: forge.Request): table?
local function asked(one, replies)
  local got
  local sent, restore = answering(replies)
  github.stack({ project = 'a/b', collection = 'prs' }, one, { desc = 'x' }, function(s)
    got = s
  end)
  restore()
  return got, sent
end

describe('github.stack', function()
  it('reads the stack github keeps, without deriving one', function()
    local held, sent = asked(item(), function(req)
      assert.equals('entry', asking(req))
      return {
        repository = {
          open = { totalCount = 4000 },
          pullRequest = {
            stack = {
              number = 7,
              entries = {
                totalCount = 4,
                nodes = {
                  { position = 4, pullRequest = layer(150, 'c', 'd') },
                  { position = 1, pullRequest = layer(147, 'main', 'a') },
                  { position = 3, pullRequest = layer(149, 'b', 'c') },
                  { position = 2, pullRequest = layer(148, 'a', 'b') },
                },
              },
            },
          },
        },
      }
    end)

    assert.equals(1, #sent)
    assert.equals(7, assert(held).number)
    assert.equals(3, held.position)
    assert.same({ 147, 148, 149, 150 }, numbers(held.layers))
  end)

  --- A stack github keeps, holding `entries` and saying it holds `totalCount`.
  --- @param entries table[]
  --- @param total integer?
  --- @return fun(req: forge.Request): table
  local function keeping(entries, total)
    return function(req)
      if asking(req) ~= 'entry' then
        return { repository = { pullRequests = { nodes = {} } } }
      end
      return {
        repository = {
          open = { totalCount = 4000 },
          pullRequest = {
            stack = { number = 7, entries = { totalCount = total or #entries, nodes = entries } },
          },
        },
      }
    end
  end

  it('counts the layer being read against the layers it was handed', function()
    -- github froze #147 and #148 at their positions when they merged, and goes
    -- on counting past them. The section draws four rows, and #149 is the third.
    local held = asked(
      item(),
      keeping({
        { position = 1, pullRequest = layer(147, 'main', 'a', { state = 'MERGED' }) },
        { position = 2, pullRequest = layer(148, 'a', 'b', { state = 'MERGED' }) },
        { position = 3, pullRequest = layer(149, 'b', 'c') },
        { position = 4, pullRequest = layer(150, 'c', 'd') },
      })
    )

    assert.equals(3, assert(held).position)
    assert.equals(149, held.layers[held.position].number)
  end)

  it('counts past a layer whose pull request it was not shown', function()
    -- `pullRequest` is nullable. Position 2 answers nothing, so #149 is drawn
    -- second of three however github numbers it.
    local held = asked(
      item(),
      keeping({
        { position = 1, pullRequest = layer(147, 'main', 'a') },
        { position = 2 },
        { position = 3, pullRequest = layer(149, 'b', 'c') },
        { position = 4, pullRequest = layer(150, 'c', 'd') },
      })
    )

    assert.same({ 147, 149, 150 }, numbers(assert(held).layers))
    assert.equals(2, held.position)
    assert.equals(149, held.layers[held.position].number)
  end)

  it('says how many layers the stack holds when it handed over fewer', function()
    local held = asked(
      item(),
      keeping({
        { position = 1, pullRequest = layer(148, 'a', 'b') },
        { position = 2, pullRequest = layer(149, 'b', 'c') },
      }, 63)
    )

    assert.equals(63, assert(held).total)
    assert.equals(2, #held.layers)
  end)

  it('derives rather than draw a stack that never reached the layer read', function()
    local held, sent = asked(item(), function(req)
      if asking(req) == 'entry' then
        return {
          repository = {
            open = { totalCount = 13 },
            pullRequest = {
              stack = {
                number = 7,
                entries = {
                  totalCount = 60,
                  nodes = { { position = 1, pullRequest = layer(147, 'main', 'a') } },
                },
              },
            },
          },
        }
      end
      assert.equals('list', asking(req))
      return {
        repository = {
          pullRequests = { nodes = { layer(148, 'a', 'b'), layer(149, 'b', 'c') } },
        },
      }
    end)

    assert.equals(2, #sent)
    assert.same({ 148, 149 }, numbers(assert(held).layers))
    assert.equals(2, held.position)
    assert.is_nil(held.number)
  end)

  it('reads a page of open pull requests where the repository holds few', function()
    local held, sent = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 13 }, pullRequest = {} } }
      end
      assert.equals('list', asking(req))
      return {
        repository = {
          pullRequests = {
            nodes = {
              layer(147, 'main', 'a'),
              layer(148, 'a', 'b'),
              layer(149, 'b', 'c'),
              layer(150, 'c', 'd'),
            },
          },
        },
      }
    end)

    assert.equals(2, #sent)
    assert.same({ 147, 148, 149, 150 }, numbers(assert(held).layers))
    assert.equals(3, held.position)
    assert.is_nil(held.number)
  end)

  it('walks from both ends where the repository holds too many to read', function()
    local rings = {}
    local held, sent = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 1200 }, pullRequest = {} } }
      end
      assert.equals('walk', asking(req))
      local base, head = req.variables.base, req.variables.head
      rings[#rings + 1] = base .. '/' .. head
      local under = ({ b = layer(148, 'a', 'b'), a = layer(147, 'main', 'a') })[base]
      local over = ({ c = layer(150, 'c', 'd') })[head]
      return {
        repository = {
          under = { nodes = under and { under } or {} },
          over = { nodes = over and { over } or {} },
        },
      }
    end)

    -- One round trip to ask github, then a ring per layer either side.
    assert.same({ 'b/c', 'a/d', 'main/d' }, rings)
    assert.equals(4, #sent)
    assert.same({ 147, 148, 149, 150 }, numbers(assert(held).layers))
    assert.equals(3, held.position)
  end)

  it('leaves a fork to be named rather than walked past', function()
    local held = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 1200 }, pullRequest = {} } }
      end
      local over = req.variables.head == 'c' and { layer(158, 'c', 'x'), layer(159, 'c', 'y') }
        or {}
      return { repository = { under = { nodes = {} }, over = { nodes = over } } }
    end)

    assert.same({ 158, 159 }, assert(held).forks)
    assert.same({ 149 }, numbers(held.layers))
  end)

  it("drops a fork's pull request answering to the same branch name", function()
    local held = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 1200 }, pullRequest = {} } }
      end
      local under = req.variables.base == 'b'
          and {
            layer(900, 'main', 'b', { isCrossRepository = true }),
            layer(148, 'main', 'b'),
          }
        or {}
      return { repository = { under = { nodes = under }, over = { nodes = {} } } }
    end)

    assert.same({ 148, 149 }, numbers(assert(held).layers))
  end)

  it('asks nothing at all about a pull request from a fork', function()
    local held, sent = asked(item({ isCrossRepository = true }), function()
      error('should not have asked')
    end)
    assert.equals(0, #sent)
    assert.is_nil(held)
  end)

  it('draws no stack for a pull request standing alone', function()
    local held = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 13 }, pullRequest = {} } }
      end
      return { repository = { pullRequests = { nodes = { layer(149, 'b', 'c') } } } }
    end)
    assert.is_nil(held)
  end)

  it('says nothing where a request failed rather than half a chain', function()
    local held = asked(item(), function(req)
      if asking(req) == 'entry' then
        return { repository = { open = { totalCount = 13 }, pullRequest = {} } }
      end
      return nil
    end)
    assert.is_nil(held)
  end)
end)

--- Answer every `glab api` with whatever `replies` says of its path, and record
--- the paths asked. glab shells out, so the transport is the only seam.
--- @param replies fun(path: string): table
local function serving(replies)
  local paths = {}
  local real = vim.system
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, _, on_exit)
    local path = cmd[#cmd]
    paths[#paths + 1] = path
    on_exit({ code = 0, stdout = vim.json.encode(replies(path)), stderr = '' })
    return {}
  end
  return paths, function()
    vim.system = real
  end
end

local PROJECT = 40

--- @param over table?
local function row(iid, base, head, over)
  return vim.tbl_extend('force', {
    iid = iid,
    title = 'merge ' .. iid,
    state = 'opened',
    draft = false,
    target_branch = base,
    source_branch = head,
    source_project_id = PROJECT,
    target_project_id = PROJECT,
  }, over or {})
end

--- @param over table? what to say about the merge request being read
local function request_item(over)
  return {
    project = 'a/b',
    repo = {},
    node = vim.tbl_extend('force', {
      number = 3,
      title = 'merge 3',
      state = 'OPEN',
      isDraft = false,
      baseRefName = 'b',
      headRefName = 'c',
      isCrossRepository = false,
    }, over or {}),
  }
end

--- @param one table
--- @param replies fun(path: string): table
local function derived(one, replies)
  local got, done = nil, false
  local paths, restore = serving(replies)
  glab.stack({ project = 'a/b', collection = 'prs' }, one, { desc = 'x' }, function(s)
    got, done = s, true
  end)
  -- `request` answers through vim.schedule, so the loop has to be pumped.
  vim.wait(2000, function()
    return done
  end, 5)
  restore()
  return got, paths
end

--- @param path string
local function filtered(path)
  return path:match('source_branch=([^&]+)'), path:match('target_branch=([^&]+)')
end

describe('glab.stack', function()
  it('chains a page that came back short, and asks nothing more', function()
    local held, paths = derived(request_item(), function()
      return { row(1, 'main', 'a'), row(2, 'a', 'b'), row(3, 'b', 'c'), row(4, 'c', 'd') }
    end)
    assert.equals(1, #paths)
    assert.same({ 1, 2, 3, 4 }, numbers(assert(held).layers))
    assert.equals(3, held.position)
    assert.is_nil(held.number)
  end)

  it('walks where a full page says nothing about what follows it', function()
    local rings = {}
    local held, paths = derived(request_item(), function(path)
      local source, target = filtered(path)
      if not source and not target then
        local page = {}
        for i = 1, 100 do
          page[i] = row(1000 + i, 'main', 'x' .. i)
        end
        return page
      end
      if source then
        rings[#rings + 1] = 'under ' .. source
        return ({ b = { row(2, 'a', 'b') }, a = { row(1, 'main', 'a') } })[source] or {}
      end
      rings[#rings + 1] = 'over ' .. target
      return ({ c = { row(4, 'c', 'd') } })[target] or {}
    end)

    -- The page, then a ring of two calls per layer either side. A ring fires
    -- both at once, so which of the pair answers first is not fixed.
    assert.equals(7, #paths)
    table.sort(rings)
    assert.same({
      'over c',
      'over d',
      'over d',
      'under a',
      'under b',
      'under main',
    }, rings)
    assert.same({ 1, 2, 3, 4 }, numbers(assert(held).layers))
    assert.equals(3, held.position)
  end)

  it("drops a fork's merge request, which is on another project", function()
    local held = derived(request_item(), function()
      return {
        row(1, 'main', 'b', { source_project_id = 99 }),
        row(2, 'main', 'b'),
        row(3, 'b', 'c'),
      }
    end)
    assert.same({ 2, 3 }, numbers(assert(held).layers))
  end)

  it('names a fork rather than ordering it', function()
    local held = derived(request_item(), function()
      return { row(3, 'b', 'c'), row(8, 'c', 'x'), row(9, 'c', 'y') }
    end)
    assert.same({ 8, 9 }, assert(held).forks)
  end)

  it('reads a draft out of the flag rather than the title', function()
    local held = derived(request_item(), function()
      return { row(2, 'main', 'b', { draft = true }), row(3, 'b', 'c') }
    end)
    local layers = assert(held).layers
    assert.is_true(layers[1].isDraft)
    assert.equals('OPEN', layers[1].state)
    assert.is_false(layers[2].isDraft)
  end)

  it('asks nothing at all about a merge request from a fork', function()
    local held, paths = derived(request_item({ isCrossRepository = true }), function()
      return {}
    end)
    assert.equals(0, #paths)
    assert.is_nil(held)
  end)

  it('draws no stack for a merge request standing alone', function()
    local held = derived(request_item(), function()
      return { row(3, 'b', 'c') }
    end)
    assert.is_nil(held)
  end)
end)
