---
name: feature-flow
description: Run the full issue implementation pipeline (BA triage, architect, implementation, review, commit) for a single GitHub issue
user-invocable: true
requires: [review, ba-triage]
requires-agents: [ba, architect, lead-dev, junior-dev, qa-assist, documentarian]
---

# Feature Flow Skill

> **Repo-specific guidance.** If `.llm-academy/feature-flow.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

When the user invokes `/feature-flow <issue-number>`, run the full implementation pipeline for that issue. This is an interactive, single-issue version of a batch processing pipeline with a human checkpoint after triage.

## Usage

```
/feature-flow 42
```

If no issue number is provided, ask the user which issue to work on (suggest candidates based on open issues and dependencies).

## Pipeline Overview

```
BA (Triage) ──checkpoint──> Architect ──> Implementation ──> /review skill ──> [Docs*] ──> BA (commit/PR/close)
   ↑ may be reused          ↑ user approval                  ↑ foreground       ↑ *only if source changed
   from a prior /ba-triage
```

Landing is always via pull request, so CI runs on every change and there is a reviewable history on GitHub. Direct-merge-to-default-branch is not used.

After BA triage, report the assessment to the user and wait for approval before continuing. The remaining steps auto-advance without pausing.

If a prior triage result already exists on the issue (e.g. the user ran `/ba-triage <number>` earlier), reuse the readiness/approach result instead of re-running that part of the BA agent — see Step 1.

## Step-by-Step Process

### Step 0: Setup

1. Fetch the issue with `mcp__github__issue_read` (or `gh issue view`).
2. Display a brief summary (title, labels, acceptance criteria).
3. **Detect worktree context** (see Worktree Awareness below). Record whether the current working directory is a worktree.
4. Create an isolated git branch: `feature/issue-<number>` from `origin/<default-branch>` (run `git fetch origin` first). In a worktree, create the branch from the current HEAD if and only if it matches `origin/<default-branch>`; otherwise fetch and base the branch on `origin/<default-branch>` directly.
5. Check issue labels for special handling (see Label Handling below).

#### Worktree Awareness

Before doing any git operations, run `git worktree list` to know the topology:

- **Main worktree mode** — current `pwd` matches the first `git worktree list` entry, and the default branch is checked out there. Safe to `git checkout <default-branch>` locally.
- **Worktree mode** — current `pwd` is a secondary entry (e.g. `.worktrees/<name>`). The default branch is checked out elsewhere. **Do NOT `git checkout <default-branch>` in this worktree** — git will refuse, and even if it didn't, you'd be editing files in another working copy through this one.

Treat the main worktree (where the user is actively working) as read-only from this session. Never run `git checkout`, `git merge`, or file edits against its path. All implementation work, including conflict resolution, must happen on the feature branch inside the current worktree.

### Step 1: BA Triage (background agent — reuse if already done)

#### Step 1a: Check for a prior triage result

The `/ba-triage` skill leaves a machine-readable footer on its triage comment in this form:

```
<!-- triage-result: ready=<bool> approach=<scaffold|lead-dev|junior|needs-architect|> defer_label=<label-or-empty> -->
```

Fetch the issue's comments (`gh issue view <num> --json comments`) and look for the most recent comment containing that marker.

- **If found:** parse it. Treat the parsed `ready` / `approach` / `defer_label` as the triage outcome. Skip the BA agent's readiness check.
- **If not found:** run the BA readiness check below.

The `/ba-triage` skill is responsible for the readiness/approach decision. The project backlog scope-bundling sweep (Step 1c) always runs fresh inside `/feature-flow` regardless of whether prior triage was reused — the backlog is mutable and may have changed since triage.

#### Step 1b: BA readiness check (skipped when reusing)

Launch a **ba** agent in the background to triage the issue.

The BA must determine:
- **Is the issue ready?** Check for: blocked dependencies, insufficient detail, needs-design, duplicate, out-of-scope.
- **If ready, can it be fast-tracked?** Assess whether the issue is well-specified enough to skip the architect:
  - `fast-track to scaffold` — has architectural plan, send to lead-dev + junior-dev
  - `fast-track to lead-dev` — clear implementation steps, complex, send to lead-dev
  - `fast-track to junior-dev` — simple and fully specified
  - `needs-architect` — needs architect review (default if unsure)

**BA agent prompt context must include:**
- The full issue body and comments
- The issue's current labels
- A summary of the open backlog (for dependency awareness)

The BA agent should leave a triage comment on the issue in the same format `/ba-triage` produces (so later re-runs can detect and reuse it).

#### Step 1c: Project backlog scope-bundling sweep (always runs)

Whether the readiness result was freshly produced or reused, scan the project's backlog file (e.g., `TODOS.md`, `BACKLOG.md`, or equivalent) for entries that could be cheaply rolled into this issue's scope. You can do this inline or fold it into the BA agent's task when one is being launched anyway.

A backlog item is a bundling candidate when it:
- Touches the same files/system as the issue
- Would be near-zero marginal cost to fix while the implementer is already in that code
- Is small enough that bundling won't bloat the PR or muddy the issue's commit story

A backlog item is **not** a bundling candidate when it:
- Belongs to a different system entirely
- Implies a non-trivial design decision
- Is large enough to deserve its own issue and review

Produce a **bundling suggestions** list (zero or more entries). Each entry names the item and a one-sentence justification for why it fits.

#### Step 1d: Report and checkpoint

**Report to the user**:
- Whether the readiness result was freshly produced or reused (when reused, include the comment timestamp/author)
- Ready or deferred (with reasoning)
- If deferred: what label was suggested, what action was taken
- If ready: the recommended approach (fast-track type or needs-architect)
- **Bundling suggestions** (if any): list each candidate with the justification

**Wait for user approval before proceeding.** Use AskUserQuestion:
- If deferred: ask if they want to override and proceed anyway
- If ready: show the recommended approach and ask if they agree or want to change it
- If reused: include a "re-run triage" option in case the issue has changed materially since the prior triage
- If bundling suggestions exist: ask which (if any) to roll into scope. Include "none" as an explicit option. For each accepted suggestion, append the item text to the issue's working scope so downstream agents see it.

### Step 2: Architect Review (background agent, skip if fast-tracked)

Launch an **architect** agent in the background. The architect reviews the issue and recommends one of:
- `scaffold` — lead-dev scaffolds, junior-dev implements
- `lead-dev` — lead-dev implements directly
- `junior` — junior-dev implements directly
- `direct` — architect implements directly
- `decision-required` — user-facing ambiguity, defer for human input

The architect also checks for:
- **Dependencies**: Is this issue blocked by unresolved issues? Does it unblock others?
- **Product decisions**: If the architect makes a product decision, flag it for review.

When done, report the architect's recommendation and proceed to implementation.

If `decision-required`: comment on the issue, add the label, report to user, and stop.

If a product decision was made: create a `product-decision-review` issue, report it, and continue.

### Step 3: Implementation (background agent)

Based on the approach (from BA fast-track or architect recommendation), launch the appropriate agent(s):

| Approach | Agent(s) | Description |
|----------|----------|-------------|
| `scaffold` | **lead-dev** then **junior-dev** | Lead scaffolds interfaces/stubs, junior fills in bodies |
| `lead-dev` | **lead-dev** | Lead implements directly |
| `junior` | **junior-dev** | Junior implements directly |
| `direct` | **architect** | Architect implements directly |

Each implementation agent should:
- Read the issue, any handoff docs, and relevant source files
- Write the implementation
- Run the project's build and test commands to verify

### Step 4: Review (`/review` skill, foreground)

Invoke the **`/review`** skill via the Skill tool. The skill runs in the foreground and: (1) spawns the `reviewer` subagent as the primary pass; (2) runs an adversarial cross-model pass whenever a secondary model is reachable — via a project's wrapper script or, absent one, a direct CLI probe (see `/review` Step 3); (3) synthesizes both sources, auto-fixes trivial findings inline, and batch-asks the user about substantive ones; (4) writes `handoffs/review-{issue}.md` and returns one of these verdicts on its final line:

- `approved` — proceed to commit
- `non_blocking_issues` — capture each remaining finding (see Step 4a below), then proceed to commit
- `blocking_issues` — send back for fixes (max 3 loops)

**No-changes shortcut:** If `git diff --quiet origin/<default-branch>` shows no changes after implementation, skip the skill entirely and treat the verdict as `approved`. (Compare against the remote base, not `HEAD` — local commits don't count as "no changes" for a PR review.)

**Why foreground:** the skill needs main-context execution for its AskUserQuestion-based fix-first loop, and it blocks the conversation for ~1–5 min when an adversarial pass runs. This is intentional — bundling fix-first and non-blocking capture into one blocking window keeps the user in a single decision flow rather than two.

**Skill failure handling:** if the skill aborts (a reviewer-agent failure surfaces to the user; an unreachable or failing adversarial tool is handled internally by graceful skip), treat that as a `blocking_issues` verdict and stop the pipeline. Do not silently approve.

#### Step 4a: Non-blocking finding capture

When `/review` returns `non_blocking_issues`, the skill has already written each remaining finding to `handoffs/review-{issue}.md`. Read that file to enumerate the findings. Do **not** silently create follow-up issues. For each finding, classify it and ask the user how to capture it. Use AskUserQuestion with these options:

- **`backlog`** — Append to the project's backlog file under the appropriate section with a priority tier and a "Surfaced by:" line referencing this issue. Use for small, well-scoped concerns with a clear file/symbol pointer and no design ambiguity.
- **`issue`** — Create a GitHub issue (labeled `follow-up-issue`) referencing this issue as the source. Use for findings that need real spec work — design decisions, multi-file refactors, anything that would bloat the backlog file or needs discussion before implementation.
- **`skip`** — Drop the finding. Use for trivial nits that aren't worth tracking.

Suggest a default per finding based on size and shape (the reviewer's own characterization usually makes this obvious). Present all findings in a single AskUserQuestion turn so the user isn't drip-fed prompts.

For each `backlog` choice: edit the backlog file directly, placing the entry under the section that matches the affected system. Match the existing format.

For each `issue` choice: draft the body to `/tmp/issue-body.md`, then `gh issue create --body-file`. Link the new issue to the appropriate epic per the project's tracking workflow.

### Step 5: QA Handoff (when behavior changes)

If the implementation changes observable behavior (new features, changed UI, modified mechanics, bug fixes that affect user-facing behavior), generate a QA handoff document at `docs/qa-handoffs/<issue-number>.md`.

Launch a **qa-assist** agent to produce the document. The document should include:
- **Summary**: What changed and why (1–2 sentences)
- **Test steps**: Numbered manual verification steps for **the new behavior the diff introduced** — not a generic "make sure everything still works" sweep
- **Expected behavior**: What the user should see at each step
- **Edge cases**: Boundary conditions of the new behavior worth checking
- **Impact notes** (only when relevant):
  - *System/mechanic impact* — if the diff plausibly touches a load-bearing system (auth, persistence, ordering, money, a core algorithm), call out the affected system with one targeted quick-check step.
  - *Content impact* — if the change invalidates user-authored content (hand-tuned data, assets, fixtures), flag it as a heads-up that re-authoring is needed — not a pass/fail step.

Scope the steps to what the diff changed. Whether to add regression coverage for pre-existing behavior the diff doesn't touch is a project-philosophy call: early-stage / rewrite-freely projects generally shouldn't; stability-focused projects should. Follow your project's stance (and the qa-assist agent's guidance).

**Skip this step** for purely internal refactors, test-only changes, tooling/skill updates, or documentation-only changes — anything where there's nothing new to observe.

### Step 6: Documentation (optional — gated on source changes)

If the implementation changed **source code**, run the documentarian to keep outward-facing docs honest about what shipped. This stage is gated — it does real work only when the diff touches source.

**Gate (cheap pre-check):** look at `git diff origin/<default-branch> --stat`. If the change is obviously docs-only, config-only, or test-only, **skip this step**. Otherwise launch the documentarian — it self-gates against the project's precise source globs (from its overlay) and no-ops if it concludes no documented surface is affected.

Launch a **documentarian** agent in the background. It will:
- Reconcile design intent (the feature's spec doc + `handoffs/design-{issue}.md`) against what actually shipped (`git diff origin/<default-branch>`).
- Update the outward-facing surfaces the change affects — README/usage, CHANGELOG/release notes, reference docs — sourced from intent + diff, not by paraphrasing the code.
- Leave a one-line *as-built* note on the spec (or the FEATURE_LOG entry) wherever shipped behavior diverged from the plan.
- Write edits directly into files on the feature branch (it does **not** commit) and report which surfaces it touched.

The doc edits are committed together with the code by Step 7 (BA Cleanup) — there is no separate docs PR. If the documentarian reports it couldn't source a change's rationale from the design/spec, surface that gap rather than letting it invent prose.

**Skip this step** when the gate above says no source changed, or when the project maintains no documented surfaces (no overlay and no README/CHANGELOG) — there's nothing to propagate to.

### Step 7: BA Cleanup (background agent)

Launch a **ba** agent to:
1. Stage and commit changes with an appropriate message (include `Co-Authored-By` attribution per the project's convention)
2. Do NOT push yet

After the BA agent completes, land the change via pull request:

1. Bring the feature branch up to date with the default branch:
   - `git fetch origin`
   - In worktree mode: `git merge origin/<default-branch> --no-edit` from inside the current worktree.
   - In main worktree mode: same — stay on the feature branch and merge `origin/<default-branch>` into it. Do not check out the default branch.
   - Resolve any conflicts on the feature branch only. Never touch a path that's checked out in another worktree. Run the project's test suite after resolution.
   - If the merge introduces a new commit, that's fine — the PR will include it.
2. `git push origin feature/issue-<number>` (use `-u` on first push).
3. Draft the PR body to `/tmp/pr-<number>-body.md` (use the Write tool, not heredoc). Include `Closes #<number>` so the issue auto-closes on merge.
4. `gh pr create --base <default-branch> --head feature/issue-<number> --title "<commit-title>" --body-file /tmp/pr-<number>-body.md`
5. **Ask the user how to land**: auto-merge via `gh pr merge --merge --delete-branch` (or `--squash` / `--rebase` per project convention), or leave the PR open for them to review and merge manually. Default: ask first, never auto-merge without confirmation.
6. If the user opts to merge: run `gh pr merge --merge --delete-branch <PR#>` (the `--delete-branch` flag handles both local and remote branch deletion after merge).
7. After merge: if `Closes #<n>` didn't auto-close the issue, close it with a summary comment. Then handle dependency resolution.

Report the final result to the user, including the PR URL.

#### Step 7a: Update FEATURE_LOG (if the project uses one)

If `FEATURE_LOG.md` exists at the repo root, update it after the PR merges (or is confirmed merged):

1. Find the entry for the feature this issue covers (match by title keywords or `See:` issue number).
2. If found: assess whether the vision doc now matches the implementation.
   - More work planned per the vision doc → set status to `partially-live`.
   - Vision is fully implemented → set status to `live`.
   - No vision doc exists → set status to `code-present` (do not promote to `live` without a vision doc).
3. Add the PR number to the `See:` line.
4. If no entry exists, create one at the appropriate status and flag to the user that conviction should be confirmed.
5. Skip silently if the issue is purely infra/tooling with no named feature in FEATURE_LOG, or if the project does not maintain a FEATURE_LOG. See `/feature-log` for format and vocabulary.

## Label Handling

Before triage, check issue labels:

| Label | Action |
|-------|--------|
| `product-decision-review` | Defer silently — requires human review |
| `planning` | Defer silently — feature request not yet decided |
| `follow-up-issue` | Fast-track to lead-dev (skip triage and architect) |
| `blocked` | Check if blockers are resolved; if not, defer |
| `decision-required` | Defer — needs human product/design input |

### Customization

Add or remove labels to match your project's workflow. Common additions:
- `needs-design` — requires design doc or RFC first
- `duplicate` — already tracked elsewhere
- `wontfix` / `out-of-scope` — not aligned with current goals

## Dependency Handling

### Blocked issues
If the architect detects this issue is blocked by unresolved dependencies:
- Comment on the issue with blocker list (`**Blockers**: #50, #60`)
- Add `blocked` label
- Report to user and stop

### Resolving issues
If this issue unblocks other issues:
- Comment on the resolving issue listing what it unblocks
- After commit: check each dependent issue's remaining blockers
- Only remove `blocked` label when ALL blockers are resolved
- Add appropriate comments to dependent issues

## Error Handling

- **Implementation fails (build/test errors):** Report the error, ask user if they want to retry or abort.
- **Review rejects 3 times:** Stop and report. Ask user for manual intervention.
- **Merge conflict:** Resolve inside the *current* worktree on the feature branch. Never touch the main worktree's checkout. For trivial conflicts (whitespace, adjacent imports, comment-only differences), resolve and continue. For substantive conflicts, surface to the user and ask how to proceed.
- **Pre-existing test failures on the default branch:** Verify by running the failing test against `origin/<default-branch>` directly. If the failure is pre-existing, note it in the PR description and continue — do not attempt to fix out-of-scope failures inside this issue's PR.
- **Agent fails:** Report the failure, offer to retry or skip the step.
- **`gh` CLI not authenticated:** Surface immediately; the PR landing path requires a working `gh`.

## Git Workflow

Landing is always via pull request. CI runs on every change and there is a reviewable history on GitHub.

1. Before starting: `git fetch origin && git checkout -b feature/issue-<number> origin/<default-branch>`
2. All work happens on the issue branch.
3. After review approval: commit on the issue branch (no push yet).
4. Bring feature branch in sync with the default branch: `git fetch origin && git merge origin/<default-branch> --no-edit` (resolve conflicts on the feature branch; never check out the default branch).
5. `git push -u origin feature/issue-<number>`.
6. `gh pr create --base <default-branch> --head feature/issue-<number> --body-file /tmp/pr-<number>-body.md`. PR body should include `Closes #<number>` so the issue auto-closes on merge.
7. Confirm with user, then `gh pr merge --merge --delete-branch <PR#>` (or let user merge manually).
8. Local cleanup: `git branch -d feature/issue-<number>` (only after the PR has merged).

If anything fails during merge/push/PR, leave the branch intact and report — never destructively reset or force-push.

### Hard rules
- Never `git checkout <default-branch>`, `git merge`, `git rebase`, or otherwise modify a branch that's checked out in another worktree.
- Never edit files under another worktree's path. All file operations stay inside the current worktree's tree.
- Never direct-merge to the default branch locally and push — landing must go through `gh pr create` + `gh pr merge` so CI runs.

## Customization Points

When adapting this skill for your project, update the following:

1. **Build/test commands**: Replace references to build and test commands with your project's equivalents (e.g., `npm test`, `cargo build`, `dotnet test`, `make check`).
2. **Default branch**: The skill assumes `main` or `master` — adjust to your default branch name.
3. **Branch naming**: Change `feature/issue-<number>` to match your project's convention.
4. **Backlog file**: Replace references to the project backlog scope-bundling sweep with your project's backlog file (e.g., `TODOS.md`, `BACKLOG.md`).
5. **Co-Authored-By**: Update the attribution line to match your project's convention.
6. **Labels**: Add or remove labels in the Label Handling section to match your workflow.
7. **Tracking/epics**: Update the logic for linking new issues to epics to match your project's tracking structure.
8. **Agent models**: The pipeline uses agents defined in the `agents/` directory. Ensure those agents are configured for your project's tech stack.

## Reporting

Throughout the pipeline, keep the user informed:
- After each step completes, briefly summarize what happened
- At the end, report:
  - What was done (files changed, tests passed)
  - Any follow-up issues created
  - Any product decision review issues created
  - Any dependencies resolved

## Notes

- This skill processes ONE issue at a time. For batch processing, consider a shell script wrapper that invokes this flow in headless mode for multiple issues.
- The checkpoint after triage lets the user redirect the approach before expensive implementation work begins.
- The BA readiness/approach check is also available standalone as `/ba-triage <number>`. When the user has already run it, this skill detects the triage comment footer and reuses the readiness result. The project backlog scope-bundling sweep always runs fresh inside `/feature-flow` because the backlog may have changed since triage.
- The BA, architect, and implementation agents run in the background so the conversation stays free for discussion. Step 4 (Review) runs **foreground** via the `/review` skill, because its synthesis and fix-first flow need AskUserQuestion in the main context.
