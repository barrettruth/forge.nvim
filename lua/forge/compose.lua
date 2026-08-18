--- A buffer text is written in for forge to send.
---
--- Writing the buffer is the submit, as it is for any 'acwrite' buffer: that is
--- what :w means for a netrw file over scp, for oil.nvim, for :Gwrite. The
--- other reading — that closing is the signal and :w merely a step — is git's,
--- and git only means it because it launched the editor and is waiting on it.
--- Nothing launches this one, and the plugin that tried has two open bugs from
--- it: a bare :w performing the action anyway, and a submit hung on a teardown
--- autocmd that silently ate the text whenever a config kept the buffer alive.
---
--- So :w submits, and ZQ and :q! discard, both of them out of Vim rather than
--- out of forge. :wq and ZZ submit without closing: Vim reads 'modified' again
--- to decide whether the quit half may go ahead, and the request has not come
--- back by then. 'modified' is what guards what was typed, so a caller clears
--- it when github says yes and never before.

local view = require('forge.view')

local M = {}

--- The first line, then a blank line, then the rest — a commit message's
--- shape, which is the one everybody already knows.
--- @param lines string[]
--- @return string subject
--- @return string body
function M.split(lines)
  local body = {}
  for i = 2, #lines do
    if #body > 0 or vim.trim(lines[i]) ~= '' then
      body[#body + 1] = lines[i]
    end
  end
  return vim.trim(lines[1] or ''), table.concat(body, '\n')
end

--- @class forge.Compose
--- @field name string what to call the buffer
--- @field text string what it opens holding
--- @field filetype string
--- @field desc string what the write autocmd is for
--- @field label string the winbar's first segment, as the item spells it
--- @field tag string
--- @field mode string the word standing where the item's state would
--- @field mode_hl string? the group that word is drawn in
--- @field split boolean? beside what is being written about, rather than over it
--- @field on_write fun(lines: string[], buf: integer)

--- Open one.
---
--- `name` is a `forge://` one for the sake of reading it, but |uri.parse| does
--- not know it, which is what keeps every `forge://*` autocmd off a buffer that
--- is not a view.
--- @param opts forge.Compose
--- @return integer buf
function M.open(opts)
  local buf = view.buffer_named(opts.name) or vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, opts.name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text or '', '\n'))
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = opts.filetype
  --- Gone the moment nothing shows it, so it is only ever as old as what it was
  --- opened from. 'modified' refuses ":q", ":bd" and ":enew", which leaves
  --- ":hide" throwing the text away as surely as ":q!" does. "hide" would keep
  --- it, but a buffer that hides is never abandoned, so it costs the refusal on
  --- all three of those and leaves ":q!" holding a buffer with its contents
  --- unloaded. One quiet way to lose text beats three.
  vim.bo[buf].bufhidden = 'wipe'

  --- One handler however many times this is opened: a buffer still on screen is
  --- found again by name, and a second handler would send what it holds twice.
  vim.api.nvim_clear_autocmds({ event = 'BufWriteCmd', buffer = buf })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    desc = opts.desc,
    callback = function()
      opts.on_write(vim.api.nvim_buf_get_lines(buf, 0, -1, false), buf)
    end,
  })

  if opts.split then
    vim.cmd.split()
  end
  vim.cmd.buffer(buf)
  --- The item's own winbar with its state swapped for the mode, so this reads
  --- as something the item is doing rather than another kind of thing. Every
  --- part of it is forge's own word, so a `%{}` would be reading nothing a
  --- template could not already say. `ModeMsg` by default because that is what
  --- a mode is drawn in, and because a state's colour would put the word in a
  --- vocabulary it does not belong to.
  vim.wo[0][0].winbar = ('%%#Title#%s%%* %%#Tag#%s%%* %%#%s#%s%%*'):format(
    opts.label or '',
    opts.tag or '',
    opts.mode_hl or 'ModeMsg',
    opts.mode
  )
  return buf
end

return M
