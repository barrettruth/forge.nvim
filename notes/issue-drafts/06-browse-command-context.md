# Clean up browse command context and address syntax

## Problem

Browse mostly works from normal file buffers, but it breaks down in a few
important cases.

Observed:

- help says visual `:Forge browse` should include a range, but the command
  itself does not accept a range
- `:Forge browse target=README.md:1-5` fails even though the current docs do not
  make the full grammar obvious
- `:Forge browse rev=@main` behaved badly from a special `canola://` buffer
- contextual browse from non-file views can derive the wrong path or line target

## Expected

- docs and command behavior should match
- address syntax should be easier to understand
- special buffers should not leak bogus file context into browse targets
