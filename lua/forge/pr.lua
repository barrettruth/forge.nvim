local M = {}

---@param f forge.Forge
---@param num string
---@param scope? forge.Scope
---@return forge.PRState
function M.pr_state(f, num, scope)
  return require('forge.state').pr_state(f, num, scope)
end

---@param num string
---@param state forge.PRState
---@param scope? forge.Scope
---@return forge.PRState
function M.set_pr_state(num, state, scope)
  return require('forge.state').set_pr_state(num, state, scope)
end

---@param num? string
---@param scope? forge.Scope
function M.clear_pr_state(num, scope)
  require('forge.state').clear_pr_state(num, scope)
end

---@param opts forge.PRActionOpts?
function M.pr(opts)
  require('forge.action_target').pr(opts)
end

---@param opts forge.ReviewOpts?
function M.review(opts)
  require('forge.action_target').review(opts)
end

---@param opts forge.PRActionOpts?
function M.pr_ci(opts)
  require('forge.action_target').pr_ci(opts)
end

---@param opts forge.CreatePROpts?
function M.create_pr(opts)
  require('forge.creation').create_pr(opts)
end

---@param opts forge.CurrentPROpts?
---@return forge.PRRef?, forge.CmdError?
function M.current_pr(opts)
  return require('forge.resolve').current_pr(opts)
end

return M
