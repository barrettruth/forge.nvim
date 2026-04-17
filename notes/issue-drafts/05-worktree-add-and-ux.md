# Fix worktree add crash and revisit the add UX

## Problem

Worktree add is currently broken.

The add flow can hit:
`E5560: nvim_echo must not be called in a fast event context`

That comes from logging in the callback path.

## Expected

First fix the crash so worktree add works again.

After that, revisit the UX. The current `vim.ui.input` prompt works, but the
fzf-lua-style model where you type a branch name in the picker and hit `<c-a>`
feels better for worktree creation.
