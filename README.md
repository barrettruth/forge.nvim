# forge.nvim

GitHub issues and pull requests in Neovim.

## Requirements

- Neovim 0.12+
- [`gh`](https://cli.github.com), authenticated
- (Optionally) [ci.nvim](https://github.com/barrettruth/ci.nvim) to view PR checks
- (Optionally) [diffs.nvim](https://github.com/barrettruth/diffs.nvim) to view PR diffs

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

:PR                                               " the PR for this branch
:PR 41138                                         " a pull request by number
:PR neovim/neovim                                 " open pull requests there
```

In a list, `<CR>` opens the item under the cursor, `-` navigates to the parent.

See `:help forge.nvim` for more information.

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)
