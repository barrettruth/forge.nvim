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

:PR                                               " the PR for this branch
:PR 41138                                         " a pull request by number
:PR neovim/neovim                                 " open pull requests there
```

In a list, `<CR>` opens the item under the cursor and `g?` says what every
other key does.

Which repository you are in is gh's answer, not a remote forge picked for
itself, so a fork resolves to the repository its issues and pull requests
actually live on and forge agrees with the gh commands you run beside it.

See `:help forge.nvim`.
