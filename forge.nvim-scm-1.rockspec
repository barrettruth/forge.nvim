rockspec_format = '3.0'
package = 'forge.nvim'
version = 'scm-1'

source = {
  url = 'git+https://github.com/barrettruth/forge.nvim.git',
}

description = {
  summary = 'Forge-agnostic git workflow for Neovim',
  homepage = 'https://github.com/barrettruth/forge.nvim',
  license = 'MIT',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
  'busted >= 2.1.1',
}

test = {
  type = 'busted',
}

build = {
  type = 'builtin',
}
