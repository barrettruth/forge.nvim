# Clean up CI and checks picker behavior

## Problem

The CI/check surface works, but it still has a pile of regressions and rough
edges.

Observed:

- `:FzfLua resume` duplicated check rows on each resume
- skipped checks fail the log action with an easy-to-miss message
- long check names get truncated too aggressively
- duration extmarks are hard to distinguish from real log text
- the repo CI summary view feels questionable overall
- repo CI likely needs a `load more` path
- repo CI may want grouping by workflow/run type
- current highlight treatment in summary/log views is not great

## Expected

The CI surface should feel stable, readable, and obvious without relying on
message-area diagnostics.
