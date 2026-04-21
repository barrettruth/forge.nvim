local M = {}

function M.forge_name()
  local ok, forge = pcall(require, 'forge')
  if not ok or type(forge) ~= 'table' or type(forge.detect) ~= 'function' then
    return nil
  end
  local detected = forge.detect()
  if type(detected) ~= 'table' or type(detected.name) ~= 'string' or detected.name == '' then
    return nil
  end
  return detected.name
end

return M
