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
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- At least one forge CLI: [`gh`](https://cli.github.com/),
  [`glab`](https://gitlab.com/gitlab-org/cli), or
  [`tea`](https://gitea.com/gitea/tea)

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
