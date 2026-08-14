local M = {}

--- The directory a request is made from.
---
--- The buffer's own, when it has a file behind it, so a file opened from
--- another repository is asked about there rather than wherever nvim was
--- started. A buffer with no file, forge's own included, falls back to the
--- working directory.
--- @return string
function M.dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' or name:find('^%w[%w+.-]*://') then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(name)
end

return M
