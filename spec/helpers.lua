vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.packpath = {}

--- Neovim bundles parsers for c, lua, vim, vimdoc, markdown and query, but
--- not yaml, which reading a github issue form needs. The dev shell supplies
--- one; without it the form tests would quietly fall back to finding nothing.
local yaml = vim.env.FORGE_YAML_PARSER
if yaml and yaml ~= '' then
  vim.opt.runtimepath:prepend(yaml)
end

return {}
