---@meta

---@alias forge.ScopeKind 'github'|'gitlab'|'codeberg'

---@alias forge.WebKind 'pr'|'issue'|'ci'|'release'
---@alias forge.CommandFamily 'pr'|'review'|'issue'|'ci'|'release'|'browse'|'clear'
---@alias forge.SectionName 'prs'|'issues'|'ci'|'browse'|'releases'
---@alias forge.RouteName
---| 'prs.all'
---| 'prs.open'
---| 'prs.closed'
---| 'issues.all'
---| 'issues.open'
---| 'issues.closed'
---| 'ci.all'
---| 'ci.current_branch'
---| 'browse.contextual'
---| 'browse.branch'
---| 'browse.commit'
---| 'releases.all'
---| 'releases.draft'
---| 'releases.prerelease'

---@class forge.Scope
---@field kind forge.ScopeKind
---@field host string
---@field slug string
---@field repo_arg string
---@field web_url string
---@field owner string?
---@field namespace string?
---@field repo string?

---@class forge.LineRange
---@field start_line integer
---@field end_line integer

---@class forge.RepoTarget
---@field kind 'repo'
---@field form 'hosted'|'path'|'symbolic'
---@field text string
---@field host string?
---@field slug string?
---@field name string?
---@field via 'alias'|'remote'|'explicit'?
---@field alias string?
---@field remote string?

---@class forge.RevTarget
---@field kind 'rev'
---@field text string
---@field rev string?
---@field repo forge.RepoTarget?
---@field default_branch boolean?

---@class forge.BranchTarget
---@field kind 'branch'
---@field text string
---@field branch string

---@class forge.CommitTarget
---@field kind 'commit'
---@field text string
---@field commit string

---@class forge.LocationTarget
---@field kind 'location'
---@field text string
---@field rev forge.RevTarget
---@field path string
---@field range forge.LineRange?

---@class forge.HeadInput
---@field branch string?
---@field head_branch string?
---@field rev string?
---@field scope forge.Scope?
---@field head_scope forge.Scope?
---@field repo forge.RepoLike?
---@field project_id string?

---@class forge.PRRef
---@field num string
---@field scope forge.Scope?

---@class forge.HeadRef
---@field branch string
---@field scope forge.Scope?
---@field project_id string?

---@class forge.IssueRef
---@field num string
---@field scope forge.Scope?

---@class forge.SubjectRef
---@field num string
---@field scope forge.Scope?

---@class forge.ReleaseRef
---@field tag string
---@field scope forge.Scope?

---@class forge.RunRef
---@field id string
---@field scope forge.Scope?
---@field status string?
---@field url string?

---@alias forge.PRRefLike forge.PRRef|string
---@alias forge.IssueRefLike forge.IssueRef|string
---@alias forge.ReleaseRefLike forge.ReleaseRef|string
---@alias forge.RunRefLike forge.RunRef|string
---@alias forge.TargetValue forge.RepoTarget|forge.RevTarget|forge.BranchTarget|forge.CommitTarget|forge.LocationTarget
---@alias forge.RepoLike forge.Scope|forge.RepoTarget|string
---@alias forge.HeadLike forge.HeadInput|forge.HeadRef|forge.RevTarget|string

---@class forge.ScopedOpts
---@field scope forge.Scope?

---@class forge.TargetParseOpts
---@field resolve_repo boolean?
---@field aliases table<string, string>?
---@field default_repo string?

---@class forge.SurfaceOpts
---@field forge_name string?

---@class forge.SurfaceNamesOpts: forge.SurfaceOpts
---@field include_aliases boolean?
---@field include_all_aliases boolean?

---@class forge.SurfaceResolvedName
---@field canonical string
---@field invoked string
---@field alias string?

---@class forge.CmdError
---@field code string?
---@field message string

---@class forge.SystemResult
---@field code integer
---@field stdout string?
---@field stderr string?

---@class forge.CommandSubjectSpec
---@field kind string?
---@field min integer?
---@field max integer?

---@class forge.ModifierSpec
---@field kind 'value'|'flag'
---@field target string?
---@field values string[]?

---@class forge.CommandVerbDef
---@field subject forge.CommandSubjectSpec?
---@field modifiers string[]?
---@field legacy_modifiers string[]?
---@field required_modifiers string[]?
---@field modifier_values table<string, string[]>?

---@class forge.CommandFamilyDef
---@field name forge.CommandFamily
---@field surface string
---@field default_verb string?
---@field verb_order string[]
---@field verbs table<string, forge.CommandVerbDef>
---@field aliases table<string, string>?

---@class forge.Command
---@field family forge.CommandFamily
---@field invoked_family string
---@field family_alias string?
---@field name string
---@field surface string
---@field implicit boolean
---@field alias string?
---@field subject forge.CommandSubjectSpec?
---@field subjects string[]
---@field raw string[]
---@field modifiers table<string, any>
---@field declared_modifiers string[]
---@field declared_legacy_modifiers string[]
---@field legacy_modifiers string[]?
---@field parsed_modifiers table<string, any>
---@field modifier_values table<string, string[]>?
---@field required_modifiers string[]?
---@field default_policy table
---@field default_targets table
---@field range { start_line: integer, end_line: integer }?

---@class forge.Context
---@field id string
---@field root string
---@field branch string
---@field head string
---@field forge forge.Forge?
---@field has_file boolean
---@field loc string?

---@class forge.OpCallbacks
---@field on_success fun()?
---@field on_failure fun()?

---@class forge.RouteOpts: forge.ScopedOpts
---@field back fun()?
---@field forge_name string?
---@field context string?
---@field branch string?
---@field commit string?

---@class forge.PickerBackOpts: forge.RouteOpts

---@class forge.PickerLimitOpts: forge.PickerBackOpts
---@field limit integer?

---@class forge.RunViewOpts: forge.ScopedOpts
---@field job_id string?
---@field log boolean?
---@field failed boolean?

---@class forge.PRDetails
---@field title string
---@field body string
---@field url string?
---@field draft boolean?
---@field head_branch string
---@field base_branch string
---@field labels string[]?
---@field assignees string[]?
---@field reviewers string[]?
---@field milestone string?

---@class forge.IssueDetails
---@field title string
---@field body string
---@field labels string[]?
---@field assignees string[]?
---@field milestone string?

---@class forge.CommentMetadata
---@field labels string[]
---@field assignees string[]
---@field milestone string
---@field draft boolean
---@field reviewers string[]

---@class forge.SubmissionFields
---@field labels boolean?
---@field assignees boolean?
---@field milestone boolean?
---@field draft boolean?
---@field reviewers boolean?

---@class forge.SubmissionOps
---@field create forge.SubmissionFields?
---@field update forge.SubmissionFields?

---@class forge.Submission
---@field issue forge.SubmissionOps?
---@field pr forge.SubmissionOps?

---@class forge.CreatePROpts
---@field draft boolean?
---@field instant boolean?
---@field web boolean?
---@field back fun()?
---@field scope forge.Scope?
---@field head_branch string?
---@field head_scope forge.Scope?
---@field base_branch string?
---@field base_scope forge.Scope?

---@class forge.CurrentPROpts: forge.ScopedOpts
---@field forge forge.Forge?
---@field forge_name string?
---@field repo forge.RepoLike?
---@field head forge.HeadLike?
---@field head_branch string?
---@field head_scope forge.Scope?
---@field base_scope forge.Scope?
---@field project_id string?
---@field target_opts forge.TargetParseOpts?

---@class forge.PRActionOpts: forge.CurrentPROpts
---@field num string|integer?

---@class forge.ReviewOpts: forge.PRActionOpts
---@field adapter string?

---@class forge.BranchCIOpts: forge.CurrentPROpts
---@field branch string?

---@class forge.CreateIssueOpts
---@field web boolean?
---@field blank boolean?
---@field template string?
---@field back fun()?
---@field scope forge.Scope?

---@class forge.ReviewContext
---@field forge forge.Forge
---@field pr forge.PRRef
---@field adapter string
---@field opts table
---@field details fun(): forge.PRDetails?, string?

---@class forge.ReviewAdapter
---@field label string|fun(ctx: forge.ReviewContext): string?
---@field open fun(ctx: forge.ReviewContext)

---@class forge.PRState
---@field state string
---@field mergeable string
---@field review_decision string
---@field is_draft boolean

---@class forge.Check
---@field name string
---@field bucket string?
---@field state string?
---@field link string?
---@field run_id string?
---@field job_id string?
---@field startedAt string?
---@field completedAt string?
---@field elapsed string?
---@field scope forge.Scope?

---@class forge.CIRun
---@field id string
---@field name string
---@field branch string
---@field status string
---@field event string
---@field url string
---@field created_at string
---@field scope forge.Scope?

---@class forge.RepoInfo
---@field permission string
---@field merge_methods string[]

---@class forge.Capabilities
---@field draft boolean
---@field reviewers boolean
---@field per_pr_checks boolean
---@field ci_json boolean

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string, pr_one: string, pr_full: string, ci: string }
---@field capabilities forge.Capabilities
---@field submission forge.Submission?
---@field list_pr_json_cmd fun(self: forge.Forge, state: string, limit?: integer, scope?: forge.Scope): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string, limit?: integer, scope?: forge.Scope): string[]
---@field pr_fields { number: string, title: string, branch: string, state: string, author: string, created_at: string }
---@field issue_fields { number: string, title: string, state: string, author: string, created_at: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string, scope?: forge.Scope)
---@field browse_subject (fun(self: forge.Forge, num: string, scope?: forge.Scope))?
---@field browse fun(self: forge.Forge, loc: string, branch: string, scope?: forge.Scope)
---@field browse_branch fun(self: forge.Forge, branch: string, scope?: forge.Scope)
---@field browse_commit fun(self: forge.Forge, commit: string, scope?: forge.Scope)
---@field checkout_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field fetch_pr fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field pr_base_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field pr_for_branch_cmd fun(self: forge.Forge, branch: string, scope?: forge.Scope): string[]
---@field checks_cmd fun(self: forge.Forge, num: string): string
---@field check_log_cmd fun(self: forge.Forge, run_id: string, failed_only: boolean, job_id: string?, scope?: forge.Scope): string[]
---@field steps_cmd (fun(self: forge.Forge, run_id: string, scope?: forge.Scope): string[])?
---@field view_cmd (fun(self: forge.Forge, id: string, opts?: forge.RunViewOpts): string[])?
---@field summary_json_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field watch_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field cancel_run_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field rerun_run_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field run_status_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field list_web_url (fun(self: forge.Forge, kind: forge.WebKind, scope?: forge.Scope): string?)?
---@field browse_run (fun(self: forge.Forge, id: string, scope?: forge.Scope))?
---@field run_web_url (fun(self: forge.Forge, id: string, scope?: forge.Scope): string?)?
---@field job_web_url (fun(self: forge.Forge, run_id: string, job_id: string, scope?: forge.Scope): string?)?
---@field live_tail_cmd (fun(self: forge.Forge, run_id: string, job_id: string?, scope?: forge.Scope): string[])?
---@field list_runs_json_cmd fun(self: forge.Forge, branch: string?, scope?: forge.Scope, limit?: integer): string[]
---@field list_runs_cmd fun(self: forge.Forge, branch: string?, scope?: forge.Scope): string
---@field normalize_run fun(self: forge.Forge, entry: table): forge.CIRun
---@field run_log_cmd fun(self: forge.Forge, id: string, failed_only: boolean, scope?: forge.Scope): string[]
---@field merge_cmd fun(self: forge.Forge, num: string, method: string?, scope?: forge.Scope): string[]
---@field approve_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field repo_info fun(self: forge.Forge, scope?: forge.Scope): forge.RepoInfo
---@field pr_state fun(self: forge.Forge, num: string, scope?: forge.Scope): forge.PRState
---@field close_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field reopen_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field close_issue_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field reopen_issue_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field draft_toggle_cmd fun(self: forge.Forge, num: string, is_draft: boolean, scope?: forge.Scope): string[]?
---@field create_pr_cmd fun(self: forge.Forge, title: string, body: string, base: string, draft: boolean, scope?: forge.Scope, metadata?: forge.CommentMetadata): string[]
---@field update_pr_cmd fun(self: forge.Forge, num: string, title: string, body: string, scope?: forge.Scope, metadata?: forge.CommentMetadata, previous?: forge.CommentMetadata): string[]
---@field fetch_pr_details_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field parse_pr_details fun(self: forge.Forge, json: table): forge.PRDetails
---@field fetch_issue_details_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field parse_issue_details fun(self: forge.Forge, json: table): forge.IssueDetails
---@field create_pr_web_cmd (fun(self: forge.Forge, scope?: forge.Scope, head_scope?: forge.Scope, head_branch?: string, base_branch?: string): string[]?)?
---@field create_pr_web_url (fun(self: forge.Forge, scope?: forge.Scope, head_scope?: forge.Scope, head_branch?: string, base_branch?: string): string?)?
---@field default_branch_cmd fun(self: forge.Forge, scope?: forge.Scope): string[]
---@field checks_json_cmd (fun(self: forge.Forge, num: string, scope?: forge.Scope): string[])?
---@field template_paths fun(self: forge.Forge): string[]
---@field list_releases_json_cmd fun(self: forge.Forge, scope?: forge.Scope, limit?: integer): string[]
---@field release_fields { tag: string, title: string, is_draft: string?, is_prerelease: string?, is_latest: string?, published_at: string }
---@field browse_release fun(self: forge.Forge, tag: string, scope?: forge.Scope)
---@field delete_release_cmd fun(self: forge.Forge, tag: string, scope?: forge.Scope): string[]
---@field create_issue_cmd fun(self: forge.Forge, title: string, body: string, labels: string[]?, scope?: forge.Scope, metadata?: forge.CommentMetadata): string[]
---@field update_issue_cmd fun(self: forge.Forge, num: string, title: string, body: string, scope?: forge.Scope, metadata?: forge.CommentMetadata, previous?: forge.CommentMetadata): string[]
---@field issue_template_paths fun(self: forge.Forge): string[]
---@field create_issue_web_cmd (fun(self: forge.Forge, scope?: forge.Scope): string[]?)?
---@field create_issue_web_url (fun(self: forge.Forge, scope?: forge.Scope): string?)?
