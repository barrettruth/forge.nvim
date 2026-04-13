---@meta

---@alias forge.ScopeKind 'github'|'gitlab'|'codeberg'

---@class forge.Scope
---@field kind forge.ScopeKind
---@field host string
---@field slug string
---@field repo_arg string
---@field web_url string
---@field owner string?
---@field namespace string?
---@field repo string?

---@class forge.PRRef
---@field num string
---@field scope forge.Scope?

---@class forge.IssueRef
---@field num string
---@field scope forge.Scope?

---@class forge.ReleaseRef
---@field tag string
---@field scope forge.Scope?

---@alias forge.PRRefLike forge.PRRef|string

---@class forge.ScopedOpts
---@field scope forge.Scope?

---@class forge.PickerBackOpts: forge.ScopedOpts
---@field back fun()?

---@class forge.PickerLimitOpts: forge.PickerBackOpts
---@field limit integer?

---@class forge.RunViewOpts: forge.ScopedOpts
---@field job_id string?
---@field log boolean?
---@field failed boolean?

---@class forge.PRDetails
---@field title string
---@field body string
---@field head_branch string
---@field base_branch string

---@class forge.IssueDetails
---@field title string
---@field body string

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

---@class forge.CreateIssueOpts
---@field web boolean?
---@field blank boolean?
---@field template string?
---@field back fun()?
---@field scope forge.Scope?

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
---@field per_pr_checks boolean
---@field ci_json boolean

---@class forge.Forge
---@field name string
---@field cli string
---@field kinds { issue: string, pr: string }
---@field labels { issue: string, pr: string, pr_one: string, pr_full: string, ci: string }
---@field capabilities forge.Capabilities
---@field list_pr_json_cmd fun(self: forge.Forge, state: string, limit?: integer, scope?: forge.Scope): string[]
---@field list_issue_json_cmd fun(self: forge.Forge, state: string, limit?: integer, scope?: forge.Scope): string[]
---@field pr_fields { number: string, title: string, branch: string, state: string, author: string, created_at: string }
---@field issue_fields { number: string, title: string, state: string, author: string, created_at: string }
---@field view_web fun(self: forge.Forge, kind: string, num: string, scope?: forge.Scope)
---@field browse fun(self: forge.Forge, loc: string, branch: string, scope?: forge.Scope)
---@field browse_branch fun(self: forge.Forge, branch: string, scope?: forge.Scope)
---@field browse_commit fun(self: forge.Forge, sha: string, scope?: forge.Scope)
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
---@field run_status_cmd (fun(self: forge.Forge, id: string, scope?: forge.Scope): string[])?
---@field live_tail_cmd (fun(self: forge.Forge, run_id: string, job_id: string?, scope?: forge.Scope): string[])?
---@field list_runs_json_cmd fun(self: forge.Forge, branch: string?, scope?: forge.Scope, limit?: integer): string[]
---@field list_runs_cmd fun(self: forge.Forge, branch: string?, scope?: forge.Scope): string
---@field normalize_run fun(self: forge.Forge, entry: table): forge.CIRun
---@field run_log_cmd fun(self: forge.Forge, id: string, failed_only: boolean, scope?: forge.Scope): string[]
---@field merge_cmd fun(self: forge.Forge, num: string, method: string, scope?: forge.Scope): string[]
---@field approve_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field repo_info fun(self: forge.Forge, scope?: forge.Scope): forge.RepoInfo
---@field pr_state fun(self: forge.Forge, num: string, scope?: forge.Scope): forge.PRState
---@field close_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field reopen_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field close_issue_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field reopen_issue_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field draft_toggle_cmd fun(self: forge.Forge, num: string, is_draft: boolean, scope?: forge.Scope): string[]?
---@field create_pr_cmd fun(self: forge.Forge, title: string, body: string, base: string, draft: boolean, scope?: forge.Scope): string[]
---@field update_pr_cmd fun(self: forge.Forge, num: string, title: string, body: string, scope?: forge.Scope): string[]
---@field fetch_pr_details_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field parse_pr_details fun(self: forge.Forge, json: table): forge.PRDetails
---@field fetch_issue_details_cmd fun(self: forge.Forge, num: string, scope?: forge.Scope): string[]
---@field parse_issue_details fun(self: forge.Forge, json: table): forge.IssueDetails
---@field create_pr_web_cmd (fun(self: forge.Forge, scope?: forge.Scope, head_scope?: forge.Scope, head_branch?: string, base_branch?: string): string[]?)?
---@field create_pr_web_url (fun(self: forge.Forge, scope?: forge.Scope, head_scope?: forge.Scope, head_branch?: string, base_branch?: string): string?)?
---@field default_branch_cmd fun(self: forge.Forge, scope?: forge.Scope): string[]
---@field checks_json_cmd (fun(self: forge.Forge, num: string, scope?: forge.Scope): string[])?
---@field template_paths fun(self: forge.Forge): string[]
---@field list_releases_json_cmd fun(self: forge.Forge, scope?: forge.Scope): string[]
---@field release_fields { tag: string, title: string, is_draft: string?, is_prerelease: string?, is_latest: string?, published_at: string }
---@field browse_release fun(self: forge.Forge, tag: string, scope?: forge.Scope)
---@field delete_release_cmd fun(self: forge.Forge, tag: string, scope?: forge.Scope): string[]
---@field create_issue_cmd fun(self: forge.Forge, title: string, body: string, labels: string[]?, scope?: forge.Scope): string[]
---@field update_issue_cmd fun(self: forge.Forge, num: string, title: string, body: string, scope?: forge.Scope): string[]
---@field issue_template_paths fun(self: forge.Forge): string[]
---@field create_issue_web_cmd (fun(self: forge.Forge, scope?: forge.Scope): string[]?)?
---@field create_issue_web_url (fun(self: forge.Forge, scope?: forge.Scope): string?)?
