# Prospective changes

## Manual regression notes

- PR picker merged-state `m` / PR symbol currently renders black on selection;
  investigate overriding that segment so the selected row highlight wins
  cleanly.
- Inspect how closed-but-not-merged PRs render in the picker; compare that state
  styling against merged PRs.
- Split the highlight treatment for author name and relative "since" timestamp;
  they should not share the same highlight group.
- Commit picker metadata also shares the same treatment for author name and
  relative time; reconsider whether those should remain visually identical.
- PR manage picker currently offers `Mark as draft` for non-open PRs; gate draft
  toggles to states where the forge actually supports the transition.
- PR manage picker currently offers `Reopen` for any non-open PR state, which
  incorrectly includes merged PRs; restrict reopen to closed-but-not-merged PRs.
- PR `Ready` / `Mark as ready` should only be available for draft PRs;
  underlying commands may work in valid states, but the picker/manage surface
  should gate them strictly by PR state.
- More generally, the PR manage picker should show only actions that are
  actually applicable to the specific PR's current
  state/capabilities/permissions, not a broader approximate set.
- After approving PR #158, the manage picker still showed `Approve`;
  review/state-sensitive actions should likely disappear or change once already
  satisfied.
- `:Forge pr checkout` on a merged PR with a deleted head branch surfaces the
  raw `gh` failure (`couldn't find remote ref ...`); consider
  preflighting/gating this path or presenting a clearer Forge-level message.
- Add a forward navigation counterpart to `<c-o>` for nested picker flows, e.g.
  `<c-i>` to go in / reverse the back action.
- Revisit PR review UX and potentially remove the `<c-d>` review binding
  entirely for now.
- Review fallback currently proceeds even when PR checkout/materialization
  fails; surface that more clearly or redesign the flow instead of silently
  dropping into current-branch context.
- Evaluate alternative review integrations / shell-outs beyond the current
  diffs.nvim + fugitive approach, including plugins such as codediff.
- `:Forge review end` ends the session state but does not close already-open
  review windows; decide whether that is desirable or whether review teardown
  should also close review UI.
- Remove the PR review action for now.
- Remap PR edit to `<c-e>`.
- Remove `<cr>` as the PR picker "more/manage" action.
- Use `<c-d>` for PR draft toggle instead.
- Revisit user-facing logging volume versus debug logging; worktree and related
  flows may be too chatty in normal operation.
- Investigate the `<c-w>` worktree action UX where the statusline shows
  `-- TERMINAL --`; confirm whether that transient terminal-mode appearance is
  avoidable.
- CI/check picker name column is truncating long check names too aggressively;
  entries like `Markdown Format Check` should not be cut off prematurely.
- Skipped checks currently fail the `<cr>` log action with only a message
  (`no log available - job was not started`) that is easy to miss in-session;
  surface this more clearly in the active UI.
- `:FzfLua resume` appears to duplicate rows in the checks picker on each
  resume; investigate whether streamed/resumed picker state is appending entries
  instead of restoring them, and verify whether the bug affects other Forge
  pickers too.
- In CI/check log views, the end-of-line duration extmarks are hard to visually
  distinguish from actual log text; adjust their presentation so metadata reads
  as metadata.
- Issue close/reopen currently refreshes by reloading the entire issue picker
  and feels slow; investigate whether the post-action refresh path can reuse
  cached data or update the affected row more surgically.
- `:Forge issue browse <number>` can resolve to a PR page when the number
  belongs to a PR; review whether this subcommand should stay distinct, error on
  PR targets, or be simplified in favor of a more general numeric
  `:Forge browse <number>` flow.
- `:Forge issue create web` repeatedly did nothing in live GitHub testing (even
  while other Forge browser-opening paths were working); investigate whether the
  GitHub web-create command path is failing silently.
- Revisit issue-create command language if Forge keeps moving away from
  requiring picker flows: plain `:Forge issue create` may want to behave more
  like the current blank/default compose path, with `template=` and picker
  selection as optional specializations rather than the default.
- Issue creation currently treats an empty body as an abort condition, but
  GitHub issue creation does not inherently require a non-empty body; reconsider
  that validation rule.
- Issue edit parity is currently missing: there is no `:Forge issue edit`
  command or equivalent issue-edit compose flow, while PRs do support direct
  editing.
- `:Forge pr create web` showed `[forge]: checking for existing PR...` then
  `[forge]: pushing...` but did not open a browser page in live GitHub testing;
  investigate whether the GitHub web-create path is failing silently after push
  or needs clearer precondition/error handling.
- `:Forge pr create web` was tested from `main`; Forge currently does not
  preflight obvious invalid PR-create conditions (for example creating from the
  default branch or with no meaningful head/base diff) before shelling out, and
  it ignores the result of the final `gh pr create --web` call, which makes
  failures silent.
- Non-web PR create paths (`:Forge pr create`, `:Forge pr create fill`)
  correctly stop with `no changes` on `main`, while `:Forge pr create web` does
  not share that safeguard; align the preflight behavior across create modes.
- More generally, PR create flows should treat "current branch is also the
  effective target/base branch" as a special invalid/preflighted case, not just
  fall through the normal create logic.
- Contextual `:Forge browse` appears correct from a normal file buffer, but
  behaved oddly when invoked from an issue-related view/buffer; investigate
  buffer-context detection and whether Forge/`gh browse` is deriving the wrong
  path/line target in non-file views. Also review whether the `?plain=1` GitHub
  URL shape is desirable.
- Help/docs say `:Forge browse` in visual mode includes the selected line range,
  but the `:Forge` user command is defined without range support, so invoking it
  from visual mode errors with `no range allowed`; align the command definition
  and docs.
- `:Forge browse target=README.md:1-5` failed with
  `invalid revision address README.md`; current parser expects full location
  addresses like `target=@main:README.md#L1-L5`. The docs/UX should make that
  grammar explicit, and/or the command could support a simpler bare-path
  shorthand.
- `:Forge browse rev=@main` produced a clearly wrong URL
  (`.../blob/main/rge.nvim/?plain=1#L1`) when invoked from a special `canola://`
  buffer; investigate how explicit `rev=` browse resolves paths in non-file
  buffers and whether it should ignore buffer-derived file context there.
- Revisit the overall target-address syntax, especially the `@` revision marker;
  it may be technically consistent but still not the best user-facing command
  language.
- Revisit picker backend requirements: architecturally, `fzf-lua` would be
  better as optional rather than effectively mandatory today. If that changes,
  reflect it consistently in healthcheck, docs, and README.
- Repo-level `:Forge ci` likely needs a `load more` workflow instead of only the
  initial fixed window of runs.
- Repo-level `:Forge ci` may work better as a grouped/sub-picker workflow
  organized by run type or workflow name, similar to GitHub’s native Actions
  view.
- If repo-level `:Forge ci` moves to grouped workflow/run-type views, `<tab>`
  could toggle between those groupings in addition to, or instead of, only
  cycling status buckets.
- Revisit the repo-CI GitHub summary-view approach overall; the current summary
  → job drilldown flow may not be the right UX.
- The green foreground treatment in the repo-CI summary/log presentation is not
  desirable; revisit that highlight choice.
- Revisit branch picker worktree markers: the `+` prefix is visible/useful, but
  we should think about whether it ought to be colorized distinctly.
- Worktree picker current-entry marker (`*`) is highlighted green and reads
  well; keep an eye on marker-color consistency between branch and worktree
  pickers.
- `:Forge commits` failed in a worktree whose branch upstream ref was
  stale/missing (`origin/fix/commit-picker-yank-state` not found); commit picker
  should fall back cleanly to the local branch instead of surfacing the raw git
  error.
- Commit picker parsing is leaking leading newlines into SHAs after the first
  record, so actions like `<cr>` / `git show` can fail with
  `fatal: ambiguous argument '\n<sha>'`, and browse can open malformed URLs
  containing `%0A<sha>`; trim commit fields during parse.
- Revisit the entire icon/mnemonic system holistically instead of piecemeal;
  current defaults like `closed = x` and `fail = x` overload the same glyph
  across different domains and may not be the clearest language.
- Branch/worktree delete confirmation currently uses a numbered `1: Yes / 2: No`
  prompt; prefer a simpler inline `[y/N]` style prompt instead.
- Consider a config option to skip delete confirmations for picker delete
  actions such as branch/worktree deletion.
- Worktree add is currently broken: after `vim.ui.input` it can hit
  `E5560: nvim_echo must not be called in a fast event context`, because the add
  flow logs via `vim.notify` from a fast-event callback path.
- Revisit the worktree-add UX: the current `vim.ui.input` prompt works, but the
  fzf-lua model where you type a branch name directly in the picker and then
  press `<c-a>` to create feels better for worktrees (and possibly branches)
  than a separate blocking prompt.
- PR compose buffers appear to lack expected syntax/highlight treatment in live
  use; investigate filetype/highlight setup for compose/edit buffers.
- Revisit compose-buffer abort UX for issue/PR creation: confirm whether there
  is an intuitive way to abandon creation after typing content without
  accidentally submitting or silently leaving state behind.
- Revisit PR compose metadata formatting; forms like `draft=true`,
  `reviewers=name1,name2`, and similar compact `labels=` / `assignees=` fields
  may be preferable to the current presentation.
- Explicitly verify the custom completion behavior inside PR/issue compose
  buffers.
- In compose buffers, regular completion for `@` and `#` works with the local
  completion setup (`<c-n>` via blink.cmp); discuss whether metadata fields
  themselves should adopt clearer explicit prefixes / syntax to make completion
  behavior more discoverable.
- Direct `:Forge pr edit <num>` works, but the edit buffer metadata can show the
  current local branch (for example `On branch main against main`) rather than
  the PR's head branch, which is misleading when editing a PR from another
  checkout.
- Revisit compose buffer naming: buffers currently use names like
  `forge://pr/<nr>/edit` and `forge://pr/new`; decide whether those suffixes are
  helpful, should be simplified, or should be hidden/stripped from the visible
  buffer name.
