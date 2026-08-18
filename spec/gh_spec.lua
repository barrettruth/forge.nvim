local gh = require('forge.gh')

--- Capture the argv rather than the request: which flag a variable is sent
--- under is the whole of what is being tested, and it is settled before gh runs.
--- @return string[][] sent, fun() restore
local function watching()
  local sent = {}
  local real = vim.system
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd)
    sent[#sent + 1] = cmd
    return {}
  end
  return sent, function()
    vim.system = real
  end
end

--- The flag `name` was sent under, and what went with it.
--- @param cmd string[]
--- @param name string
--- @return string? flag
--- @return string? value
local function under(cmd, name)
  for i = 1, #cmd - 1 do
    local value = cmd[i + 1]:match('^' .. name .. '=(.*)$')
    if value then
      return cmd[i], value
    end
  end
end

--- @param variables table
--- @return string[] argv
local function ask(variables)
  local sent, restore = watching()
  gh.graphql({ desc = 'x', query = 'query {}', variables = variables }, function() end)
  restore()
  return sent[1]
end

describe('how a variable reaches gh', function()
  it('sends what someone wrote as a string, whatever it holds', function()
    --- "@" is a filename to --field, and "{owner}" is expanded by it. Neither
    --- may be reachable from a body, a title or a search.
    for _, prose in ipairs({
      'handles {owner} correctly',
      '@notes.md and {ok}',
      '@someone asked for this',
      'local t = {}',
      'fix {count} handling',
    }) do
      local flag, value = under(ask({ body = prose }), 'body')
      assert.equals('-f', flag)
      assert.equals(prose, value)
    end
  end)

  it('sends the slug placeholders as placeholders, since gh expands those', function()
    local cmd = ask({ owner = '{owner}', repo = '{repo}' })
    assert.equals('-F', under(cmd, 'owner'))
    assert.equals('-F', under(cmd, 'repo'))
  end)

  it('sends a repository actually named "123" as a name', function()
    local cmd = ask({ owner = '123', repo = '456' })
    assert.equals('-f', under(cmd, 'owner'))
    assert.equals('-f', under(cmd, 'repo'))
  end)

  it('sends a number as a number, which is the only way Int takes it', function()
    assert.equals('-F', under(ask({ number = 27 }), 'number'))
  end)

  it('carries a list one item at a time', function()
    local cmd = ask({ labels = { 'bug', 'ui' } })
    local seen = {}
    for i = 1, #cmd - 1 do
      if cmd[i + 1]:find('^labels%[%]=') then
        seen[#seen + 1] = cmd[i] .. ' ' .. cmd[i + 1]
      end
    end
    assert.same({ '-f labels[]=bug', '-f labels[]=ui' }, seen)
  end)
end)
