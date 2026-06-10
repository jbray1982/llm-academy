---
name: review
description: Pre-landing review of a branch's diff against base. Runs a primary pass through the reviewer subagent, an optional adversarial cross-model pass, synthesizes findings, auto-fixes trivial nits, batch-asks the user about substantive ones, and writes `handoffs/review-{issue}.md` with a verdict the pipeline consumes.
user-invocable: true
requires-agents: [reviewer]
---

# Review Skill

> **Repo-specific guidance.** If `.llm-academy/review.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

Pre-landing review for [your project]. Designed to be called by `/feature-flow` (Step 4) and also invokable directly (`/review`) on any branch.

The skill does NOT commit, push, or open PRs — that is the pipeline's commit step's job. The skill produces a verdict + findings; the caller acts on them.

## Usage

```
/review                # base branch defaults to origin/<default-branch>
/review <base-branch>  # explicit base (e.g. /review origin/feature/foo)
```

## Pipeline

```
detect diff → read handoffs → primary pass (reviewer agent)
            → adversarial pass (optional; skip if not configured) → synthesize
            → fix-first (auto-fix trivial, batch-ask substantive)
            → write handoffs/review-{issue}.md → return verdict
```

## Verdict contract

The skill's final output (and `handoffs/review-{issue}.md`'s "Status" line) MUST resolve to exactly one of:

- `approved` — no remaining issues; safe to land
- `non_blocking_issues` — issues found but caller can proceed; each finding is captured in the findings list with severity / file / fix
- `blocking_issues` — issues found that the implementer must address before landing

`/feature-flow` Step 4 branches on this verdict. Do not invent new verdict labels.

---

## Step 0: Detect base, diff, and execution mode

```bash
BASE="${1:-origin/main}"   # set to your repo's default branch
git fetch origin --quiet 2>/dev/null || true
DIFF_INS=$(git diff "$BASE" --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
DIFF_DEL=$(git diff "$BASE" --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
DIFF_TOTAL=$((DIFF_INS + DIFF_DEL))
HEADLESS=0
[ -n "$CLAUDE_HEADLESS" ] && HEADLESS=1
[ -n "$CI" ] && HEADLESS=1
[ -n "$BATCH_PROCESSOR" ] && HEADLESS=1
# Detect issue number from branch name (e.g. feature/issue-42 → 42).
# Falls back to "unknown" when the branch doesn't follow the convention.
ISSUE=$(git branch --show-current 2>/dev/null | grep -oE '[0-9]+$' || echo "unknown")
REVIEW_FILE="handoffs/review-${ISSUE}.md"
echo "BASE=$BASE  DIFF_TOTAL=$DIFF_TOTAL  HEADLESS=$HEADLESS  REVIEW_FILE=$REVIEW_FILE"
```

**Headless detection rules** (be defensive — these signals stack):

1. `CLAUDE_HEADLESS`, `CI`, or `BATCH_PROCESSOR` env vars set → headless.
2. `AskUserQuestion` is not in your available tool list → headless (the harness has restricted you).
3. The user explicitly passed `--headless` as an argument to `/review` → headless.

If any of the above is true, treat HEADLESS=1 for the rest of the skill. **In headless mode you MUST NOT call AskUserQuestion** — it will silently fail and the skill will hang or proceed with wrong state.

**No-diff shortcut**: if `git diff --quiet "$BASE"` returns 0, the branch has no changes against base. Write a minimal `handoffs/review-{issue}.md` (Status: approved, "no changes detected") and stop. Do not run the reviewer or adversarial pass.

Print a one-line summary: `Reviewing <N> lines against <base>.`

---

## Step 1: Read handoff context (optional)

If a design handoff (`handoffs/design-{issue}.md`) or manifest handoff (`handoffs/manifest-{issue}.md`) exists, the skill is being invoked inside `/feature-flow` after architect + implementation. Pass those paths to the reviewer agent so it can check design compliance + manifest completeness.

If neither file exists, the skill is being run ad-hoc. The reviewer agent reviews against project conventions only (no design/manifest cross-check). This is fine — the workflow degrades gracefully.

---

## Step 2: Primary review pass (reviewer subagent, foreground)

Spawn the `reviewer` agent via the Agent tool. The reviewer is the source of truth for your project-specific check categories — keep those rules in the agent definition, not duplicated here. **The skill orchestrates; the agent embodies the conventions.**

The agent's prompt must include:

1. The base branch name (so it runs `git diff <base>` correctly)
2. Whether the design and manifest handoffs are present
3. Instruction to write its findings to `handoffs/review-{issue}.md` in the standard format (see Step 6 below)
4. Instruction to return a final-line verdict in the format `VERDICT: <approved|non_blocking_issues|blocking_issues>` followed by a JSON findings array on the next line

**Run foreground** (no `run_in_background`). The skill must have the reviewer's output before proceeding to synthesis.

**Failure handling**:
- *Interactive*: if the reviewer agent fails or returns no parseable verdict, surface the failure to the user via AskUserQuestion (retry / abort / treat as blocking). Do not silently approve.
- *Headless*: same failure → write a minimal `handoffs/review-{issue}.md` with `Status: blocking_issues` and a finding `reviewer agent failed` (include stderr/last-message excerpt). Return `VERDICT: blocking_issues`. Never silently approve in headless.

---

## Step 3: Adversarial pass (cross-model second opinion, optional)

A second, independent model reviewing the same diff catches determinism bugs, edge cases, and platform-specific failures the primary pass misses. This step is **optional and tool-agnostic** — wire it up if your project has a secondary-model CLI; skip it cleanly if not.

**Interface contract.** Configure a single script wrapper (reference path: `tools/adversarial-review-pass.sh`) that takes the base branch as `$1`, runs your secondary model against `git diff <base>`, prints findings to stdout, and exits with:

- **exit 3** — the secondary model CLI is not installed/available. Skip Step 3 entirely, print the script's message, continue to Step 4.
- **exit 0** — it ran; findings are on stdout. Proceed to synthesis.
- **any other exit** — it ran but errored (auth/timeout/etc.). Non-blocking (the adversarial pass is additive): inspect the error and skip to Step 4 (e.g. auth failure → print "secondary model not authenticated — continuing without adversarial pass").

Wrapping both the availability probe and the run in one script means the whole pass fires a **single** permission prompt — grant `Bash(bash tools/adversarial-review-pass.sh *)` once. Keep the adversarial prompt inside the script (single source of truth).

```bash
bash tools/adversarial-review-pass.sh "$BASE"
```

Set the Bash tool's `timeout` parameter to `300000` (5 min). Note: macOS has no `timeout` binary, so the Bash-tool timeout is the only bound — don't rely on shell `timeout`.

If no adversarial tool is configured, skip this step silently and collapse the synthesis (Step 4) to the primary pass only. The adversarial pass is always additive — **its absence never blocks landing.**

---

## Step 4: Cross-model synthesis

Present both reviews to the user under a single header:

```
═══════════════════════════════════════════════════════════
REVIEW SYNTHESIS (N lines against <base>)
═══════════════════════════════════════════════════════════
  Primary (reviewer agent):
    <N findings, listed by severity>

  Adversarial (secondary model):
    <M findings, listed by severity>
    Recommendation: <secondary model's recommendation line>

  Overlap (both flagged): <K findings, one-line each>
  Unique to reviewer:     <P findings>
  Unique to adversarial:  <Q findings>
═══════════════════════════════════════════════════════════
```

If the adversarial pass was skipped, the synthesis collapses to just the primary findings — say so explicitly: `Adversarial pass skipped (<reason>).`

Overlap is computed by file + approximate line range + category. Don't over-engineer the matching — a coarse heuristic is fine. Tag overlapped findings with `[BOTH]` in the synthesis output; they get priority in the next step.

---

## Step 5: Fix-First

Classify each unique finding (overlap counts as one) as **AUTO-FIX** or **ASK**:

- **AUTO-FIX**: mechanical changes the user would obviously approve. Missing import/using-statement, dead code, typo in a string literal, unused private field, formatting drift, a missing serialization/registry entry for a new type the diff added.
- **ASK**: anything that involves judgment, changes behavior, touches multiple files in a non-mechanical way, requires understanding intent, or is flagged CRITICAL.

When in doubt: ASK.

### Step 5a: Apply AUTO-FIX items

Apply each AUTO-FIX inline using Edit. After each, print one line: `[AUTO-FIXED] <file>:<line> — <what changed>`.

Skip Step 5a entirely if there are zero AUTO-FIX items.

### Step 5b: Resolve ASK items

If there are zero ASK items after auto-fix, skip Step 5b — go straight to Step 6.

**Interactive mode (HEADLESS=0):**
- If 1–4 ASK items: present them in a single AskUserQuestion. For each ASK item, options are A) Fix as recommended, B) Skip (defer / treat as non-blocking finding).
- If 5+ ASK items: split into batches of 4 and ask sequentially. Lead each batch with the highest-severity items first.
- Each option must include enough context for the user to decide without re-reading the diff: file + line + one-sentence problem + one-sentence proposed fix.

**Headless mode (HEADLESS=1):**
- Do NOT call AskUserQuestion. Treat every ASK item as deferred — record it in `handoffs/review-{issue}.md` with `Status: deferred-headless` and do not apply the fix.
- Verdict resolution still works: any CRITICAL ASK item still surfaces as `blocking_issues`, non-critical ASK items become `non_blocking_issues`. The caller (batch processor, automation) gets a clear signal in the verdict + findings JSON and can act on it however it wants.
- Print one line summarizing what was deferred: `Headless mode: deferred N ASK items (X critical, Y informational).`

### Step 5c: Apply user-approved fixes

(Interactive mode only — no-op in headless.)

For each ASK item the user chose to fix, apply the fix using Edit. Skipped items remain in the findings list (they don't disappear) and contribute to the verdict — if any skipped item is CRITICAL, the verdict is `blocking_issues`.

---

## Step 6: Write `handoffs/review-{issue}.md`

Use `$REVIEW_FILE` (set in Step 0) as the path — e.g. `handoffs/review-42.md`. Latest-wins per issue: overwrite any prior review for this issue number. Git history preserves earlier rounds. Format:

```markdown
# Review: <branch or issue ref>

## Status: <approved | non_blocking_issues | blocking_issues>

<one-paragraph summary: total findings, what was auto-fixed, what was asked,
what was skipped, build/test status>

---

## Findings

### Critical (blocking)
- **<file>:<line>** — <description and recommended fix>
  Status: <fixed | skipped | needs-followup>

### Non-Blocking
- **<file>:<line>** — <description>
  Status: <fixed | skipped | needs-followup>

---

## Auto-Fixed
- <file>:<line> — <what changed>

---

## Adversarial Pass

<verbatim secondary-model output, or "Skipped (<reason>)" if unavailable>

---

## Manifest Checklist

(only if a manifest handoff was present)
- [x] <item> — confirmed
- [ ] <item> — <what's missing>
```

### Verdict resolution

- If any finding's `Status: skipped` is CRITICAL → `blocking_issues`
- Else if any findings remain (skipped non-critical, or unfixable) → `non_blocking_issues`
- Else → `approved`

Print the verdict to the user as the final line of the skill output:

```
VERDICT: <approved|non_blocking_issues|blocking_issues>
```

`/feature-flow` Step 4 reads this line and branches.

---

## Notes

- **No commits, no pushes, no PRs.** The skill never modifies git history. Auto-fixes touch the working tree; commits happen later (in `/feature-flow` Step 6 or by the user manually).
- **Foreground only when interactive.** In interactive mode the skill blocks the conversation for the duration of the review (~1–5 min when the adversarial pass runs) — necessary for AskUserQuestion-based fix-first.
- **Headless-safe.** When `CLAUDE_HEADLESS` / `CI` / `BATCH_PROCESSOR` is set, AskUserQuestion is unavailable, or `--headless` is passed: the skill never prompts. AUTO-FIX items are still applied (they need no user input by definition); ASK items are deferred and surfaced through the verdict + findings JSON. The reviewer subagent and adversarial shell-out both work the same way in either mode.
- **Run the adversarial pass even on small diffs when it's configured.** A 5-line change to determinism or serialization is exactly the kind of thing one model misses; the only gate is "is the secondary model available."
- **Reviewer agent owns project-specific check categories.** This skill orchestrates; the agent embodies the conventions. Keep the conventions in one place to avoid drift.
- **Backlog cross-reference**: if the diff appears to address an open item in the project's backlog file (heuristic match on file paths or symbol names), include a `Possibly closes: <title>` line in the review summary. Non-blocking; surface only.

## Calling from `claude -p` (headless)

If you wire this skill into a batch script or CI job:

```bash
CLAUDE_HEADLESS=1 claude -p "/review origin/main" \
  --output-format json \
  --allowedTools "Read,Write,Edit,Bash,Agent"
```

The skill returns its findings via the final `handoffs/review-{issue}.md` file and the `VERDICT:` line in stdout. Parse the verdict to branch your script. AskUserQuestion does not need to be in `--allowedTools` — the skill detects its absence and routes to the deferred-finding path.
