--- Deriving a stack from a set of pull requests. No network and no editor, so
--- a forge that registers stacks and one that does not both end up here.

local M = {}

--- How many layers to follow before giving up. A chain longer than this is a
--- forge answering something forge cannot draw, not a stack anybody wrote.
M.MAX = 50

--- One pull request, reduced to what a chain is built out of. `state` and
--- `isDraft` are separate for the same reason they are on a list's nodes: which
--- of them a draft is drawn as belongs to |forge.Spec|, not to a forge.
--- @class forge.stack.Pull
--- @field number integer
--- @field title string
--- @field state string in forge's words, as every backend answers them
--- @field isDraft boolean
--- @field base string the branch it merges into
--- @field head string the branch it merges from

--- The chain holding `number`, bottom first.
---
--- Down follows each pull request's single base and is never ambiguous. Up can
--- meet two sharing a base, which is a fork: the layer above is genuinely
--- unknown, so stop and name them rather than pick one.
--- @param pulls forge.stack.Pull[]
--- @param number integer
--- @return forge.stack.Pull[]? ordered nil where `number` is not among `pulls`
--- @return integer[]? forks what it forks into above, where it does
function M.chain(pulls, number)
  local by_head, children, start = {}, {}, nil
  for _, pull in ipairs(pulls) do
    -- The first wins. github serves two open pull requests on one branch where
    -- they merge into different bases, and a later one would rewrite the chain
    -- underneath itself.
    by_head[pull.head] = by_head[pull.head] or pull
    children[pull.base] = children[pull.base] or {}
    table.insert(children[pull.base], pull)
    if pull.number == number then
      start = pull
    end
  end
  if not start then
    return nil
  end

  local ordered = { start }
  -- Nothing the forge answers is trusted to be acyclic.
  local seen = { [start.number] = true }

  local below = start
  while #ordered < M.MAX do
    local under = by_head[below.base]
    if not under or seen[under.number] then
      break
    end
    seen[under.number] = true
    table.insert(ordered, 1, under)
    below = under
  end

  local forks
  local above = start
  while #ordered < M.MAX do
    local over = children[above.head] or {}
    if #over > 1 then
      forks = vim.tbl_map(function(pull)
        return pull.number
      end, over)
      table.sort(forks)
      break
    end
    if #over == 0 or seen[over[1].number] then
      break
    end
    seen[over[1].number] = true
    ordered[#ordered + 1] = over[1]
    above = over[1]
  end

  return ordered, forks
end

--- Which layer of `ordered` is `number`, counting from the bottom.
--- @param ordered forge.stack.Pull[]
--- @param number integer
--- @return integer
function M.position(ordered, number)
  for i, pull in ipairs(ordered) do
    if pull.number == number then
      return i
    end
  end
  return 1
end

--- A chain as a stack, or nothing where there is no stack to draw.
---
--- One layer is not a stack. A lone pull request that forks above is, because
--- the fork is the thing worth saying.
--- @param pulls forge.stack.Pull[]
--- @param number integer
--- @return forge.Stack?
function M.of(pulls, number)
  local ordered, forks = M.chain(pulls, number)
  if not ordered or (#ordered < 2 and not forks) then
    return nil
  end
  return {
    layers = ordered,
    position = M.position(ordered, number),
    forks = forks,
  }
end

return M
