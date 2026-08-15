---
name: review
description: Pre-landing review of a branch's diff against base. Runs a primary pass through the reviewer subagent (hub-and-spoke on large diffs — per-file spokes plus an integration coordinator), an optional adversarial cross-model pass, synthesizes findings, auto-fixes trivial nits, batch-asks the user about substantive ones, and writes `handoffs/review-{issue}-{round}.md` with a verdict the pipeline consumes.
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
detect diff → read handoffs → primary pass (single reviewer agent, or
                                hub-and-spoke: per-file spokes → coordinator hub)
            → adversarial pass (probe for a secondary CLI; skip if none) → synthesize
            → fix-first (auto-fix trivial, batch-ask substantive)
            → write handoffs/review-{issue}-{round}.md → return verdict
```

## Verdict contract

The skill's final output (and the review file's "Status" line) MUST resolve to exactly one of:

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
# Round number: one file per review pass, so re-reviews never clobber earlier rounds.
mkdir -p handoffs
LAST=$(ls handoffs/review-${ISSUE}-[0-9][0-9].md 2>/dev/null \
  | sed -E 's/.*-([0-9]{2})\.md$/\1/' | sort -n | tail -1)
# A legacy unnumbered handoffs/review-{issue}.md counts as round 01.
[ -z "$LAST" ] && { [ -f "handoffs/review-${ISSUE}.md" ] && LAST=01 || LAST=00; }
ROUND=$(printf '%02d' $((10#$LAST + 1)))   # 10# — else 08/09 parse as octal
REVIEW_FILE="handoffs/review-${ISSUE}-${ROUND}.md"
PREV_REVIEW=$(ls handoffs/review-${ISSUE}-[0-9][0-9].md 2>/dev/null | sort | tail -1)
echo "BASE=$BASE  DIFF_TOTAL=$DIFF_TOTAL  HEADLESS=$HEADLESS  REVIEW_FILE=$REVIEW_FILE"
```

`$REVIEW_FILE` is **always a new file** — never overwrite a prior round. `$PREV_REVIEW` (empty on the first round) is the most recent earlier round, useful as context in Step 1.

**Reading a review elsewhere**: the current review for an issue is the highest-numbered `handoffs/review-{issue}-*.md`. Downstream consumers (`/feature-flow`, the `ba` and `documentarian` agents) resolve it that way, falling back to a legacy unnumbered `handoffs/review-{issue}.md`.

**Headless detection rules** (be defensive — these signals stack):

1. `CLAUDE_HEADLESS`, `CI`, or `BATCH_PROCESSOR` env vars set → headless.
2. `AskUserQuestion` is not in your available tool list → headless (the harness has restricted you).
3. The user explicitly passed `--headless` as an argument to `/review` → headless.

If any of the above is true, treat HEADLESS=1 for the rest of the skill. **In headless mode you MUST NOT call AskUserQuestion** — it will silently fail and the skill will hang or proceed with wrong state.

**No-diff shortcut**: if `git diff --quiet "$BASE"` returns 0, the branch has no changes against base. Write a minimal `$REVIEW_FILE` (Status: approved, "no changes detected") and stop. Do not run the reviewer or adversarial pass.

Print a one-line summary: `Reviewing <N> lines against <base>.`

---

## Step 1: Read handoff context (optional)

If a design handoff (`handoffs/design-{issue}.md`) or manifest handoff (`handoffs/manifest-{issue}.md`) exists, the skill is being invoked inside `/feature-flow` after architect + implementation. Pass those paths to the reviewer agent(s) — on the hub-and-spoke path, both spokes and the coordinator get them — so review checks design compliance + manifest completeness.

If neither file exists, the skill is being run ad-hoc. Review against project conventions only (no design/manifest cross-check). This is fine — the workflow degrades gracefully.

If `$PREV_REVIEW` is non-empty, this is a **re-review**: an earlier round already ran on this issue. Pass that path to the reviewer agent(s) too (spokes and/or coordinator, per Step 2), so review can check whether the previous round's findings were actually addressed rather than rediscovering them from scratch.

---

## Step 2: Primary review pass (hub-and-spoke, reviewer subagents)

Large changesets suffer from lost-in-the-middle: a single agent holding the whole diff in context tends to under-review files in the middle of the review and under-weight cross-file consistency. To counter this, the primary pass fans out one reviewer agent per file (or per small file group) for close reading, then runs a dedicated coordinator pass over the whole diff for integration issues. Small diffs skip the fan-out entirely — it's not worth the overhead.

The reviewer agent (and its per-file/coordinator variants below) is the source of truth for your project-specific check categories — keep those rules in the agent definition, not duplicated here. **The skill orchestrates; the agent embodies the conventions.**

### Step 2a: Decide fan-out vs. single-pass

Using `$DIFF_TOTAL` (lines changed) and the changed-file count from Step 0:

```bash
CHANGED_FILES=$(git diff "$BASE" --name-only 2>/dev/null)
FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c .)
```

- **File count ≤ 3 AND `$DIFF_TOTAL` < 150** → single-pass (below). One reviewer agent sees the whole diff, same as before.
- **Otherwise** → hub-and-spoke (Step 2b–2c).

### Step 2b (single-pass path): whole-diff reviewer

Spawn one `reviewer` agent via the Agent tool with the whole diff. The agent's prompt must include:

1. The base branch name (so it runs `git diff <base>` correctly)
2. Whether the design and manifest handoffs are present
3. The resolved `$REVIEW_FILE` path, with the instruction to write its findings there in the standard format (see Step 6 below). Pass the path explicitly — the agent must not guess it, or it will clobber an earlier round.
4. Instruction to return a final-line verdict in the format `VERDICT: <approved|non_blocking_issues|blocking_issues>` followed by a JSON findings array on the next line

Skip Step 2c (there's no per-file/coordinator split); treat this agent's output as the complete primary pass and proceed to Step 3.

### Step 2c (hub-and-spoke path): per-file spokes + coordinator hub

**Spokes — one reviewer agent per file, grouped and capped:**

- If `$FILE_COUNT` ≤ 12: one `reviewer` agent per changed file.
- If `$FILE_COUNT` > 12: group files (by directory, or evenly) into at most 12 agent calls, each reviewing its group's files together. Never spawn more than 12 spoke agents regardless of file count — bound the fan-out on very large changesets.

Launch all spoke agents **in parallel, in a single message with multiple Agent tool calls** (they're independent). Each spoke agent's prompt must include:

1. The base branch name and the specific file(s) it owns (`git diff <base> -- <file>`), so it reviews only its slice
2. Whether design/manifest handoffs are present (pass the paths; the spoke may need surrounding context even though its slice is narrow)
3. The **full list of changed files** in this diff (names only, from `$CHANGED_FILES`) — so the spoke agent can flag "this touches an interface/contract that another changed file likely depends on" even without reading that file itself, rather than silently assuming its file is reviewed in isolation
4. Instruction to return findings for its file(s) only, in the standard finding format (file, line, severity, description, fix), plus a short list of **integration concerns** — things it suspects need checking against other changed files (e.g. "this renames a public function; verify all call sites were updated") — labeled separately so the coordinator can act on them
5. No `$REVIEW_FILE` write — spokes report back to the skill; only the skill writes `$REVIEW_FILE` (Step 6)

**Hub — one coordinator agent, after all spokes return:**

Spawn a single `reviewer` agent as coordinator, run foreground, with:

1. The full diff against `$BASE` (whole-diff context, not a slice)
2. Every spoke agent's findings and integration-concern notes, concatenated
3. Explicit instruction to focus on what per-file review structurally can't catch: interface/contract mismatches between changed files, call sites not updated for a signature change, duplicated logic introduced across files, inconsistent naming/patterns across the changeset, and whether the integration-concern notes from spokes actually check out
4. Instruction to *not* re-relitigate findings the spokes already made correctly — only add new integration findings or flag a spoke finding as a false positive
5. The resolved `$REVIEW_FILE` path and instruction to write the merged result (its own integration findings plus a rollup of spoke findings) there in the standard format (Step 6), and to return the final-line verdict format `VERDICT: <approved|non_blocking_issues|blocking_issues>` followed by a JSON findings array

Treat the coordinator's output as the complete primary pass for Step 3 onward — the spokes' raw output doesn't need separate handling once the coordinator has rolled it up.

**Run foreground** (no `run_in_background`) for the coordinator step — the skill must have its output before proceeding to synthesis. Spokes may run as parallel Agent calls but the skill still waits for all of them before invoking the coordinator (the coordinator needs every spoke's findings).

**Failure handling**:
- *A spoke agent fails*: don't abort the whole pass. Note the failed file(s) explicitly to the coordinator ("no automated review ran for `<file>`") so it's visible in the final findings and review file rather than silently skipped.
- *Interactive*: if the coordinator (or, on the single-pass path, the sole reviewer agent) fails or returns no parseable verdict, surface the failure to the user via AskUserQuestion (retry / abort / treat as blocking). Do not silently approve.
- *Headless*: same failure → write a minimal `$REVIEW_FILE` with `Status: blocking_issues` and a finding `reviewer agent failed` (include stderr/last-message excerpt). Return `VERDICT: blocking_issues`. Never silently approve in headless.

---

## Step 3: Adversarial pass (cross-model second opinion, optional)

A second, independent model reviewing the same diff catches determinism bugs, edge cases, and platform-specific failures the primary pass misses. **This needs no setup** — if a secondary-model CLI is on `PATH`, the pass runs. Availability is always **probed at run time**, never assumed from a prior session's notes (see the stale-hint warning at the end of this step).

### Probe

(If the project has adopted a pinned wrapper — see the last subsection — run that first and fall through to this probe only if it fails.)

Check `command -v <candidate>` for each candidate CLI in turn. Default candidate list — deliberately generic, since these skills ship to any consuming project: `codex`, `gemini`. `.llm-academy/review.md` may extend or override it (add vendors, reorder preference, restrict to one).

Take the first candidate that resolves. But `command -v` only proves the *name* resolves — not that the CLI is authenticated or usable — so if the chosen one errors on invocation, move to the next candidate before concluding that nothing is reachable.

### The adversarial prompt

The skill carries the prompt. This is the single source of truth for it — don't restate it elsewhere:

> The complete diff of this branch against `<base>` follows on stdin. Review it adversarially. Focus on what a first-pass reviewer plausibly missed: edge cases, determinism, platform-specific failure modes, and error paths. For each finding, give the file, the line or range, a one-sentence problem statement, and a one-sentence recommended fix. End with a one-line overall recommendation (approve / non-blocking issues / blocking issues).

Substitute the resolved base for `<base>`, and say explicitly how the diff reaches the model — it arrives as an unlabeled payload and won't otherwise know what it's looking at or what it's diffed against. Keep the prompt model-agnostic: no vendor-specific flags in the prompt text itself; flags belong in the invocation.

### Invoke

Exact flags vary per CLI — check `<cli> --help` if you're not sure rather than guessing. Generic shape (diff piped via stdin, the prompt above passed as an argument):

```bash
git diff "$BASE" | codex exec "<the prompt above, with $BASE substituted>"
```

Substitute whichever CLI was found reachable for `codex exec`, and adjust how the diff reaches it (stdin vs. an argument vs. a temp file) to match that CLI's own interface.

Set the Bash tool's `timeout` parameter to `300000` (5 min). macOS has no `timeout` binary, so the Bash-tool timeout is the only bound — don't rely on shell `timeout`.

Grant `Bash(codex exec:*)` (or your CLI's equivalent) once in settings and the pass stops prompting.

### Outcomes

Exactly three, reported per Step 4:

- **Ran** — findings are on stdout; proceed to synthesis.
- **Attempted but failed** — a model was reachable but every candidate errored (auth, timeout, bad invocation). Non-blocking: the adversarial pass is additive. Report the reason and continue to Step 4.
- **Skipped** — no candidate is on `PATH` at all. Skip silently and collapse the synthesis to the primary pass. **Absence never blocks landing.**

### Optional: a pinned wrapper

Nothing above requires a script. But a project that needs a *specific* invocation — a pinned model, a proxy or self-hosted endpoint, credentials the bare CLI won't pick up — can put one at `tools/adversarial-review-pass.sh` (or any path named in `.llm-academy/review.md`) and this step will prefer it over the probe:

```bash
bash tools/adversarial-review-pass.sh "$BASE"
```

It takes the base branch as `$1` and prints findings to stdout. **If it fails for any reason — nonzero exit, no output, missing CLI — fall through to the probe above.** The wrapper is an override, not a gate: one project's pinned vendor being unavailable must never suppress a second opinion that's reachable another way. That failure is worth one line in the synthesis, since a wrapper someone deliberately configured is now not working.

No wrapper or template ships with this skill — the path above is a convention a consuming repo may adopt, not something it receives. Most projects don't need it; the probe covers them.

### Stale-hint warning

`.llm-academy/review.md` may legitimately *configure* things — a wrapper path, a candidate-list override. Trust that part; it's durable. But any statement there about whether a tool **is currently installed or reachable** is a point-in-time probe result, not standing configuration — environments change between sessions, and a CLI can be installed (or go missing) minutes after the overlay was written. Re-probe at run time regardless of what the overlay claims.

---

## Step 4: Cross-model synthesis

Present both reviews to the user under a single header:

```
═══════════════════════════════════════════════════════════
REVIEW SYNTHESIS (N lines against <base>)
═══════════════════════════════════════════════════════════
  Primary (reviewer — single pass, or hub-and-spoke coordinator rollup):
    <N findings, listed by severity>

  Adversarial (secondary model):
    <M findings, listed by severity>
    Recommendation: <secondary model's recommendation line>

  Overlap (both flagged): <K findings, one-line each>
  Unique to reviewer:     <P findings>
  Unique to adversarial:  <Q findings>
═══════════════════════════════════════════════════════════
```

Report Step 3's outcome as exactly one of these three lines. They are distinct, and collapsing them is what hid a broken second opinion for weeks:

- **Ran** — `Adversarial pass ran (<cli>).` Findings are in the synthesis above. If a pinned wrapper was used, name it instead of the CLI.
- **Attempted but failed** — a model was reachable but every attempt errored (auth, timeout, bad invocation): `Adversarial pass attempted but failed (<reason>).` The synthesis collapses to the primary findings, but say plainly that a second opinion was available and didn't land — that's a fixable environment problem, not an absent capability. If a configured wrapper was the thing that failed, say so; someone set it up deliberately and will want to know.
- **Skipped** — no secondary model reachable at all: `Adversarial pass skipped (no secondary model available).`

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
- Do NOT call AskUserQuestion. Treat every ASK item as deferred — record it in `$REVIEW_FILE` with `Status: deferred-headless` and do not apply the fix.
- Verdict resolution still works: any CRITICAL ASK item still surfaces as `blocking_issues`, non-critical ASK items become `non_blocking_issues`. The caller (batch processor, automation) gets a clear signal in the verdict + findings JSON and can act on it however it wants.
- Print one line summarizing what was deferred: `Headless mode: deferred N ASK items (X critical, Y informational).`

### Step 5c: Apply user-approved fixes

(Interactive mode only — no-op in headless.)

For each ASK item the user chose to fix, apply the fix using Edit. Skipped items remain in the findings list (they don't disappear) and contribute to the verdict — if any skipped item is CRITICAL, the verdict is `blocking_issues`.

---

## Step 6: Write `handoffs/review-{issue}-{round}.md`

Use `$REVIEW_FILE` (set in Step 0) as the path — e.g. `handoffs/review-42-01.md`, then `review-42-02.md` on the next pass. **Never overwrite an earlier round**: each review pass gets its own file, so a re-review after fixes leaves the prior round's findings readable on disk rather than only in git history. Format:

```markdown
# Review: <branch or issue ref> (round <NN>)

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

<verbatim secondary-model output, naming the CLI (or pinned wrapper) that ran; or
"Attempted but failed (<reason>)" if a model was reachable but every attempt errored;
or "Skipped (no secondary model available)" if none was reachable>

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
- **Run the adversarial pass even on small diffs.** A 5-line change to determinism or serialization is exactly the kind of thing one model misses. The only gate is whether a secondary model is reachable — never whether anything has been configured.
- **Reviewer agent owns project-specific check categories.** This skill orchestrates; the agent (whether the single-pass reviewer, a spoke, or the coordinator) embodies the conventions. Keep the conventions in one place to avoid drift.
- **Hub-and-spoke is a performance optimization, not a different review.** The coordinator's rollup should read like one coherent review, not a patchwork of per-file reports — findings still land in the same `$REVIEW_FILE` format either way, and downstream consumers (`/feature-flow`, verdict resolution) don't need to know which path ran.
- **Backlog cross-reference**: if the diff appears to address an open item in the project's backlog file (heuristic match on file paths or symbol names), include a `Possibly closes: <title>` line in the review summary. Non-blocking; surface only.

## Calling from `claude -p` (headless)

If you wire this skill into a batch script or CI job:

```bash
CLAUDE_HEADLESS=1 claude -p "/review origin/main" \
  --output-format json \
  --allowedTools "Read,Write,Edit,Bash,Agent"
```

The skill returns its findings via the round's `handoffs/review-{issue}-{round}.md` file and the `VERDICT:` line in stdout. Parse the verdict to branch your script. AskUserQuestion does not need to be in `--allowedTools` — the skill detects its absence and routes to the deferred-finding path.
