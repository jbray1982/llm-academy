---
name: feature-log
description: Query and navigate FEATURE_LOG.md — the registry of every named concept in the project's design surface
user-invocable: true
---

# /feature-log skill

> **Repo-specific guidance.** If `.llm-academy/feature-log.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

Query and navigate `FEATURE_LOG.md` — the registry of every named concept in the project's design surface.

## What FEATURE_LOG is

A flat markdown file at the repo root. Every named feature, mechanic, or cross-cutting system that has surfaced in design conversations lives here at some stage of maturity. It is maintained automatically by other skills (`/feature-spec`, `/noodle-on`, `/feature-flow`, and any project-specific issue-management skill) — you should not need to edit it manually.

It is NOT:
- A priority list (that's the project backlog file — `TODOS.md` / `BACKLOG.md`)
- An implementation backlog (that's GitHub issues)
- Design exploration (that's `noodles/`)
- Committed specs (that's `docs/<feature>/`)

It IS the answer to "what named concepts exist and where do they stand?"

## Entry format

```
- **[conviction | status]** **Feature Name** — one-line description.
  Blocks: Feature A, Feature B
  Surfaced: <session>, <date>. See: <links>.
```

With blocked modifier:
```
- **[conviction | status | blocked: Dependency]** **Feature Name** — description.
```

Terminal entries:
```
- **[dropped]** **Feature Name** — description. Dropped: reason.
- **[superseded → Replacement]** **Feature Name** — description.
```

## Status vocabulary

| Status | Meaning |
|--------|---------|
| `concept` | Mentioned, nothing fleshed out |
| `unknown` | Referenced in docs somewhere — needs archaeology |
| `code-present` | Code exists, no vision doc |
| `defined` | Vision doc exists, no code |
| `partially-live` | MVP code exists, more planned |
| `live` | Code matches vision |
| `dropped` | Decided not to build |
| `superseded → X` | Absorbed into another feature |

`blocked: <name>` is an orthogonal modifier on any status above.

## Conviction vocabulary

| Conviction | Meaning |
|-----------|---------|
| `must-have` | Definitional to the product; when-not-if |
| `probably-need` | Cross-cutting; may get absorbed into something larger |
| `cool-if` | Optional; adds texture, not load-bearing |

## When this skill is invoked

Run this skill when the user asks any of:
- "What's in FEATURE_LOG?" / "What features do we have logged?"
- "Is [feature name] in FEATURE_LOG?" / "What's the status of [feature]?"
- "What's blocking [feature]?" / "What does [feature] block?"
- "What are all the must-have features that aren't defined yet?"
- "What's lingering / what's unresolved?"
- "Show me everything at [status]"
- Any question whose answer lives in the feature registry rather than in code or GitHub

## How to respond

1. **Read `FEATURE_LOG.md`** in full before answering. It is the source of truth — do not answer from memory.

2. **For a named feature lookup**: find the entry, report conviction, status, blocking relationships, and `See:` links. If not found, say so and offer to add it.

3. **For a filtered view** (e.g. "all must-have that are just concepts"): scan all entries, return a formatted table. Example:

   | Feature | Conviction | Status | Blocks |
   |---------|-----------|--------|--------|
   | Notification System | must-have | concept | User Preferences, Email Digest |

4. **For blocking queries** ("what does X block?" or "what's blocking X?"): scan `Blocks:` fields. Report both directions — what X blocks and what blocks X (via `blocked:` modifier on X's own entry).

5. **For a general overview**: group entries by status, show counts per conviction level, call out anything `blocked` or `unknown`. Format as a compact dashboard:

   ```
   live (2): Auth, Session Management
   partially-live (1): Search
   defined (3): FEATURE_LOG, Notifications, Audit Log
   concept (8): User Preferences, Email Digest, ...
   unknown (1): Legacy Importer
   dropped/superseded (0)
   ```

6. **Offer to update**: if the user provides new information during the conversation ("oh, we specced that last week"), offer to update the entry on the spot.

## When to suggest adding an entry

If a named concept comes up in conversation that isn't in FEATURE_LOG, mention it at the end of your response: "I didn't find [name] in FEATURE_LOG — want me to add it?" Confirm conviction before writing.

## Bootstrapping a project

If `FEATURE_LOG.md` does not yet exist, this skill can create it. On first invocation against a project with no log, ask the user whether to scaffold it. If yes, create the file at the repo root with a brief header and an empty list — entries will accumulate over time as other skills run. Do not try to back-fill the entire codebase in one pass; the registry grows organically as features surface.
