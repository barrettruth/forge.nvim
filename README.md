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

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)
