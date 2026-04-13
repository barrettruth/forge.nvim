# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and Codeberg/Gitea/Forgejo —
without leaving your editor.

## Features

- Automatic forge detection from git remote (`gh`, `glab`, `tea`)
- PR lifecycle: list, create, checkout, worktree,, merge, approve, and more
- Issue management: list, browse, close/reopen, state filtering
- CI/CD: view runs per-branch or repo-wide, stream logs, filter by status
- Local git sections for branches, commits, and worktrees with branch/commit
  `git show`, switching, and forge web actions
- File/line permalink generation and yanking

## Requirements

- Neovim 0.10.0+
- tree-sitter `yaml` parser for YAML issue form templates
- At least one forge CLI: [`gh`](https://cli.github.com/),
  [`glab`](https://gitlab.com/gitlab-org/cli), or
  [`tea`](https://gitea.com/gitea/tea)

Optional:

- [fzf-lua](https://github.com/ibhagwan/fzf-lua) for interactive picker
  workflows

Direct `:Forge` action commands work without `fzf-lua`. Install it if you want
the interactive picker UI opened by mappings such as `<Plug>(forge)` or
`require('forge').open()`.

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/forge.nvim):

```
luarocks install forge.nvim
```

## Documentation

```vim
:help forge.nvim
```
