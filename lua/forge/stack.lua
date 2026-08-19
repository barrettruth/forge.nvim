--- Deriving a stack from a set of pull requests. No network and no editor.

local M = {}

--- How many layers to follow before giving up.
M.MAX = 50

--- One pull request, reduced to what a chain is built out of.
--- @class forge.stack.Pull
--- @field number integer
--- @field title string
--- @field state string in forge's words, as every backend answers them
--- @field isDraft boolean
--- @field base string the branch it merges into
--- @field head string the branch it merges from

--- The chain holding `number`, bottom first.
---
--- Two sharing a base is a fork, and which one continues the chain is unknown,
--- so it is named rather than picked.
--- @param pulls forge.stack.Pull[]
--- @param number integer
--- @return forge.stack.Pull[]? ordered nil where `number` is not among `pulls`
--- @return integer[]? forks what it forks into above, where it does
function M.chain(pulls, number)
  local by_head, children, start = {}, {}, nil
  for _, pull in ipairs(pulls) do
    -- One branch may carry two open pull requests, into different bases.
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
  -- Nothing a forge answers is trusted to be acyclic.
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

--- A chain as a stack, or nothing where there is none to draw. One layer is no
--- stack unless it forks, which is worth saying.
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
