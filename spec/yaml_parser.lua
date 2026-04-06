local parser = vim.env.FORGE_TEST_RTP
if not parser or parser == '' then
  return
end

local path = parser .. '/parser/yaml.so'
if not vim.uv.fs_stat(path) then
  return
end

local ok, err = vim.treesitter.language.add('yaml', { path = path })
assert(ok, err)
