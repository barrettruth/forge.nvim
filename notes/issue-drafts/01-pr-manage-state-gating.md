# Tighten PR manage action gating

## Problem

The PR manage picker is still too loose about which actions it shows.

Live examples from the GitHub pass:

- merged PRs still offered `Reopen`
- non-open PRs still offered `Mark as draft`
- `Mark as ready` should only exist for draft PRs
- after approving PR #158, the picker still showed `Approve`

## Expected

Only show actions that are valid for the specific PR state, merge status, draft
state, permissions, and forge capabilities.

## Notes

The underlying command paths work when called in valid states. The problem is
the picker surface, not the semantic ops layer.
