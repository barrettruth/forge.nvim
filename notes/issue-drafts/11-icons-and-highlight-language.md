# Revisit icons and highlight language across pickers

## Problem

The current icon and highlight language is inconsistent.

Observed:

- `closed = x` and `fail = x` overload the same glyph
- the merged marker highlight did not play nicely with selection state
- author and relative time often share the same visual treatment when they
  should read differently
- branch/worktree markers are useful, but their color story is still unsettled

## Expected

One pass over icons and highlight roles so the same symbols and colors mean the
same things everywhere.
