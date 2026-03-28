# forge.nvim

**Forge-agnostic git workflow for Neovim**

PR, issue, and CI workflows across GitHub, GitLab, and more — without leaving
your editor.

## Features

- Automatic forge detection from git remote (GitHub via `gh`, GitLab via `glab`,
  Codeberg/Gitea/Forgejo via `tea`)
- PR lifecycle: list, create (compose buffer with template discovery, diff stat,
  reviewers), checkout, worktree, review diff, merge, approve, close/reopen,
  draft toggle
- Issue management: list, browse, close/reopen, state filtering
- CI/CD: view runs per-branch or repo-wide, stream logs, filter by status
- Code review via [diffs.nvim](https://github.com/barrettruth/diffs.nvim) with
  unified/split toggle and quickfix navigation
- Commit and branch browsing with checkout, diff, and URL generation
- File/line permalink generation and yanking (commit and branch URLs)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) pickers with contextual
  keybinds
- Pluggable source registration for custom or self-hosted forges

## Dependencies

- Neovim 0.10.0+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- At least one forge CLI:
  - [`gh`](https://cli.github.com/) for GitHub
  - [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab
  - [`tea`](https://gitea.com/gitea/tea) for Codeberg/Gitea/Forgejo
- [vim-fugitive](https://github.com/tpope/vim-fugitive) (optional, for fugitive
  keymaps and split diff)
- [diffs.nvim](https://github.com/barrettruth/diffs.nvim) (optional, for review
  mode)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'barrettruth/forge.nvim',
  dependencies = { 'ibhagwan/fzf-lua' },
}
```

### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
MiniDeps.add({
  source = 'barrettruth/forge.nvim',
  depends = { 'ibhagwan/fzf-lua' },
})
```

### [luarocks](https://luarocks.org/modules/barrettruth/forge.nvim)

```
luarocks install forge.nvim
```

### Manual

```sh
git clone https://github.com/barrettruth/forge.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/forge.nvim
```

## Usage

forge.nvim works through two entry points: the `:Forge` command and the `<c-g>`
picker.

`:Forge` with no arguments (or `<c-g>`) opens the top-level picker — PRs,
issues, CI, commits, branches, worktrees, and browse actions. Each sub-picker
has contextual keybinds shown in the fzf header.

PR creation opens a compose buffer (markdown) pre-filled from commit messages
and repo templates. First line is the title, everything after the blank line is
the body. Draft, reviewers, and base branch are set in the HTML comment block
below. Write (`:w`) to push and create.

## Configuration

Configure via `vim.g.forge`. All fields are optional — defaults shown below.

```lua
vim.g.forge = {
  ci = { lines = 10000 },
  sources = {},
  keys = {
    picker = '<c-g>',
    next_qf = ']q',  prev_qf = '[q',
    next_loc = ']l',  prev_loc = '[l',
    review_toggle = 's',
    terminal_open = 'gx',
    fugitive = {
      create = 'cpr', create_draft = 'cpd',
      create_fill = 'cpf', create_web = 'cpw',
    },
  },
  picker_keys = {
    pr = {
      checkout = 'default', diff = 'ctrl-d', worktree = 'ctrl-w',
      checks = 'ctrl-t', browse = 'ctrl-x', manage = 'ctrl-e',
      create = 'ctrl-a', toggle = 'ctrl-o', refresh = 'ctrl-r',
    },
    issue = { browse = 'default', close_reopen = 'ctrl-s', toggle = 'ctrl-o', refresh = 'ctrl-r' },
    checks = { log = 'default', browse = 'ctrl-x', failed = 'ctrl-f', passed = 'ctrl-p', running = 'ctrl-n', all = 'ctrl-a' },
    ci = { log = 'default', browse = 'ctrl-x', refresh = 'ctrl-r' },
    commits = { checkout = 'default', diff = 'ctrl-d', browse = 'ctrl-x', yank = 'ctrl-y' },
    branches = { diff = 'ctrl-d', browse = 'ctrl-x' },
  },
  display = {
    icons = { open = '+', merged = 'm', closed = 'x', pass = '*', fail = 'x', pending = '~', skip = '-', unknown = '?' },
    widths = { title = 45, author = 15, name = 35, branch = 25 },
    limits = { pulls = 100, issues = 100, runs = 30 },
  },
}
```

Set `keys = false` to disable all keymaps. Set `picker_keys = false` to disable
all picker keybinds. Set any individual key to `false` to disable it.

### Examples

Disable quickfix/loclist keymaps:

```lua
vim.g.forge = {
  keys = { next_qf = false, prev_qf = false, next_loc = false, prev_loc = false },
}
```

Nerd font icons:

```lua
vim.g.forge = {
  display = {
    icons = { open = '', merged = '', closed = '', pass = '', fail = '', pending = '', skip = '', unknown = '' },
  },
}
```

Self-hosted GitLab:

```lua
vim.g.forge = {
  sources = { gitlab = { hosts = { 'gitlab.mycompany.com' } } },
}
```

Override PR picker bindings:

```lua
vim.g.forge = {
  picker_keys = { pr = { checkout = 'ctrl-o', diff = 'default' } },
}
```

## Commands

`:Forge` with no arguments opens the top-level picker. Subcommands:

| Command                                       | Description                       |
| --------------------------------------------- | --------------------------------- |
| `:Forge pr`                                   | List open PRs                     |
| `:Forge pr --state={open,closed,all}`         | List PRs by state                 |
| `:Forge pr create [--draft] [--fill] [--web]` | Create PR                         |
| `:Forge pr checkout {num}`                    | Checkout PR branch                |
| `:Forge pr diff {num}`                        | Review PR diff                    |
| `:Forge pr worktree {num}`                    | Fetch PR into worktree            |
| `:Forge pr checks {num}`                      | Show PR checks                    |
| `:Forge pr browse {num}`                      | Open PR in browser                |
| `:Forge pr manage {num}`                      | Merge/approve/close/draft actions |
| `:Forge issue`                                | List all issues                   |
| `:Forge issue --state={open,closed,all}`      | List issues by state              |
| `:Forge issue browse {num}`                   | Open issue in browser             |
| `:Forge issue close {num}`                    | Close issue                       |
| `:Forge issue reopen {num}`                   | Reopen issue                      |
| `:Forge ci`                                   | CI runs for current branch        |
| `:Forge ci --all`                             | CI runs for all branches          |
| `:Forge commit`                               | Browse commits                    |
| `:Forge commit checkout {sha}`                | Checkout commit                   |
| `:Forge commit diff {sha}`                    | Review commit diff                |
| `:Forge commit browse {sha}`                  | Open commit in browser            |
| `:Forge branch`                               | Browse branches                   |
| `:Forge branch diff {name}`                   | Review branch diff                |
| `:Forge branch browse {name}`                 | Open branch in browser            |
| `:Forge worktree`                             | List worktrees                    |
| `:Forge browse [--root] [--commit]`           | Open file/repo/commit in browser  |
| `:Forge yank [--commit]`                      | Yank permalink for file/line      |
| `:Forge review end`                           | End review session                |
| `:Forge review toggle`                        | Toggle split/unified review       |
| `:Forge cache clear`                          | Clear all caches                  |

## Keymaps

### Global

| Key         | Mode | Description                      |
| ----------- | ---- | -------------------------------- |
| `<c-g>`     | n, v | Open forge picker                |
| `]q` / `[q` | n    | Next/prev quickfix entry (wraps) |
| `]l` / `[l` | n    | Next/prev loclist entry (wraps)  |

### Fugitive buffer

Active in `fugitive` filetype buffers when a forge is detected.

| Key   | Description                         |
| ----- | ----------------------------------- |
| `cpr` | Create PR (compose buffer)          |
| `cpd` | Create draft PR                     |
| `cpf` | Create PR from commits (no compose) |
| `cpw` | Push and open web creation          |

### Review

Active during a review session.

| Key | Description               |
| --- | ------------------------- |
| `s` | Toggle unified/split diff |

### Terminal (log buffers)

Active on CI/check log terminals when a URL is available.

| Key  | Description               |
| ---- | ------------------------- |
| `gx` | Open run/check in browser |

## Picker Actions

Keybinds shown in the fzf header. `default` = `enter`.

| Picker       | Key                            | Action                             |
| ------------ | ------------------------------ | ---------------------------------- |
| **PR**       | `enter`                        | Checkout                           |
|              | `ctrl-d`                       | Review diff                        |
|              | `ctrl-w`                       | Worktree                           |
|              | `ctrl-t`                       | Checks                             |
|              | `ctrl-x`                       | Browse                             |
|              | `ctrl-e`                       | Manage (merge/approve/close/draft) |
|              | `ctrl-a`                       | Create new                         |
|              | `ctrl-o`                       | Cycle state (open/closed/all)      |
|              | `ctrl-r`                       | Refresh                            |
| **Issue**    | `enter`                        | Browse                             |
|              | `ctrl-s`                       | Close/reopen                       |
|              | `ctrl-o`                       | Cycle state                        |
|              | `ctrl-r`                       | Refresh                            |
| **Checks**   | `enter`                        | View log (tails if running)        |
|              | `ctrl-x`                       | Browse                             |
|              | `ctrl-f` / `ctrl-p` / `ctrl-n` | Filter: failed / passed / running  |
|              | `ctrl-a`                       | Show all                           |
| **CI**       | `enter`                        | View log (tails if running)        |
|              | `ctrl-x`                       | Browse                             |
|              | `ctrl-r`                       | Refresh                            |
| **Commits**  | `enter`                        | Checkout (detached)                |
|              | `ctrl-d`                       | Review diff                        |
|              | `ctrl-x`                       | Browse                             |
|              | `ctrl-y`                       | Yank hash                          |
| **Branches** | `ctrl-d`                       | Review diff                        |
|              | `ctrl-x`                       | Browse                             |

## Custom Sources

Register a custom forge source for self-hosted or alternative platforms:

```lua
require('forge').register('mygitea', require('my_gitea_source'))
```

Route remotes to your source by host:

```lua
vim.g.forge = {
  sources = { mygitea = { hosts = { 'gitea.internal.dev' } } },
}
```

A source is a table implementing the `forge.Forge` interface. Required fields:
`name` (string), `cli` (string, checked via `executable()`), `kinds`
(`{ issue, pr }`), and `labels` (`{ issue, pr, pr_one, pr_full, ci }`).

Required methods (all receive `self`): `list_pr_json_cmd`,
`list_issue_json_cmd`, `pr_json_fields`, `issue_json_fields`, `view_web`,
`browse`, `browse_root`, `browse_branch`, `browse_commit`, `checkout_cmd`,
`yank_branch`, `yank_commit`, `fetch_pr`, `pr_base_cmd`, `pr_for_branch_cmd`,
`checks_cmd`, `check_log_cmd`, `check_tail_cmd`, `list_runs_json_cmd`,
`list_runs_cmd`, `normalize_run`, `run_log_cmd`, `run_tail_cmd`, `merge_cmd`,
`approve_cmd`, `repo_info`, `pr_state`, `close_cmd`, `reopen_cmd`,
`close_issue_cmd`, `reopen_issue_cmd`, `draft_toggle_cmd`, `create_pr_cmd`,
`create_pr_web_cmd`, `default_branch_cmd`, `template_paths`.

See `lua/forge/github.lua`, `lua/forge/gitlab.lua`, or `lua/forge/codeberg.lua`
for complete implementations. The `forge.Forge` class definition with full type
annotations is in `lua/forge/init.lua`.

### Skeleton

```lua
local M = {
  name = 'mygitea',
  cli = 'tea',
  kinds = { issue = 'issues', pr = 'pulls' },
  labels = { issue = 'Issues', pr = 'PRs', pr_one = 'PR', pr_full = 'Pull Requests', ci = 'CI/CD' },
}

function M:list_pr_json_cmd(state)
  return { 'tea', 'pr', 'list', '--state', state, '--output', 'json' }
end

function M:pr_json_fields()
  return { number = 'number', title = 'title', branch = 'head', state = 'state', author = 'poster', created_at = 'created_at' }
end

return M
```

## Health

Run `:checkhealth forge` to verify your setup. Checks for `git`, forge CLIs
(`gh`, `glab`, `tea`), required plugins (`fzf-lua`), optional plugins
(`diffs.nvim`, `vim-fugitive`), and any registered custom sources.

## FAQ

**Q: How do I create a PR?** `<c-g>` -> Pull Requests -> `ctrl-a` to compose. Or
from fugitive: `cpr` (compose), `cpd` (draft), `cpf` (instant), `cpw` (web).

**Q: Does review mode require diffs.nvim?** Yes. Without
[diffs.nvim](https://github.com/barrettruth/diffs.nvim), the diff action and
review toggling are unavailable.

**Q: How does forge detection work?** forge.nvim reads the `origin` remote URL
and matches against known hosts and any custom `sources.<name>.hosts`. The first
match wins, and the CLI must be in `$PATH`.

**Q: Can I use this with self-hosted GitLab/Gitea?** Yes. Add your host to
`vim.g.forge.sources`. See the [examples](#examples).

**Q: What does `ctrl-o` do in pickers?** Cycles the state filter: open -> closed
-> all -> open.

**Q: How do I merge/approve/close a PR?** `ctrl-e` on a PR in the picker opens
the manage picker. Available actions depend on your repository permissions.

**Q: Does this work without a forge remote?** Partially. Commits, branches, and
worktrees work in any git repo. PRs, issues, CI, and browse require a detected
forge.
