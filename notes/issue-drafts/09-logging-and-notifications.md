# Revisit logging and normal user notifications

## Problem

Forge is still too chatty in normal use, and some messages land in places that
are easy to miss.

Observed:

- user-facing info logging is noisy in ordinary flows
- some important outcomes only show up in `:messages`
- worktree actions briefly dropping into terminal mode are confusing

## Expected

Normal successful flows should stay quiet unless the user explicitly wants more
detail. Debug logging should be available without turning every shell-out into
user-facing chatter.
