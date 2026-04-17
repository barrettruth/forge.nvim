# Backend capability matrix

Canonical reference for "which forge / CLI supports operation X". Optimized
for the operations forge.nvim cares about today and for the operations users
keep asking about ("can I cancel CI on Codeberg?", "does glab support
re-running failed jobs?").

Whether forge.nvim wires an operation up is tracked separately — this matrix
is about what the underlying CLIs and forges actually expose.

Versions verified against:

- `gh` 2.89.0 (GitHub)
- `glab` 1.91.0 (GitLab)
- `tea` 0.13.0 (Gitea / Codeberg / Forgejo)

Legend:

- `✓`         supported as a first-class CLI subcommand or flag
- `flag`     supported via a flag on a more general subcommand
- `api`      not a CLI subcommand, but reachable via `gh api` / `glab api`
             / `tea api` against a documented REST endpoint
- `—`        unsupported by the CLI; no clean fallback
- `n/a`      the underlying forge model does not have this concept

Every cell shows the actual command/flag (or `—`) so this file doubles as a
crib sheet when wiring new verbs into `forge.ops`.

---

## Pull / merge requests

### Lifecycle

| Operation                  | gh                              | glab                              | tea                                  |
| -------------------------- | ------------------------------- | --------------------------------- | ------------------------------------ |
| List                       | `gh pr list`                    | `glab mr list`                    | `tea pulls list`                     |
| View                       | `gh pr view`                    | `glab mr view`                    | `tea pulls <idx>`                    |
| Create                     | `gh pr create`                  | `glab mr create`                  | `tea pulls create`                   |
| Create as draft            | `--draft`                       | `--draft`                         | — (no `--draft` on `tea pulls create`) |
| Edit (title/body)          | `gh pr edit`                    | `glab mr update`                  | `tea pulls edit`                     |
| Toggle draft / ready       | `gh pr ready [--undo]`          | `glab mr update --draft / --ready`| — (Gitea has no draft PR concept reachable via tea) |
| Checkout                   | `gh pr checkout`                | `glab mr checkout`                | `tea pulls checkout`                 |
| Diff                       | `gh pr diff`                    | `glab mr diff`                    | — (use `git diff` after checkout)    |
| Merge                      | `gh pr merge [--merge/--squash/--rebase]` | `glab mr merge [--squash/--rebase]` | `tea pulls merge [--style merge\|rebase\|squash]` |
| Close / reopen             | `gh pr close / reopen`          | `glab mr close / reopen`          | `tea pulls close / reopen`           |
| Update branch with base    | `gh pr update-branch [--rebase]`| `glab mr rebase [--skip-ci]`      | — (Gitea offers an "update PR branch" REST endpoint; not in tea) |
| Revert                     | `gh pr revert`                  | —                                 | —                                    |
| Lock / unlock conversation | `gh pr lock / unlock`           | —                                 | —                                    |

### Metadata (add/remove)

| Operation             | gh                                  | glab                                                     | tea                                       |
| --------------------- | ----------------------------------- | -------------------------------------------------------- | ----------------------------------------- |
| Labels (add/remove)   | `gh pr edit --add-label / --remove-label` | `glab mr update -l / -u`                            | `tea pulls edit --add-labels / --remove-labels` |
| Assignees (add)       | `gh pr edit --add-assignee` (`@me`/`@copilot` ok) | `glab mr update --assignee +user / -user`     | `tea pulls edit --add-assignees`          |
| Assignees (remove)    | `gh pr edit --remove-assignee`      | `glab mr update --assignee !user` / `--unassign`         | — (no `--remove-assignees` on `tea pulls edit`) |
| Reviewers (add)       | `gh pr edit --add-reviewer`         | `glab mr update --reviewer +user`                        | `tea pulls edit --add-reviewers`          |
| Reviewers (remove)    | `gh pr edit --remove-reviewer`      | `glab mr update --reviewer !user`                        | `tea pulls edit --remove-reviewers`       |
| Milestone (set)       | `gh pr edit --milestone`            | `glab mr update -m`                                      | `tea pulls edit --milestone`              |
| Milestone (clear)     | `gh pr edit --remove-milestone`     | `glab mr update -m ""` / `-m 0`                          | `tea pulls edit --milestone ""`           |

### Review and comments

| Operation                          | gh                                | glab                                          | tea                                         |
| ---------------------------------- | --------------------------------- | --------------------------------------------- | ------------------------------------------- |
| Approve                            | `gh pr review --approve`          | `glab mr approve`                             | `tea pulls approve`                         |
| Request changes                    | `gh pr review --request-changes`  | — (no first-class command)                    | `tea pulls reject`                          |
| Comment on whole PR                | `gh pr comment` / `gh pr review --comment` | `glab mr note`                       | `tea comment <idx>`                         |
| File/line review comments          | api (REST `/pulls/{n}/comments`)  | api (REST `/projects/{p}/merge_requests/{iid}/discussions`) | api (REST `/repos/.../pulls/{idx}/reviews`) |
| Revoke own approval                | re-review / dismiss via API       | `glab mr revoke`                              | — (API only)                                |

---

## Issues

### Lifecycle

| Operation         | gh                  | glab                          | tea                            |
| ----------------- | ------------------- | ----------------------------- | ------------------------------ |
| List              | `gh issue list`     | `glab issue list`             | `tea issues list`              |
| View              | `gh issue view`     | `glab issue view`             | `tea issues <idx>`             |
| Create            | `gh issue create`   | `glab issue create`           | `tea issues create`            |
| Edit (title/body) | `gh issue edit`     | `glab issue update`           | `tea issues edit`              |
| Close / reopen    | `gh issue close / reopen` | `glab issue close / reopen` | `tea issues close / reopen`  |
| Comment           | `gh issue comment`  | `glab issue note`             | `tea comment <idx>`            |
| Delete            | `gh issue delete`   | `glab issue delete`           | — (API only)                   |
| Transfer / lock / pin | `gh issue transfer/lock/pin` | —                  | —                              |

### Metadata (add/remove)

| Operation          | gh                                          | glab                                                  | tea                                          |
| ------------------ | ------------------------------------------- | ----------------------------------------------------- | -------------------------------------------- |
| Labels             | `gh issue edit --add-label / --remove-label`| `glab issue update -l / -u`                           | `tea issues edit --add-labels / --remove-labels` |
| Assignees (add)    | `gh issue edit --add-assignee`              | `glab issue update --assignee +user`                  | `tea issues edit --add-assignees`            |
| Assignees (remove) | `gh issue edit --remove-assignee`           | `glab issue update --assignee !user` / `--unassign`   | — (no `--remove-assignees` on `tea issues edit`) |
| Milestone          | `gh issue edit --milestone / --remove-milestone` | `glab issue update -m` (`""` to clear)           | `tea issues edit --milestone` (`""` to clear)|

---

## CI / pipelines / runs

### Reading

| Operation                  | gh                                | glab                                       | tea                                                     |
| -------------------------- | --------------------------------- | ------------------------------------------ | ------------------------------------------------------- |
| List runs (repo)           | `gh run list`                     | `glab ci list`                             | `tea api .../actions/runs` (no `tea actions runs list` for repo with branch filter — `tea actions runs list` exists but uses tea's own filters) |
| List per-PR checks         | `gh pr checks`                    | api (pipeline-of-MR via `glab api`)        | api (commit statuses via `tea api .../commits/{sha}/status`) |
| View run summary           | `gh run view`                     | `glab ci view`                             | `tea actions runs view`                                 |
| View run log               | `gh run view --log`               | `glab ci trace <job>`                      | `tea actions runs logs <run>`                           |
| View only failed log lines | `gh run view --log-failed`        | — (filter manually)                        | — (no `--failed` filter; could `grep` after the fact)  |
| Live tail / follow         | `gh run watch`                    | `glab ci trace` (already live for running) | `tea actions runs logs --follow` (per job, in-progress only) |
| Download artifacts         | `gh run download [--name/--pattern]` | `glab ci artifact <ref> <jobName>`      | — (Gitea Actions exposes artifacts via API; no tea subcommand) |

### Writing (mutations)

| Operation                          | gh                                | glab                                  | tea                                              |
| ---------------------------------- | --------------------------------- | ------------------------------------- | ------------------------------------------------ |
| Cancel run / pipeline              | `gh run cancel [--force]`         | `glab ci cancel pipeline <id>`        | `tea actions runs delete` (the `delete` subcommand is documented as "Delete or cancel a workflow run") |
| Cancel single job                  | — (cancel scoped to whole run)    | `glab ci cancel job <id>`             | — (API only)                                     |
| Rerun whole run                    | `gh run rerun`                    | — (glab only retries jobs)            | api (`POST /repos/{o}/{r}/actions/runs/{id}/rerun`) |
| Rerun failed jobs only             | `gh run rerun --failed`           | partial — `glab ci retry <job>` per job | — (API only)                                   |
| Rerun a single job                 | `gh run rerun --job <databaseId>` | `glab ci retry <job-id>`              | — (API only)                                     |
| Delete run                         | `gh run delete`                   | `glab ci delete <id>`                 | `tea actions runs delete` (same subcommand cancels in-flight runs and removes completed ones) |
| Manual trigger (workflow_dispatch) | `gh workflow run`                 | `glab ci run` / `glab ci trigger <job>` (manual jobs only) | — (`tea actions workflows` only has `list`) |
| Lint config                        | —                                 | `glab ci lint`                        | —                                                |

> Note on Codeberg per-PR checks: forge.nvim reads commit statuses (third-
> party CI like Woodpecker) rather than Gitea Actions jobs because not every
> Codeberg repo runs Actions. As a result, "log viewing" for a per-PR check
> on Codeberg only works if the status happens to come from a Gitea Actions
> run on the same SHA — otherwise the log lives on the external CI provider.

---

## Releases

| Operation                        | gh                                 | glab                              | tea                                  |
| -------------------------------- | ---------------------------------- | --------------------------------- | ------------------------------------ |
| List                             | `gh release list`                  | `glab release list`               | `tea releases list`                  |
| View                             | `gh release view`                  | `glab release view`               | `tea releases <tag>` (via list)      |
| Create                           | `gh release create`                | `glab release create`             | `tea releases create`                |
| Create as draft                  | `--draft`                          | n/a (GitLab releases don't model draft state) | `--draft`                |
| Create as prerelease             | `--prerelease`                     | n/a (no prerelease concept in GitLab) | `--prerelease`                   |
| Edit                             | `gh release edit`                  | — (no first-class edit; recreate or use `glab api`) | `tea releases edit` |
| Delete                           | `gh release delete`                | `glab release delete`             | `tea releases delete`                |
| Upload assets                    | `gh release upload`                | `glab release upload`             | `tea releases assets create`         |
| Download assets                  | `gh release download`              | `glab release download`           | — (API only)                         |
| Delete asset                     | `gh release delete-asset`          | — (API only)                      | `tea releases assets delete`         |

> GitLab releases are tag + notes + asset links + milestone associations.
> They have no "draft" or "prerelease" toggle in the GitLab API or CLI.

---

## Repository / browse / commits

These are uniformly supported on all three CLIs and forges; they are listed
here for completeness only.

| Operation                | gh                          | glab                       | tea                            |
| ------------------------ | --------------------------- | -------------------------- | ------------------------------ |
| Open repo in browser     | `gh repo view --web`        | `glab repo view --web`     | `tea open`                     |
| Open file/line permalink | `gh browse <path>`          | `glab repo browse <path>`  | URL constructed by forge.nvim  |
| Open branch / commit     | `gh browse --branch / <sha>`| `glab repo browse`         | URL constructed by forge.nvim  |
| Clone                    | `gh repo clone`             | `glab repo clone`          | `tea clone`                    |
| Default branch lookup    | `gh repo view --json defaultBranchRef` | `glab repo view -F json` (`.default_branch`) | `tea api .../repos/{o}/{r}` (`.default_branch`) |

---

## Quick reference: "common ops" summary

A short version of the matrix the user actually thinks about most:

| Operation                    | GitHub | GitLab | Codeberg |
| ---------------------------- | ------ | ------ | -------- |
| PR draft / ready             | ✓      | ✓      | —        |
| PR add / remove reviewer     | ✓ / ✓  | ✓ / ✓  | ✓ / ✓    |
| PR add / remove assignee     | ✓ / ✓  | ✓ / ✓  | ✓ / —    |
| PR add / remove labels       | ✓ / ✓  | ✓ / ✓  | ✓ / ✓    |
| PR set / clear milestone     | ✓ / ✓  | ✓ / ✓  | ✓ / ✓    |
| PR comment (top-level)       | ✓      | ✓      | ✓        |
| PR comment (file/line)       | api    | api    | api      |
| PR revert                    | ✓      | —      | —        |
| PR sync with base branch     | ✓      | ✓      | api      |
| Issue add / remove assignee  | ✓ / ✓  | ✓ / ✓  | ✓ / —    |
| Issue add / remove labels    | ✓ / ✓  | ✓ / ✓  | ✓ / ✓    |
| Issue comment                | ✓      | ✓      | ✓        |
| Issue delete                 | ✓      | ✓      | api      |
| CI cancel run                | ✓      | ✓      | ✓        |
| CI cancel single job         | —      | ✓      | api      |
| CI rerun whole run           | ✓      | —      | api      |
| CI rerun failed jobs         | ✓      | per-job | api     |
| CI rerun single job          | ✓      | ✓      | api      |
| CI download artifacts        | ✓      | ✓      | api      |
| CI manual trigger            | ✓      | ✓      | —        |
| Release create (draft/prerelease) | ✓ / ✓ | n/a / n/a | ✓ / ✓ |
| Release edit                 | ✓      | api    | ✓        |
| Release upload assets        | ✓      | ✓      | ✓        |

---

## Notes for future wiring

The bulk of items marked `api` above are reachable through the existing
`tea api` / `glab api` / `gh api` shell-outs. Wiring them as forge.ops verbs
is mostly a matter of:

1. Adding a capability flag (e.g. `capabilities.cancel_run`) per source.
2. Adding the corresponding `_cmd` builder per source module.
3. Adding the verb to `forge.ops` and routing from `cmd.lua` / pickers.

Since glab's "rerun" model is per-job rather than per-run, any cross-forge
"rerun" verb in forge.nvim will need to either:

- pick the most natural unit per forge ("rerun what makes sense"), or
- expose two verbs (`ci rerun-run` and `ci rerun-job`) and gate them by
  capability flag.

Same shape for cancel: GitHub cancels whole runs, GitLab cancels either, and
Gitea collapses cancel + delete into the same subcommand.
