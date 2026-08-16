# forge.nvim

GitHub issues and pull requests in Neovim.

## Requirements

- Neovim 0.12+
- [`gh`](https://cli.github.com), authenticated
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
```

In a list, `<CR>` opens the item under the cursor; `-` takes an item back up to
its list. In either, `gf` follows the reference under the cursor.

See `:help forge.nvim` for more information.

## Known limitations

- **GitHub only.** No GitLab, Forgejo, or Gitea. Other forges may come later.
- **No review surface.** You can read a pull request and its comments, but not
  its review threads, and there is no way to approve, request changes, or
  comment on a line.
- **No notifications.** There is no inbox. Every view starts from a repository
  you name or are standing in.
- **No stacks yet.** A stacked pull request shows nothing about the stack it
  belongs to.
- **Long conversations truncate.** What github returns is capped. forge says so
  when a tail was lost, but cannot yet page past the cap to fetch it.
- **Creating happens in the browser.** `ga` opens github's own form, on
  purpose, so templates and required fields are theirs to enforce.

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)
