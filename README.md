# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and more — without leaving
your editor.

## Features

- Forge detection from git remote (GitHub via `gh`, GitLab via `glab`,
  Codeberg/Gitea/Forgejo via `tea`)
- PR lifecycle: list, create, checkout, review, merge, approve, close/reopen,
  draft toggle
- Issue management: list, browse, close/reopen
- CI/CD: view runs, stream logs, filter by status
- PR compose buffer with diff stat, template discovery, and syntax highlighting
- Code review via [diffs.nvim](https://github.com/barrettruth/diffs.nvim)
  unified/split diff with quickfix navigation
- Commit browsing with checkout, diff review, and URL yanking
- Branch browsing with diff review and remote links
- Worktree creation from PRs
- File/line permalink generation (commit and branch URLs)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) pickers with contextual
  keybinds throughout

## Dependencies

- Neovim 0.10.0+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- At least one forge CLI:
  - [`gh`](https://cli.github.com/) for GitHub
  - [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab
  - [`tea`](https://gitea.com/gitea/tea) for Codeberg/Gitea/Forgejo
- [vim-fugitive](https://github.com/tpope/vim-fugitive) (optional, for fugitive
  keymaps)
- [diffs.nvim](https://github.com/barrettruth/diffs.nvim) (optional, for review
  mode)

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

## FAQ

**Q: How do I create a PR?**

Press `<c-g>` to open the forge picker, select "Pull Requests", then `<ctrl-a>`
to create. Or from a fugitive buffer: `cpr` (create), `cpd` (draft), `cpf`
(instant), `cpw` (web).

**Q: Does forge.nvim support review diffs?**

Yes, with [diffs.nvim](https://github.com/barrettruth/diffs.nvim) installed.
Select a PR and press `<ctrl-d>` to enter review mode with unified diff. Press
`s` to toggle split/unified view. Navigate files with `]q`/`[q`.
