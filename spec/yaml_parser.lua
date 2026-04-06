local system = vim.trim(
  vim.fn.system({ 'nix', 'eval', '--impure', '--raw', '--expr', 'builtins.currentSystem' })
)
if vim.v.shell_error ~= 0 or system == '' then
  return
end

local expr = ('let flake = builtins.getFlake %q; system = %q; pkgs = flake.inputs.nixpkgs.legacyPackages.${system}; in toString pkgs.vimPlugins.nvim-treesitter-parsers.yaml'):format(
  vim.fn.getcwd(),
  system
)
local parser = vim.trim(vim.fn.system({ 'nix', 'eval', '--impure', '--raw', '--expr', expr }))
if vim.v.shell_error == 0 and parser ~= '' then
  pcall(vim.treesitter.language.add, 'yaml', { path = parser .. '/parser/yaml.so' })
end
