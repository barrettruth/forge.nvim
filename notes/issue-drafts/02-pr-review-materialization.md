# Make PR review fail loudly when materialization fails

## Problem

PR review currently falls back to the current branch when
checkout/materialization fails.

That makes the review flow hard to trust, because the UI still opens a review
session even when we are not actually reviewing the PR branch.

## Expected

If Forge cannot materialize the PR branch, the review flow should either:

- fail clearly, or
- use an explicit alternate materialization path,

but it should not silently pretend the current branch is good enough.
