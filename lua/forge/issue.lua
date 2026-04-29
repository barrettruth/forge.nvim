local M = {}

---@param num string
---@param ref? forge.Scope
function M.edit_issue(num, ref)
  require('forge.ops').issue_edit({
    num = num,
    scope = ref,
  })
end

---@param opts forge.CreateIssueOpts?
function M.create_issue(opts)
  require('forge.creation').create_issue(opts)
end

---@return string[]
function M.template_slugs()
  return require('forge.creation').template_slugs()
end

return M
