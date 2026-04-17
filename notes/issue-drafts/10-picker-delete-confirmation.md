# Revisit delete confirmation UX for picker actions

## Problem

Delete confirmations for branch/worktree actions currently use a numbered choice
prompt.

That works, but it feels clunky compared to an inline `[y/N]` prompt.

## Expected

- a simpler inline confirmation style
- an option to skip delete confirmations entirely for users who want faster
  picker workflows
