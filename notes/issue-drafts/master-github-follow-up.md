# GitHub pass follow-up

Follow-up to the earlier `bugfixes` issue. If we want to post this verbatim,
swap in the real issue number/title reference.

The GitHub regression pass turned up a mix of hard bugs, stale docs, and
workflow polish problems. The main pattern is that the core command surface
mostly works, but several picker and compose flows still need tighter state
handling and cleaner UX.

The main buckets are:

- PR state/action gating
- review materialization
- create-web behavior
- commit/worktree picker bugs
- browse/context/addressing problems
- CI/check picker regressions
- compose-buffer polish
- backend/config assumptions

See the tracker for the full list.
