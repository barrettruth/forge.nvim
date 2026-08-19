--- A buffer text is written in for forge to send.
---
--- ":w" submits, as it does for any 'acwrite' buffer. Closing discards.
--- Treating the close as the signal is git's convention. It only works because
--- git launched the editor and waits on it. guh tried it anyway and has two
--- open bugs from it.
---
--- ":wq" and "ZZ" therefore submit without closing. Vim reads 'modified' again
--- to decide whether the quit may go ahead, and the request has not come back
--- by then. 'modified' guards what was typed. A caller clears it only once the
--- forge has accepted the write.

local view = require('forge.view')

local M = {}

--- The first line, then a blank line, then the rest: a commit message's shape.
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
--- `name` is a `forge://` one so that it reads as forge's. `uri.parse` rejects
--- it. That keeps every `forge://*` autocmd off a buffer that is not a view.
--- @param opts forge.Compose
--- @return integer buf
function M.open(opts)
  local buf = view.buffer_named(opts.name) or vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, opts.name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text or '', '\n'))
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = opts.filetype
  -- Wiped the moment nothing shows it. It is never staler than what it was
  -- opened from. "wipe" costs the text on ":hide". "hide" would keep it, but a
  -- buffer that hides is never abandoned, and 'modified' would then lose its
  -- refusal of ":q", ":bd" and ":enew" too. One quiet way to lose text beats
  -- three.
  vim.bo[buf].bufhidden = 'wipe'

  -- One handler however many times this is opened. A buffer still on screen is
  -- found again by name. A second handler would send its text twice.
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
  -- The item's own winbar with its state swapped for the mode. A rendered
  -- string rather than forge.view's `%{}` template. Every part of it is
  -- forge's own word, and this buffer is never in a second window.
  vim.wo[0][0].winbar = ('%%#Title#%s%%* %%#Tag#%s%%* %%#%s#%s%%*'):format(
    opts.label or '',
    opts.tag or '',
    opts.mode_hl or 'ModeMsg',
    opts.mode
  )
  return buf
end

return M
