# Test gaps after the GitHub pass

As of today, we still have not exercised these paths:

## Still untested

- Release flows against a repo with real releases: browse, yank, delete.
- A successful PR merge path.
- CI watch on a genuinely running job/run.
- `:Forge pr create web` from a valid feature branch with a real head/base diff.
- Cross-repo and alias-based target addressing in normal use.
- A full issue-create web flow, since the GitHub web path is still not opening.

## Blocked until fixes

- Commit picker actions as a whole, because commit SHAs after the first row are
  getting parsed with a leading newline.
- Worktree add, because it currently crashes in the callback path.
- A trustworthy PR review pass, because failed PR checkout falls back to the
  current branch.
- A trustworthy PR manage-picker pass for edge states, because action gating is
  still too loose.

## Not implemented, so not really a test gap

- Issue edit parity (`:Forge issue edit`).
