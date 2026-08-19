# forge.nvim

GitHub and GitLab issues, pull requests and merge requests in Neovim.

## Requirements

- Neovim 0.12+
- [`gh`](https://cli.github.com), authenticated, for GitHub
- [`glab`](https://gitlab.com/gitlab-org/cli), authenticated, for GitLab
- (Optionally) [ci.nvim](https://forge.barrettruth.com/barrettruth/ci.nvim) to view PR checks
- (Optionally) [diffs.nvim](https://forge.barrettruth.com/barrettruth/diffs.nvim) to view PR diffs

## Installation

```lua
vim.pack.add({ 'https://github.com/barrettruth/forge.nvim' })
```

## Usage

```vim
:Issue                                            " open issues in this repo
:Issue 41310                                      " an issue by number
:Issue neovim/neovim#41310                        " in another repo
:Issue https://github.com/neovim/neovim/issues/41310
:Issue .                                          " the reference under the cursor

:PR                                               " open pull requests in this repo
:PR @                                             " the PR for the change you are on
:PR 41138                                         " a pull request by number
:PR neovim/neovim                                 " open pull requests there

:PR !123                                          " a merge request by number
:PR group/subgroup/project!123                    " in another GitLab project
:Issue forge://gitlab.com/group/subgroup/project/issues/12
```

The forge is chosen by host. gitlab.com is GitLab, as is any host `glab` holds
a login for. Everything else is GitHub. A GitLab view says "merge request" and
writes `!` in front of the number.

In a list, `<CR>` opens the item under the cursor. `-` takes an item back up to
its list. In either, `gf` follows the reference under the cursor.

See `:help forge.nvim` for more information.

## Known Limitations

Subject to change, and on the table for future development.

- **GitHub and GitLab only.** No Forgejo, Codeberg, nor Gitea.
- **No review surface.** There is no way to approve, request changes, or
  comment, and comments written against a line of the diff are not shown.
- **Issue/PR creation is browser-native.** Open in the browser with `ga`.
- **Underlying Forge Limitations.** GitHub, GitLab, and Forgejo APIs have
  mixed support for common behaviors such as PR merging, CI, search, etc.

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)
