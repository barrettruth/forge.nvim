# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and Codeberg/Gitea/Forgejo —
without leaving your editor.

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
- (Optionally) [fzf-lua](https://github.com/ibhagwan/fzf-lua) >= 0.40 for the
  picker UI
- (Optionally) a code reviewing plugin:
  [`diffview.nvim`](https://github.com/sindrets/diffview.nvim),
  [`codediff.nvim`](https://github.com/esmuellert/codediff.nvim), or
  [`diffs.nvim`](https://github.com/barrettruth/diffs.nvim)

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
