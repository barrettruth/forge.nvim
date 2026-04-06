#!/bin/sh
set -eu

SYSTEM=$(nix eval --impure --raw --expr builtins.currentSystem)
FORGE_TEST_RTP=$(
  nix eval --impure --raw --expr \
    "let flake = builtins.getFlake \"$PWD\"; pkgs = flake.inputs.nixpkgs.legacyPackages.${SYSTEM}; in toString pkgs.vimPlugins.nvim-treesitter-parsers.yaml"
)
export FORGE_TEST_RTP

nix develop .#ci --command stylua --check .
git ls-files '*.lua' | xargs nix develop .#ci --command selene --display-style quiet
nix develop .#ci --command prettier --check .
nix fmt -- --ci
nix develop .#ci --command lua-language-server --check lua --configpath "$(pwd)/.luarc.json" --checklevel=Warning
nix develop .#ci --command vimdoc-language-server check doc/
nix develop .#ci --command busted
