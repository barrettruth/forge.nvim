# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and Codeberg/Gitea/Forgejo —
without leaving your editor.

## Features

- Automatic forge detection from git remote (`gh`, `glab`, `tea`)
- Legible `:Forge` root workflow with route descriptions for forge and local git
  sections
- PR lifecycle: list, create (compose buffer with template discovery, diff stat,
  reviewers), checkout, worktree, review, merge, approve, close/reopen, draft
  toggle
- Issue management: list, browse, close/reopen, state filtering
- CI/CD: view runs per-branch or repo-wide, stream logs, filter by status
- Code review via [diffs.nvim](https://github.com/barrettruth/diffs.nvim) with
  unified/split toggle and quickfix navigation
- Local git sections for branches, commits, and worktrees with branch/commit
  review, `git show`, switching, and forge web actions
- File/line permalink generation and yanking
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) pickers with contextual
  keybinds
- Pluggable source registration for custom or self-hosted forges

## Requirements

- Neovim 0.10.0+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- At least one forge CLI: [`gh`](https://cli.github.com/),
  [`glab`](https://gitlab.com/gitlab-org/cli), or
  [`tea`](https://gitea.com/gitea/tea)
- (Optional) [diffs.nvim](https://github.com/barrettruth/diffs.nvim) for review
  mode
- (Optional) [vim-fugitive](https://github.com/tpope/vim-fugitive) for split
  diff and fugitive keymaps
- (Optional) tree-sitter `yaml` parser for YAML issue form templates

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

## Root workflow

`:Forge` opens a workflow surface, not just a route list. Root entries describe
the top-level sections with label-only rows while keeping the nested picker
behavior and workflow details in the help docs.

## FAQ

**Q: How do I configure forge.nvim?**

Configure via `vim.g.forge` before the plugin loads. All fields are optional:

```lua
vim.g.forge = {
  sections = { releases = false },
  routes = { browse = 'browse.branch' },
  keys = { commit = { browse = '<c-x>', yank = '<c-y>', refresh = '<c-r>' } },
  sources = { gitlab = { hosts = { 'gitlab.mycompany.com' } } },
  display = { icons = { open = '', merged = '', closed = '' } },
}
```

**Q: How do I install with lazy.nvim?**

```lua
{
  'barrettruth/forge.nvim',
  dependencies = { 'ibhagwan/fzf-lua' },
}
```

**Q: How do I create a PR?**

`<c-g>` to open the picker, select Pull Requests, then `ctrl-a` to compose. Or
from a fugitive buffer: `cpr` (compose), `cpd` (draft), `cpf` (instant from
commits), `cpw` (push and open web).

**Q: What does `:Forge` show by default?**

The root picker shows Pull Requests, Issues, CI, Branches, Commits, Worktrees,
Browse, and Releases. Each root row includes its scope and primary actions so
the local git sections read as first-class workflows. Customize the list with
`vim.g.forge.sections` and change where a section goes with
`vim.g.forge.routes`.

**Q: Does review mode require diffs.nvim?**

Yes. Without [diffs.nvim](https://github.com/barrettruth/diffs.nvim), diff
actions and review toggling are unavailable.

**Q: How does forge detection work?**

forge.nvim reads the `origin` remote URL and matches against known hosts and any
custom `sources.<name>.hosts` entries. The first match wins, and the CLI must be
in `$PATH`.
