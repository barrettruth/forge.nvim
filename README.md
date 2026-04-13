# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and Codeberg/Gitea/Forgejo —
without leaving your editor.

## Features

- Pull request workflows: list, create, checkout, edit, worktree, merge,
  approve, draft/ready
- Issue workflows: list, create, edit, browse, close/reopen
- CI/CD workflows: list runs, filter by status, inspect summaries, stream logs
- Local git sections for branches, commits, and worktrees
- Forge web browsing and file/line permalinks
- Automatic forge detection from git remote via `gh`, `glab`, or `tea`

## Requirements

- Neovim 0.10.0+
- tree-sitter `yaml` parser for YAML issue form templates
- At least one forge CLI: [`gh`](https://cli.github.com/),
  [`glab`](https://gitlab.com/gitlab-org/cli), or
  [`tea`](https://gitea.com/gitea/tea)
- Optional: [fzf-lua](https://github.com/ibhagwan/fzf-lua) for interactive
  picker and listing workflows

Direct `:Forge` action commands work without `fzf-lua`. Install it if you want
the interactive picker UI and list workflows. The `:Forge` command surface
covers explicit forge actions such as create/edit/browse/close/reopen/approve/
merge/draft/ready, while picker-only actions remain list-scoped controls and
local navigation workflows.

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
