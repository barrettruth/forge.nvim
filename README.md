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

## Design

**Two commands, no subcommands.** `:Issue` and `:PR`. Never `:Forge pr create`.
If you are reaching for a verb, it should have been a mapping.

**No `setup()`, no config.** Loading the plugin is enough. A default mapping
is skipped where the key is already taken, or where the `<Plug>` target is
already mapped. Your bindings win without you having to say so.

**Every view has a name.** A `forge://` URI addresses each one, and the name
alone is enough to rebuild it. That is what makes `:edit` and `gf` work without
forge binding anything.

**One contract per forge.** GitHub and GitLab implement the same backend
interface. Nothing above it asks which forge answered. A capability is the
presence of a method, never a flag. A forge that cannot do something simply
does not offer it. What killed earlier attempts was not the second backend but
the product of backends and features. Anything that multiplies gets refused.

**Delegation over absorption.** [diffs.nvim] renders diffs, [ci.nvim] renders
CI, fugitive renders logs. forge owns conversation and metadata. The rest is
scope creep.

## Known Limitations

Subject to change, and on the table for future development.

- **GitHub and GitLab only.** No Forgejo, Codeberg, nor Gitea.
- **No review surface.** There is no way to approve, request changes, or
  comment, and comments written against a line of the diff are not shown.
  Read those on the forge, or in [diffs.nvim].
- **Creating happens in the browser.** `ga` opens the forge's own new-issue or
  new-pull-request page. Templates, required fields and attachments stay the
  forge's to enforce. There is no compose buffer.
- **No stacks.** A pull request that belongs to a stack is not recognised as
  one.
- **Deleting the branch on merge is unsupported.** GitHub settles it for a
  whole repository and GitLab per merge request, and GitLab will not say over
  its REST API whether you may.
- **GitLab does less.** Closing as not planned, rebasing, waiting merges and
  merge trains are all unsupported, the commit message a merge would carry
  opens empty, and a search is matched against the title and description with
  no qualifier language.

## Acknowledgements

- [guh.nvim](https://github.com/justinmk/guh.nvim)

[ci.nvim]: https://forge.barrettruth.com/barrettruth/ci.nvim
[diffs.nvim]: https://forge.barrettruth.com/barrettruth/diffs.nvim
