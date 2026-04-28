# forge.nvim agent notes

## File handling

- **NEVER commit, stage, or include `AGENTS.md` in any git operation.** This
  file is local-only by standing instruction. Do not `git add AGENTS.md`, do
  not reference it in commit messages, do not suggest committing it. If
  `AGENTS.md` appears in `git status` as untracked, leave it untracked.

## Repo command surface

- This repo uses `justfile`, `flake.nix`, and `.envrc`.
- Prefer `just` recipes over ad-hoc commands.
- `just --summary` currently exposes:
  - `ci`
  - `default`
  - `format`
  - `lint`
  - `test`

## Environment and worktrees

- Use task worktrees under `/tmp/forge.nvim/<task>/`.
- For repo commands, use the repo-root direnv environment and then `cd` into the
  worktree:
  - `direnv exec /home/barrett/dev/forge.nvim sh -lc 'cd /tmp/forge.nvim/<task> && <command>'`

## Verification

- Run targeted specs first when possible.
- Use `just ci` as the final verification gate.
- The repo root `.envrc` currently loads `~/.config/nix#neovim`, which does not
  include `biome`.
- For the final gate, run the repo flake CI shell explicitly:
  - `nix develop /home/barrett/dev/forge.nvim#ci --command sh -lc 'cd /tmp/forge.nvim/<task> && just ci'`

## Git / GPG

- GPG signing is configured again. Attempt normal signed git commits first.
- Only retry with `--no-gpg-sign` if a git commit/signing step actually fails.

## Backwards compatibility

- This project does not maintain backwards compatibility for refactors,
  renames, removals, or behavior tightening.
- Hard-remove old/affected code; do not leave deprecated aliases, "for
  compatibility" wrappers, transitional shims, or `legacy_*` symbols.
- This applies to public Lua API names, parameter names, config keys, command
  surfaces, error message text, and internal helpers alike. If a name or
  shape is changing, change every call site in the same change and delete
  the old name outright.
- Migration notes in `doc/forge.nvim.txt` and similar docs are the only
  acceptable form of "backward compat" — and only when the user-visible
  surface changed.

## Target/current-ref stack guidance

- Shared repo/scope/head/push-context logic belongs in `lua/forge/target.lua`.
- Avoid re-implementing target resolution separately in `resolve`, `cmd`, and
  `init`.
- Explicit inputs beat ambient git state.
- Cross-backend stack changes should explicitly audit and test:
  - GitHub
  - GitLab
  - Codeberg
- Add LuaCATS for new structured target/resolver shapes in `lua/forge/types.lua`.
- Keep user-facing errors aligned with existing forge phrasing such as:
  - `no forge detected`
  - `detached HEAD`
  - `failed to fetch ...`
  - `failed to parse ... details`

## Local skills

- For target/current-ref stack work, invoke the local `forge-stack` skill.
