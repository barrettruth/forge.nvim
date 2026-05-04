# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and Forgejo/Gitea/Codeberg —
without leaving your editor.

> [!NOTE]
> Due to GitHub's historic unreliability, development, issues, and pull requests
> have moved to [Forgejo](https://git.barrettruth.com/barrettruth/forge.nvim).
> See `:help forge.nvim-forgejo` for canonical project links.

## Features

- Work with PRs: list, create, review, open/close, draft, merge and more
- Issue workflows: list, create, edit, browse, close/reopen
- CI/CD: list runs, filter by status, inspect summaries, stream logs, etc.

## Requirements

- Neovim 0.10.0+
- [tree-sitter-yaml](https://github.com/ikatyang/tree-sitter-yaml) for YAML
  issue form templates
- At least one forge CLI: [`gh`](https://cli.github.com/),
  [`glab`](https://gitlab.com/gitlab-org/cli), or
  [`tea`](https://gitea.com/gitea/tea)
- (Optionally) [fzf-lua](https://github.com/ibhagwan/fzf-lua) >= 0.40 for
  interactive built-in routes (`require('forge').open()`) and the picker API
  (`require('forge.picker').pick()`)
- (Optionally) a code reviewing plugin:
  [`diffview.nvim`](https://github.com/sindrets/diffview.nvim),
  [`codediff.nvim`](https://github.com/esmuellert/codediff.nvim), or
  [`diffs.nvim`](https://git.barrettruth.com/barrettruth/diffs.nvim)

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  'https://git.barrettruth.com/barrettruth/forge.nvim',
})
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/forge.nvim):

```
luarocks install forge.nvim
```

## Releases

Stable releases are cut from manual tags named `v0.x.y`. Pushing one of those
tags publishes the tagged version to LuaRocks.

Nightly prereleases are automated snapshots from `main`. They are published as
the rolling prerelease `nightly`, with the current short commit hash in the
release title, and are kept off the stable LuaRocks channel.

## Documentation

```vim
:help forge.nvim
```
