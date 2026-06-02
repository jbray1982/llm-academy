---
name: next-issue
description: Auto-compact context and begin working on the next GitHub issue
user-invocable: true
---

# Next Issue Skill

> **Repo-specific guidance.** If `.llm-academy/next-issue.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

When the user invokes `/next-issue [number]`, compact the conversation context and begin discussion of a new issue. If no issue number is provided, suggest one based on project status.

## Process

### 1. Compact Context
- Use the **Bash tool** to run `claude compact` — this actually compacts the conversation and frees up context window before starting fresh on a new issue. The `/compact` slash command cannot be invoked programmatically from within a skill, so you MUST use `Bash("claude compact")` instead.

### 2. Determine the Issue

**If an issue number was provided** (e.g., `/next-issue 72`):
- Fetch the issue with GitHub MCP tool `mcp__github__issue_read` (load with ToolSearch if needed)
- Display the issue title, body, and status
- Proceed to step 3

**If no issue number was provided** (e.g., just `/next-issue`):
- Check the project board and current milestone for open issues using `mcp__github__list_issues` with milestone and state filters
- Check issue dependencies — look for issues whose dependencies are all closed
- Cross-reference with tracking/epic issues to understand sequencing
- Suggest 1-3 issues that make sense to tackle next, with a brief rationale for each
- Ask the user which one to work on via **AskUserQuestion** (one option per candidate, each labeled with the issue number + short title; the user can always pick "Other" to name a different issue)
- Once the user picks one, fetch the full issue details

### 3. Begin Discussion
- Display the issue summary (title, acceptance criteria, dependencies)
- Note any dependencies that are still open (blockers)
- Identify the key files likely to be touched based on the issue description
- Ask the user if they'd like to enter plan mode or discuss the approach first

## Response Format

When suggesting issues (prefix each with a status marker — ✅ ready / all deps closed, ⏳ has an open blocker, 🔼 unblocks other work):
```
Here are candidates for the next issue:

1. ✅ **#XX — Title** — [1-line rationale for why this is ready/valuable next]
2. ⏳ **#YY — Title** — [1-line rationale, note the open blocker]
3. 🔼 **#ZZ — Title** — [1-line rationale, note what it unblocks]
```

When starting an issue:
```
## Issue #XX — Title

[Brief summary of what needs to be done]

**Acceptance Criteria**:
- [ ] [Key criteria from issue]

**Dependencies**: [All resolved | #NN still open]

**Key files**: [List of files likely to be modified]
```

## Notes

- The compact step is critical — it prevents context overflow when switching between issues
- When suggesting issues, prefer issues whose dependencies are all resolved
- Consider the natural sequencing from tracking/epic issues
- Don't suggest issues that are assigned to someone else or already in progress
