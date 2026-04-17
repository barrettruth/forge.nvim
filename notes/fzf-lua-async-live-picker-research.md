# fzf-lua async streaming and live picker update research

Date: 2026-04-07

## Scope

- Explored Forge's current picker architecture.
- Explored the local `~/dev/fzf-lua` checkout in detail.
- Focused on the idea of more efficient async streaming and live picker updates
  for an uninterrupted experience.
- Did not explore the other Forge picker backends yet. `telescope` and `snacks`
  still need equivalent research before making backend-wide claims.

## Summary

The short version is:

- Forge is currently modeled as a static snapshot picker system.
- fzf-lua is capable of operating more like a stateful source-driven picker
  system.
- The main gap is in Forge's abstraction and row identity model, not in
  fzf-lua's raw capabilities.

This means the idea looks promising for the fzf-lua backend, but it should be
treated as an fzf-first design effort until the other backends are explored.

## What was explored

### Forge

- `lua/forge/picker/init.lua`
- `lua/forge/picker/fzf.lua`
- `lua/forge/picker/telescope.lua`
- `lua/forge/picker/snacks.lua`
- `lua/forge/pickers.lua`
- `lua/forge/log.lua`
- `lua/forge/review.lua`
- `doc/forge.nvim.txt`
- recent picker-related commits, especially:
  - `7e33ca3 feat: keep picker context for auxiliary actions`
  - `70956e8 fix: use fzf reload for non-closing actions`
  - `615950f fix: preserve CI buffers during refresh`

### fzf-lua

- `lua/fzf-lua/core.lua`
- `lua/fzf-lua/shell.lua`
- `lua/fzf-lua/fzf.lua`
- `lua/fzf-lua/actions.lua`
- `lua/fzf-lua/config.lua`
- `lua/fzf-lua/providers/meta.lua`
- `lua/fzf-lua/providers/diagnostic.lua`
- `lua/fzf-lua/providers/lsp.lua`
- `tests/api_spec.lua`
- `README.md`
- `OPTIONS.md`
- `doc/fzf-lua.txt`

### Local environment checked

- `fzf 0.71.0`
- `nvim 0.12.0`

The local versions matter because modern fzf features like `reload`,
`transform`, and `change-with-nth` are available here.

## Current Forge constraints

### 1. The picker contract is snapshot-based

`lua/forge/picker/init.lua` currently models a picker as:

- `prompt`
- `entries`
- `actions`
- `picker_name`

That means every backend receives a fully materialized list up front. There is
no source/session/update abstraction yet.

### 2. The fzf backend is static

`lua/forge/picker/fzf.lua` currently:

- renders all entries up front
- prefixes each row with an integer index
- resolves selection by parsing the row prefix back into `opts.entries[idx]`

That works well for static pickers, but it becomes fragile when rows can change
while the picker is open.

### 3. Forge already does async work, but not async picker population

`lua/forge/pickers.lua` uses `vim.system(..., callback)` heavily for PRs,
issues, CI, checks, releases, branches, commits, worktrees, and review files.

The data fetches are async, but the picker UX is still mostly:

1. fetch
2. decode/parse
3. open picker

So the user usually waits before seeing the picker.

### 4. Forge already has useful cache-first behavior

Several picker flows already cache result sets:

- PRs
- issues
- releases
- branches
- commits
- worktrees

This is a strong base for an eventual stale-while-revalidate flow.

### 5. Forge already values uninterrupted UX in adjacent surfaces

`lua/forge/log.lua` is a strong precedent. The log viewer:

- reuses the same buffer during refresh
- keeps existing content visible
- preserves cursor position and bottom-follow behavior

That is the best existing Forge reference for how a picker refresh should feel.

## Confirmed fzf-lua capabilities

### 1. `fzf_exec` supports function producers

This is the biggest capability win.

`fzf-lua.core.fzf_exec` can accept:

- a table
- a shell command string
- a function producer

That function producer can emit rows asynchronously through `fzf_cb(...)`.

This is not just theoretical. fzf-lua itself uses async producer patterns in
upstream providers such as diagnostics and LSP.

This makes an async initial-load picker feasible for Forge.

### 2. `fzf_live` is real and tested

`FzfLua.fzf_live` exists, is exported, and has coverage in `tests/api_spec.lua`.

It supports query-driven live reloading where prompt input drives the source.
This is likely more appropriate for explicit search experiences than for
replacing all normal Forge list pickers.

### 3. `reload=true` is a first-class path

fzf-lua converts actions with `reload=true` into proper fzf reload binds.

Forge is already using this idea for non-closing actions in the fzf backend.

This is the correct primitive for in-place refresh after an action or explicit
refresh key.

### 4. `transform` goes beyond plain reload

fzf-lua also uses `transform` for more advanced dynamic behavior. The upstream
`providers/meta.lua` flow shows that an open picker can:

- swap sources
- update search behavior
- update preview behavior
- change `--with-nth` on newer fzf versions

That suggests fzf-lua can be pushed further than Forge currently pushes it.

### 5. `multiprocess` exists for performance

fzf-lua has a shell wrapper and multiprocess path for large or streaming
sources. This may matter if Forge eventually wants a shell-command-backed source
or very large row sets.

## Main design constraints

### 1. Stable row identity is required

Forge currently uses array index as row identity in the fzf backend.

For mutable/live/reload-heavy pickers, Forge will likely need:

- stable row ids
- a session-owned row map
- action lookup by id rather than by array position

### 2. Async first-load and live replacement are different problems

There are at least three separate UX goals:

1. open immediately and stream initial rows
2. refresh in place after an explicit action
3. update an already-open picker from background async work without a user
   action

The first two look feasible with fzf-lua's supported paths.

The third one is less clear. fzf-lua obviously supports action-driven reload and
query-driven reload, but there was not an obvious public API for arbitrary
external background replacement of the current source.

### 3. Forge prompts currently embed counts

Many Forge picker prompts include current counts and filter labels. If a picker
becomes mutable while open, those prompts can go stale unless the refresh path
also updates prompt/header text cleanly.

### 4. The backend abstraction is uneven

fzf-lua appears capable of much more than the current static Forge contract.

`telescope` and `snacks` were not explored in this research pass, so
backend-wide design work should assume capability differences until proven
otherwise.

### 5. There is a docs/code mismatch around raw fzf-lua command sources

Forge help still mentions fallback paths where `checks_cmd` or `list_runs_cmd`
can be used as raw fzf-lua command sources.

The current picker code appears to rely only on the structured JSON paths and no
longer uses those raw command fallbacks.

That should be clarified if this work proceeds.

## Recommended path

### Phase 1: fzf-only async initial load

High value, low risk.

Use fzf-lua function producers so the picker can:

- open immediately
- show cached rows or a lightweight loading state
- emit real rows once async fetches complete

Best starting targets:

- PR list
- issue list
- CI list
- checks list

### Phase 2: session-based in-place refresh

Introduce a richer Forge picker/session abstraction with:

- stable row ids
- session state
- render-from-state helpers
- refresh callbacks

Then let the fzf backend use reload-backed refresh while other backends can
temporarily keep reopen behavior if needed.

### Phase 3: selective `fzf_live`

Use `fzf_live` only where the prompt should actually drive source generation:

- PR search
- issue search
- maybe CI search

This should probably not be the first step for standard Forge list pickers.

### Phase 4: background auto-refresh while open

Only tackle this after the session model exists.

This is the least clearly supported path and likely the most backend-specific.

## Best practical takeaways

### Best immediate win

Cache-first plus async fzf producer.

This should improve perceived responsiveness without requiring a full picker
abstraction rewrite.

### Best medium-term win

Stable session ids plus reload-backed refresh.

This would make refreshes and auxiliary actions feel much more continuous.

### Best long-term direction

A capability-aware picker abstraction:

- static snapshot support for all backends
- source/session support where the backend can support it
- reopen fallback where it cannot

## Explicit caveat

This research was fzf-lua focused.

It should not be treated as evidence that Forge can or should apply the same
live-update design to `telescope` or `snacks` yet. Those backends still need
their own exploration, especially around:

- in-place refresh support
- mutable source support
- query-driven live behavior
- selection stability under row replacement
