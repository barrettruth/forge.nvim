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

Optional:

- [fzf-lua](https://github.com/ibhagwan/fzf-lua) for interactive picker
  workflows

Direct `:Forge` action commands work without `fzf-lua`. Install it only if you
want the interactive picker UI.

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/forge.nvim):

```
luarocks install forge.nvim
```

## Usage

Use direct commands for action-oriented workflows:

```vim
:Forge pr create
:Forge pr checkout 123
:Forge issue create
:Forge issue edit 42
:Forge ci log 456
```

If you use `fzf-lua`, you can also bind the picker surface with
`require('forge').open()`:

```lua
vim.keymap.set('n', '<leader>gg', function()
  require('forge').open()
end, { desc = 'forge' })
```

## Documentation

```vim
:help forge.nvim
```
