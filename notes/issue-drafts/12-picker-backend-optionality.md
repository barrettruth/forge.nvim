# Make picker backend requirements explicit, or make them real options

## Problem

Right now `fzf-lua` is effectively required.

The code only knows one picker backend, healthcheck errors without it, and the
docs/readme treat it as a requirement.

## Expected

Pick one direction and make it consistent:

- either `fzf-lua` stays required and we say that plainly, or
- picker backends become genuinely optional/pluggable and the docs, healthcheck,
  and architecture all reflect that.
