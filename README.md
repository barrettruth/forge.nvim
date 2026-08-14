# forge.nvim

GitHub issues and pull requests in Neovim.

Two commands, no configuration, no `setup()`. Forge delegates to the `gh` CLI
and renders what comes back; everything you do with a view is a mapping inside
it rather than another command to type.

## Requirements

- Neovim 0.11+
- [`gh`](https://cli.github.com), authenticated

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
```

In an issue list, `<CR>` opens the issue under the cursor.

See `:help forge.nvim`.
