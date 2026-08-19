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

The forge is chosen by host: gitlab.com, and any host `glab` holds a login for,
is GitLab; everything else is GitHub. A GitLab view says "merge request", writes
`!` in front of the number, and is named for the host it came from.

In a list, `<CR>` opens the item under the cursor; `-` takes an item back up to
its list. In either, `gf` follows the reference under the cursor.

See `:help forge.nvim` for more information.

## Known Limitations

The following limitations are subject to change and may be on the table in
future development.

- **GitHub and GitLab only**: No Forgejo, Codeberg, nor Gitea.
- **GitLab does less**: a close records no reason, so there is one close and
  no "close as not planned"; a merge is a squash or a merge commit, with no
  rebase, no merge that waits, and no merge train; and the commit message a
  merge carries opens empty.
- **No review surface**: There is no way to converse, approve, request
  changes, or comment on PRs, and comments written against a line of the diff
  are not shown either.
- **No stacks**: There is no recognization of stacks, if a PR may
  belong to one.
- **Creating occurs in the browser**. forge.nvim offloads to the browser for
  issue and PR creation.

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)
