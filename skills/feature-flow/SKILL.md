---
name: feature-flow
description: Run the full issue implementation pipeline (BA triage, architect, implementation, review, commit) for a single GitHub issue
user-invocable: true
---

# Feature Flow Skill

When the user invokes `/feature-flow <issue-number>`, run the full implementation pipeline for that issue. This is an interactive, single-issue version of a batch processing pipeline with a human checkpoint after triage.

## Usage

```
/feature-flow 42
```

If no issue number is provided, ask the user which issue to work on (suggest candidates based on open issues and dependencies).

## Pipeline Overview

```
BA (Triage) ──checkpoint──> Architect ──> Implementation ──> Reviewer ──> BA (commit/push/close)
              ↑ user approval
```

After BA triage, report the assessment to the user and wait for approval before continuing. The remaining steps auto-advance without pausing.

## Step-by-Step Process

### Step 0: Setup

1. Fetch the issue with `mcp__github__issue_read`.
2. Display a brief summary (title, labels, acceptance criteria).
3. Create an isolated git branch: `feature-flow/issue-<number>` from the default branch.
4. Check issue labels for special handling (see Label Handling below).

### Step 1: BA Triage (background agent)

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

When the BA agent completes, **report to the user**:
- Ready or deferred (with reasoning)
- If deferred: what label was suggested, what action was taken
- If ready: the recommended approach (fast-track type or needs-architect)

**Wait for user approval before proceeding.** Use AskUserQuestion:
- If deferred: ask if they want to override and proceed anyway
- If ready: show the recommended approach and ask if they agree or want to change it

### Step 2: Architect Review (background agent, skip if fast-tracked)

Launch an **architect** agent in the background. The architect reviews the issue and recommends one of:
- `scaffold` — lead-dev scaffolds, junior-dev implements
- `lead-dev` — lead-dev implements directly
- `junior` — junior-dev implements directly
- `direct` — architect implements directly
- `decision-required` — user-facing ambiguity, defer for human input

The architect also checks for:
- **Dependencies**: Is this issue blocked by unresolved issues? Does it unblock others?
- **Product decisions**: If the architect makes a product decision that should be reviewed, flag it.

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

### Step 4: Review (background agent)

Launch a **reviewer** agent to check the implementation.

The reviewer returns one of:
- `approved` — proceed to commit
- `non_blocking_issues` — create follow-up issues (labeled `follow-up-issue`), proceed to commit
- `blocking_issues` — send back for fixes (max 3 loops)

**No-changes shortcut:** If `git diff --quiet HEAD` shows no changes after implementation, skip review entirely.

### Step 5: BA Cleanup (background agent)

Launch a **ba** agent to:
1. Stage and commit changes with an appropriate message (include `Co-Authored-By` attribution)
2. Do NOT push yet

After the BA agent completes:
1. Switch to the default branch and merge the issue branch
2. Push to origin
3. Close the issue with a summary comment
4. Delete the issue branch
5. Handle dependency resolution (comment on dependent issues, remove `blocked` labels when all blockers resolved)

Report the final result to the user.

## Label Handling

Before triage, check issue labels for special flow:

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
- **Merge conflict:** Abort merge, report to user, leave branch intact for manual resolution.
- **Agent fails:** Report the failure, offer to retry or skip the step.

## Git Workflow

1. Before starting: `git checkout -b feature-flow/issue-<number>` from the default branch
2. All work happens on the issue branch
3. After review approval: commit on the issue branch (no push)
4. After commit: checkout default branch, merge issue branch, push
5. Cleanup: delete the issue branch

If anything fails during merge/push, leave the branch intact and report.

## Customization Points

When adapting this skill for your project, update the following:

1. **Build/test commands**: Replace references to build and test commands with your project's equivalents (e.g., `npm test`, `cargo build`, `dotnet test`, `make check`).
2. **Branch naming**: Change `feature-flow/issue-<number>` to match your project's branch convention.
3. **Default branch**: The skill assumes `main` or `master` — adjust to your default branch name.
4. **Co-Authored-By**: Update the attribution line to match your project's convention.
5. **Labels**: Add or remove labels in the Label Handling section to match your workflow.
6. **Agent models**: The pipeline uses agents defined in the `agents/` directory. Ensure those agents are configured for your project's tech stack.

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
- All pipeline agents run in the background so the conversation stays free for discussion.
- The skill follows the agent pipeline: feature-creator (optional) → architect → lead-dev → junior-dev → reviewer → ba.
