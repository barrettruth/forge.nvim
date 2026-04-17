# Fix web create flows for PRs and issues

## Problem

The web create paths are not trustworthy right now.

Observed:

- `:Forge issue create web` repeatedly did nothing
- `:Forge pr create web` from `main` logged `checking for existing PR...` and
  `pushing...`, then did not open anything
- non-web PR create paths correctly stop on `no changes`, but the web path skips
  that safeguard

## Expected

- shared preflight rules across create modes
- clear Forge-level errors when the web command fails
- browser opens only after the command actually succeeds

## Notes

PR create should also treat “current branch is the effective base branch” as an
invalid case and stop early.
