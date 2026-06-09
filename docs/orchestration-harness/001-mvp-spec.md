# Orchestration Harness — 001 MVP Spec

## Goal

Ship a headless, single-work-item pipeline runner that executes a **config-defined,
file-prompted** stage sequence for one item, replacing the inline-prompt /
session-threaded approach in `sunken-spires-adventure/tools/batch-process-issues.sh`'s
`process_issue`. The MVP must demonstrate that the same feature-flow stage flow can run
from external config + prompt files, with **handoff-doc context passing**, a
**verification gate** (deterministic checks + LLM judge), and **telemetry capture** —
all behind a clean backend seam with a single claude implementation. Success looks
like: `harness/run.sh <item>` runs the default (feature-flow) pipeline on one item,
writes handoffs + telemetry under a per-run dir, and exits with a meaningful status,
with zero prompt text living in the script.

## In Scope

- `harness/run.sh <item> [--config <path>]` executable; defaults to
  `harness/config/default.yaml` when `--config` is omitted.
- YAML config defining an ordered list of stages (the feature-flow preset as default).
- Per-stage prompt files under `harness/prompts/`; no prompt text inline in the script.
- Handoff-document context passing between stages (replaces `--resume` threading).
- Per-stage verification gate: deterministic `checks` (exit-code gated) **and** an
  optional LLM `judge`. Both configurable per stage; which run is data, not code.
- Telemetry: one structured record appended per stage attempt to a per-run JSONL log.
- Internal backend seam: one module exposing a single stage-execution function;
  `claude -p` is the only implementation. No backend config knob required (a `backend:`
  key may exist but only `claude` is valid).
- Default config reproduces the existing inner flow: triage → (architect | fast-track)
  → scaffold/lead/junior/direct → review-loop(+fix) → commit, including label-based
  deferral and decision-required handling, expressed in config + prompts.
- Extend `install.sh` to propagate the new `harness/` directory.
- `harness/README.md` documenting invocation, config schema, and how to override
  prompts/config per repo.

## Out of Scope (for MVP)

- The outer batch loop: item sourcing, dependency-sort ordering, `--loop-until-complete`,
  concurrency, inter-item pause. (Caller's job.)
- Git branch creation, merge, push, PR. (A commit may be a configured stage; landing is
  the caller's.)
- A second backend (codex et al.) — seam only.
- Programmatic consumption of telemetry / any adaptation loop — capture only.
- `learn-repo` generation of harness config/prompts — manual config authoring for now.
- Escalation policies beyond a static `max_retries` per stage.

## Data Model

### Directory layout (canonical, in llm-academy)
```
harness/
  run.sh                  # executable: run.sh <item> [--config <path>]
  config/default.yaml     # feature-flow preset
  prompts/                # triage.md, architect.md, scaffold.md, lead-dev.md,
                          #   junior-dev.md, direct.md, review.md, fix.md,
                          #   commit.md, judge-*.md
  schemas/                # optional per-stage JSON schemas (triage.json, architect.json,
                          #   review.json)
  lib/backend-claude.sh   # the one backend implementation behind the seam
  README.md
```

### Config schema (YAML)
```yaml
backend: claude                       # seam; only 'claude' valid in 001
co_author: "Co-Authored-By: Claude <noreply@anthropic.com>"
run_dir: .harness/runs/{item}         # {item} interpolated at runtime
stages:
  - name: triage
    prompt: prompts/triage.md         # required; prompt text lives here
    schema: schemas/triage.json       # optional; drives structured output
    tools: ["Bash(gh issue view {item}*)"]   # backend-translated allowed tools
    consumes: []                      # list of prior handoff names to inject
    produces: handoffs/triage.md      # relative to run_dir; omit if none
    verify:
      checks: []                      # list of shell commands; non-zero = fail
      judge: null                     # or { prompt: prompts/judge-triage.md,
                                      #      criteria: "…", schema: schemas/judge.json }
    on_fail: defer                    # retry | defer | abort
    max_retries: 0
```
- **Template interpolation:** `{item}` and `{run_dir}` are substituted in `tools`,
  `produces`, `run_dir`, and prompt files at runtime. Prompt files may reference
  `{item}` and `{{handoff:<name>}}` placeholders; the harness fills the latter with the
  consumed handoff contents.
- **Stage selection:** stages run top-to-bottom. A stage may be skipped by a prior
  stage's structured output (e.g. triage returns `ready=false` → `on_fail: defer`
  semantics terminate the run cleanly). Conditional branching (fast-track vs architect)
  is expressed by stages reading the prior handoff and no-op'ing when not applicable —
  the same way the bash script branches on `$approach`.

### Handoff document (`{run_dir}/handoffs/<stage>.md`)
Markdown with three parts: (1) a fenced JSON block of the stage's structured result;
(2) a prose summary the stage emits; (3) a list of changed-file paths (from
`git diff --name-only`) when the stage modified the tree. Downstream stages that name
this file in `consumes` get it injected at the `{{handoff:<name>}}` placeholder.

### Telemetry record (`{run_dir}/telemetry.jsonl`, one line per stage attempt)
```json
{"run_id":"<item>-<timestamp>","item":"<item>","stage":"triage","backend":"claude",
 "attempt":1,"status":"passed|failed|deferred|skipped","verify":{"checks":[{"cmd":"…",
 "exit":0}],"judge":{"verdict":"pass|fail","reason":"…"}},"failure_reason":null,
 "started_at":"<iso8601>","ended_at":"<iso8601>"}
```
Capture-only; no reader in the MVP. `run_id` is `<item>-<UTC timestamp>` (shell `date`).

## Behaviors

1. **Load config.** Resolve `--config` or default. Validate it parses and every stage
   has a readable `prompt` file. Fail fast with a clear message if not.
2. **Init run dir.** Create `{run_dir}` (interpolating `{item}`); create `handoffs/`
   and `telemetry.jsonl`.
3. **For each stage, in order:**
   a. Assemble the prompt: read the prompt file, interpolate `{item}`, and inject each
      `consumes` handoff at its `{{handoff:<name>}}` placeholder.
   b. Invoke the backend seam with (prompt, schema?, tools). Backend translates these to
      CLI flags (claude: `--output-format json`, `--json-schema`, `--allowedTools`).
   c. Run verification: execute each `checks` command (non-zero exit = fail); if a
      `judge` is configured, invoke the backend with the judge prompt + criteria and
      read its verdict.
   d. Write the telemetry record for this attempt.
   e. On verify pass: write the stage's `produces` handoff (if any), continue.
   f. On verify fail: apply `on_fail` — `retry` (re-run up to `max_retries`, then
      treat as `abort`), `defer` (clean stop, exit code reserved for "deferred"),
      `abort` (stop, non-zero exit).
4. **Structured-output-driven early exit.** A stage whose structured output signals a
   terminal condition (triage `ready=false`, architect `decision-required`) records a
   `deferred`/`skipped` status and stops the pipeline cleanly — mirroring the bash
   script's `return 0` deferrals. The mapping from output field → terminal condition is
   declared in config (e.g. `terminal_when: {field: ready, equals: false}`), keeping it
   data-driven.
5. **Exit codes.** `0` = pipeline completed all stages; `0` (distinct status logged) =
   deferred cleanly; non-zero = a stage aborted / max retries exhausted. The caller
   (outer wrapper) branches on these.

### Edge cases
- **No changes after implementation stages:** a commit/verify stage detects an empty
  `git diff` and records `skipped`; the pipeline completes without committing
  (mirrors the script's no-changes shortcut).
- **Missing prompt/schema file:** fail fast at config-load, not mid-run.
- **Judge configured but backend can't return structured verdict:** treat as a verify
  failure with `failure_reason` noting the judge error — never silently pass.
- **`checks` command not found / project tool absent:** non-zero exit → verify fail;
  surfaced in telemetry, not swallowed.

## Integration Points

- **Backend seam → `claude` CLI.** `lib/backend-claude.sh` owns all claude-specific
  flags. Nothing else in the harness references `claude` directly.
- **`install.sh`.** Extend to copy/symlink `harness/` into a consuming repo. This is
  the deliberate "new artifact kind" change CLAUDE.md requires; document the decision
  in the install script and README.
- **feature-flow parity.** The default config + prompts encode the same stages,
  labels, and deferral logic as `skills/feature-flow/SKILL.md` and the existing
  `process_issue`, so behavior is recognizable to anyone who knows either.
- **Consuming repo (sunken-spires).** Wraps `harness/run.sh` in its own outer loop;
  supplies a repo-specific config (check commands, tools, co-author, prompts).

## Extension Hooks (wired now, even if empty)

- **`backend:` config key + seam signature** — present so a second backend is a new
  `lib/backend-<name>.sh` + a dispatch line, no caller changes.
- **`verify.judge`** — schema accepts a judge block on every stage even where unused.
- **Telemetry schema** — includes `backend` and `attempt` fields now so cross-run /
  cross-backend analysis is possible later without a format migration.
- **`consumes`/`produces`** — the handoff graph is declared per stage, so inserting or
  reordering stages is a config edit.

## Acceptance Criteria

- [ ] `harness/run.sh <item>` runs end-to-end on one item using `config/default.yaml`
      with **no prompt text in the script** — all prompts load from `harness/prompts/`.
- [ ] Editing a prompt file changes stage behavior on the next run with no code change.
- [ ] Stages pass context via handoff docs under `{run_dir}/handoffs/`; no
      `--resume`/session threading remains in the default flow.
- [ ] At least one stage has a deterministic `checks` gate and one has an LLM `judge`;
      a forced check failure halts/retries per `on_fail`, and the failure appears in
      telemetry.
- [ ] `{run_dir}/telemetry.jsonl` contains one well-formed record per stage attempt
      with all schema fields populated.
- [ ] All claude-specific invocation is confined to `lib/backend-claude.sh`; the rest
      of the harness is backend-agnostic.
- [ ] Triage `ready=false` and architect `decision-required` terminate the run cleanly
      with the right logged status, matching the bash script's deferral behavior.
- [ ] `install.sh` propagates `harness/` into a target repo; README documents
      invocation, the config schema, and per-repo prompt/config overrides.
- [ ] Git scope honored: the harness performs no branch/merge/push/PR; any commit is a
      configured stage operating on the current tree.
