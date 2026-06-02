---
name: ba-triage
description: BA triage on a single GitHub issue — assess readiness, recommend fast-track vs. architect, and record the result on the issue
user-invocable: true
---

# BA Triage Skill

When the user invokes `/ba-triage <issue-number>`, run the BA readiness/approach triage from the issue implementation pipeline on a single issue. This is the readiness portion of `/feature-flow`'s Step 1, broken out so it can be run on its own (for backlog grooming, batch prep, or to pre-stage an issue before later running `/feature-flow` on it).

**Scope note:** This skill produces the readiness decision (ready vs. deferred) and the recommended approach (fast-track type or needs-architect). It does **not** perform `/feature-flow`'s project backlog scope-bundling sweep — that sweep is always run fresh inside `/feature-flow` because the backlog is mutable. When `/feature-flow` reuses a triage result produced by this skill, it re-does the backlog sweep at that time.

## Usage

```
/ba-triage 42
```

If no issue number is provided, ask the user which issue to triage.

## What This Skill Does

1. Fetches the issue.
2. Short-circuits on special labels (see Label Handling).
3. Otherwise launches a **ba** background agent that determines:
   - **Is the issue ready?** Defer if blocked, needs-design, duplicate, out-of-scope, insufficient detail.
   - **If ready, can it skip the architect?** Recommend one of:
     - `scaffold` — has architectural plan, lead-dev scaffolds, junior-dev implements
     - `lead-dev` — clear implementation steps, complex, lead-dev implements
     - `junior` — simple and fully specified, junior-dev implements
     - `needs-architect` — needs architect review (default if unsure)
4. Applies the appropriate defer label (when deferring) and leaves a triage comment on the issue with a machine-readable footer that other skills can read back.
5. Reports the outcome to the user.

The BA agent prompt context must include:
- The full issue body and comments
- The issue's current labels
- A summary of the open backlog (for dependency awareness)

## Label Handling (short-circuits)

Check labels before launching the BA agent:

| Label | Action |
|-------|--------|
| `product-decision-review` | Defer silently — requires human review |
| `planning` | Defer silently — feature request not yet decided |
| `follow-up-issue` | Result is `ready, approach=lead-dev` (skip architect) — record and return |
| `blocked` | Verify blockers; if still unresolved, defer |
| `decision-required` | Defer — needs human product/design input |

When short-circuiting, still write the triage comment so downstream skills can detect the result without re-running the agent.

### Customization

Add or remove labels to match your project's workflow. Common additions:
- `needs-design` — requires design doc or RFC first
- `duplicate` — already tracked elsewhere
- `wontfix` / `out-of-scope` — not aligned with current goals
- `tracking` / `meta` — an umbrella, epic, or meta issue with no actionable implementation work of its own

## Triage Comment Format

Leave one comment on the issue. The body MUST end with a machine-readable footer on its own line so `/feature-flow` and other tooling can parse it back:

**Ready example:**

```
✅ Triage: Ready — approach `lead-dev`

[1–3 sentence reasoning from the BA]

<!-- triage-result: ready=true approach=lead-dev defer_label= -->
_Tagged by `/ba-triage`._
```

**Deferred example:**

```
⏸️ Triage: Deferred — `blocked`

[Reasoning: list blocking issues or reason]

<!-- triage-result: ready=false approach= defer_label=blocked -->
_Tagged by `/ba-triage`._
```

Footer keys:
- `ready` — `true` or `false`
- `approach` — one of `scaffold`, `lead-dev`, `junior`, `needs-architect`, or empty when deferred
- `defer_label` — the label that explains the deferral, or empty when ready. This is an **open enumeration** — the values below are a starting set, not a closed list. Add your project's own defer reasons (see Customization) and use whichever label you applied: `blocked`, `needs-design`, `duplicate`, `out-of-scope`, `needs-detail`, `tracking`, …

If a triage comment already exists on the issue, write a new one (don't try to edit the old). The newest comment wins.

Use `/tmp/ba-triage-comment.md` for the comment body and `gh issue comment <num> --body-file /tmp/ba-triage-comment.md`.

## Defer-Label Application

If deferring with a defer_label, also apply that label:

```
gh issue edit <num> --add-label <defer_label>
```

When the label is one of the short-circuit labels (`planning`, `product-decision-review`, `decision-required`), it's already on the issue — don't re-add.

## Reporting to the User

After the agent completes (or after a short-circuit), summarize:

- **Ready:** `Issue #N is ready. Recommended approach: <approach>. Reasoning: <one line>.`
- **Deferred:** `Issue #N deferred (<defer_label>). Reasoning: <one line>. A triage comment was added and the label applied.`

Do not prompt for next steps — this skill is a one-shot. If the user wants to implement, they can invoke `/feature-flow <number>`, which will detect this triage result and skip its own BA step.

## Notes

- This is the same triage logic used by the first step of `/feature-flow` and any batch processing pipeline you have configured.
- Re-running this skill on an issue is safe — it just leaves a fresh triage comment. The newest comment is authoritative.
