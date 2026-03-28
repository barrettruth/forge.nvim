#!/bin/sh
set -eu

nix develop .#ci --command stylua --check .
git ls-files '*.lua' | xargs nix develop .#ci --command selene --display-style quiet
nix develop .#ci --command prettier --check .
nix fmt -- --ci
nix develop .#ci --command lua-language-server --check lua --configpath "$(pwd)/.luarc.json" --checklevel=Warning
nix develop .#ci --command vimdoc-language-server check doc/
nix develop .#ci --command busted
