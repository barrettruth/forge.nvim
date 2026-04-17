# Polish compose buffers for PR and issue workflows

## Problem

The compose/edit buffers work, but they still feel rough.

Observed during the pass:

- compose buffers do not have the expected syntax/highlight treatment
- metadata formatting is noisy and could be more compact
- it is not obvious how to abandon a partially written compose buffer cleanly
- issue creation currently aborts on an empty body even though GitHub does not
  require one
- direct `:Forge pr edit <num>` can show the current local branch in metadata
  instead of the PR head branch
- buffer names like `forge://pr/<nr>/edit` may or may not be worth exposing
  as-is
- if picker dependence keeps shrinking, plain `:Forge issue create` may want to
  be the default direct path rather than forcing template selection

## Expected

Tighter compose defaults, clearer metadata, and cleaner submit/abort behavior.
