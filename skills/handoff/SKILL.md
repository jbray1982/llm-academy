---
name: handoff
description: Write a minimal handoff prompt to /tmp/ so a fresh context (post-/clear, or a new session for the next logical step) can resume the current task. Leans on the project's auto-loaded instructions and any session-memory index — captures only what is NOT already available for free.
user-invocable: true
---

# Handoff Skill

When the current context is bloated mid-task and the user wants to `/clear` and continue, or wants to spin a new context for the next logical step, this skill writes a small markdown prompt to `/tmp/` that the fresh context can read to pick up exactly where this one left off.

## Why this is minimal

The fresh context already gets a lot for free:
- **Your project's instructions file** (e.g. `CLAUDE.md`) loads automatically — conventions, architecture, settled decisions.
- **A session-memory layer**, if your project uses one (e.g. the [claude-mem](https://github.com/) plugin), injects a recent-observations index with IDs at SessionStart, plus ID-based fetch (`get_observations([...])`) and search for progressive disclosure.
- **`git status` / `gh`** are available to re-derive the working-tree and issue/PR state.

So the handoff prompt's job is NOT to re-summarize the project or the recent timeline. Its job is to capture the **edge state** — the things the fresh context cannot derive from the instructions file, the memory index, or `git status`:

1. What the active task actually is (in one or two sentences).
2. The next concrete step to take.
3. Which specific memory IDs are load-bearing for this task (the SessionStart index only shows a limited window; older IDs may be off-screen). *(Skip this section entirely if your project has no session-memory layer.)*
4. In-flight decisions / assumptions that haven't been written down yet.
5. Files, branches, PRs, or issues the new context should verify still exist before acting on them.

If the current context can write those things into ~40 lines, the fresh context can resume with one `Read` call and a few lookups.

> **No session-memory layer?** Drop the "Load-bearing memory" section and add a little more "where we are" context to compensate — the instructions file + `git status` are then the only free inputs.

## Usage

```
/handoff                  # auto-derive slug from active task
/handoff <slug>           # explicit slug, e.g. /handoff notification-digest
```

## Process

### Step 1: Read the room

Before writing anything, look at the current conversation in your head and answer:

- **Task statement** — what are we doing? One or two sentences. If genuinely ambiguous (you can't name it), ask the user once: "What should I capture as the task?" Otherwise don't ask.
- **Last completed step** — the most recent thing that finished cleanly.
- **Next intended step** — what you were about to do (or what's blocking it).
- **Open loops** — decisions the user just made, assumptions you're operating on, things you discovered but haven't acted on yet. These are the things most likely to be lost in a `/clear`.
- **Load-bearing IDs** (if a memory layer exists) — memory IDs already referenced in the current conversation, plus any older ones that matter. If uncertain, run a single memory search with the task statement as the query (limit 5–8) and keep only the clearly-relevant ones.
- **Verify-targets** — file paths, branches, PRs, issues, scripts the handoff names by reference. The fresh context should sanity-check these (`git status`, `gh pr view`, `ls`) before acting.

### Step 2: Choose the slug

If the user passed one, use it. Otherwise derive a short kebab-case slug from the task (e.g. `notification-digest`, `auth-refactor`, `handoff-skill`). Keep it under ~30 chars.

### Step 3: Write `/tmp/handoff-<slug>.md`

Use the Write tool. Use this template — keep each section terse. If a section is genuinely empty (no open loops, nothing to verify), include the header with a single `- none` line so the fresh context knows you considered it.

```markdown
# Handoff: <one-line task title>

_Written: <YYYY-MM-DD HH:MM> from session continuing <branch or worktree if relevant>_

## Task
<1–2 sentences. What we are doing and why, no more.>

## Where I am
- Last done: <one line>
- Next step: <one line — the very next action the fresh context should take>
- Blocker (if any): <one line, or omit>

## Load-bearing memory
(omit this whole section if the project has no session-memory layer)
Fetch with `get_observations([...])` as needed. Do not pre-fetch all of them — fetch only when a decision depends on the detail.

- `<ID>` — <one-line why this matters for the task>
- `<ID>` — <one-line why>

(SessionStart will auto-inject recent observations; these are the ones likely to be load-bearing but off-screen or easy to miss.)

## Open loops (not written down yet)
- <in-flight decision, assumption, or finding that hasn't been captured>
- <...>

## Verify before acting
- `<file or path>` — <what to confirm: exists, contains X, on branch Y>
- `<gh issue / PR / branch>` — <state to confirm>

## Resume incantation
```
Read /tmp/handoff-<slug>.md and continue from "Next step".
```
```

### Step 4: Tell the user

Print two lines and stop:

```
Handoff written: /tmp/handoff-<slug>.md
After /clear, paste: Read /tmp/handoff-<slug>.md and continue from "Next step".
```

That's the whole skill. Do not print the prompt body inline — the user can `cat` it if they want to review before clearing.

## Do NOT

- Do NOT re-summarize the instructions file, the project, the architecture, or the recent memory timeline. The fresh context gets all of that automatically.
- Do NOT embed the full content of memory observations. IDs only; let the fresh context fetch what it needs.
- Do NOT commit, push, or modify any tracked file. The handoff is scratch; `/tmp/` is the right place.
- Do NOT spawn agents or run long tool chains to "make sure" things are captured. If uncertain, ask the user one focused question. Otherwise write what you know and ship it.
- Do NOT use bash heredoc to create the file — use the Write tool (typically pre-approved for `/tmp/`).
- Do NOT ask the user to confirm the handoff body before writing. The whole point is frictionless context-swap; the user will course-correct from the fresh context if anything is off.

## When NOT to use this skill

- The user wants a durable design doc, exploration note, or vision artifact → use `/noodle-on` or `/feature-spec`.
- The user wants to capture a stray idea for later → use your project's quick-capture mechanism.
- The work is done and the user is ready to commit → just commit; no handoff needed.
- The fresh context will be for an unrelated task → no handoff needed, just `/clear`.

## Example

User invokes `/handoff notification-digest` after a long session designing a daily-digest notification feature.

Skill writes `/tmp/handoff-notification-digest.md`:

```markdown
# Handoff: Notification digest — delivery scheduler scaffold

_Written: 2026-03-04 23:14 from feature/issue-300 (worktree)_

## Task
Implementing the daily notification digest (#300). Building the scheduler that batches a user's unread notifications into one digest, then wiring three pieces (batch query, template render, send adapter).

## Where I am
- Last done: Confirmed scheduler design with user; rejected per-notification sends in favor of a single Batch(userId, window) -> Digest pass per run.
- Next step: Scaffold `services/notifications/DigestScheduler.ts` with the Batch signature and a stub Digest type.
- Blocker: none

## Load-bearing memory
Fetch with `get_observations([...])` as needed.

- `2807` — digest design vision (batch-per-window, opt-out handling)
- `2809` — MVP spec (scoped implementation, reusable render)
- `2810` — Issue #300 MVP scope update

## Open loops (not written down yet)
- User picked "one digest per day" over "configurable cadence" — confirmed in conversation but not yet reflected in #300 body.
- Render will reuse the existing email-template engine (decided ~20 min ago); not yet noted in the design doc.

## Verify before acting
- `services/notifications/` — confirm the DigestScheduler file does not yet exist (this is the first file).
- `gh issue view 300` — confirm body still reflects MVP scope from observation 2810.
- `handoffs/design-300.md` — confirm absent (no architect handoff yet; lead-dev will direct-implement).

## Resume incantation
```
Read /tmp/handoff-notification-digest.md and continue from "Next step".
```
```

And prints:

```
Handoff written: /tmp/handoff-notification-digest.md
After /clear, paste: Read /tmp/handoff-notification-digest.md and continue from "Next step".
```
