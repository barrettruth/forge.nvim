# Fix commit picker SHA parsing and upstream fallback

## Problem

The commit picker has two separate integrity problems.

1. SHAs after the first row are getting parsed with a leading newline. That
   breaks:
   - show
   - browse
   - yank

2. When a branch upstream ref is stale or missing, the commit picker can surface
   a raw git failure instead of falling back cleanly to the local branch.

## Expected

- trim parsed commit fields
- treat commit rows as canonical clean data
- fall back to the local branch when the tracked upstream ref is not usable
