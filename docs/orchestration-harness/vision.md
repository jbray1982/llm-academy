# Orchestration Harness — Vision

## Vision

A generic, project-agnostic, **headless single-work-item pipeline runner** — in one
line, *"feature-flow, headless + configurable + instrumented + pluggable."* It takes
one work item and drives it through a configurable sequence of LLM stages (triage →
architect → implement → review → commit, by default), gating each stage with
verification, passing context between stages via inspectable handoff documents, and
recording structured telemetry on every run.

It is the canonical, reusable form of the hand-rolled bash pipeline that lives today
in `sunken-spires-adventure/tools/batch-process-issues.sh`. That script tangles two
concerns: an **outer batch loop** (fetch issues, dependency-sort, loop-until-complete,
merge/push, stats) and an **inner single-item pipeline** (`process_issue`: the staged
BA→architect→dev→review→commit flow). This feature extracts and generalizes *only the
inner pipeline*. Where items come from, how many run, ordering, concurrency, and
landing are **out of scope** — a separate outer wrapper supplies those. sunken-spires
becomes the first such wrapper; the harness is what it calls its "batch processor,"
but the harness itself processes exactly one item per invocation.

The harness lives in llm-academy as a new installable artifact and follows the
project's adoption model: generic canonical definition, per-repo customization through
configuration and prompt-file overrides rather than forks.

## User Experience

A maintainer of a consuming repo runs:

```
harness/run.sh <item> [--config path/to/config.yaml]
```

With no `--config`, the harness uses its default config (the feature-flow stage
preset). `<item>` is an opaque identifier — a GitHub issue number for sunken-spires,
but the harness never assumes that; the first configured stage fetches its own context
(`gh issue view <item>`, read a file, etc.). The run executes each configured stage
headlessly, writing handoff documents and telemetry under a per-run directory, and
exits with a status the caller can branch on.

What it *feels* like compared to the old bash loop: prompts are now editable files you
can tune without touching the script; you can see exactly why a run failed (telemetry
+ handoffs); stages only advance when their verification passes; and swapping the
underlying LLM CLI is a config concern, not a rewrite.

## Mechanics & Systems

- **Configurable staged pipeline.** Stages are an ordered list in a YAML config. Each
  stage is self-describing: prompt file, optional output schema, allowed tools,
  handoffs it consumes/produces, verification gate, and failure policy. The default
  config ships the feature-flow preset.
- **Prompts in files.** Every stage's prompt text lives in a `prompts/<stage>.md`
  file referenced by the config — never inline in the script. Tunable and overridable
  per repo independent of the harness code.
- **Handoff documents (replaces session threading).** The current script threads a
  single `claude --resume <session>` across all stages. The harness replaces that with
  explicit per-stage handoff docs: a stage writes a structured result + prose summary,
  downstream stages declare what they `consume`, and the harness injects those
  handoffs into their prompts. This is what makes the backend swappable and the run
  inspectable — `--resume` is claude-only; handoff docs are backend-agnostic.
- **Layered verification.** Each stage may declare a verification gate: deterministic
  `checks` (commands whose exit code gates the stage — tests, lint, build) and/or an
  optional LLM `judge` (evaluates the stage output against stated criteria). Which
  checks run at which stage is configurable. Failure drives the stage's failure policy
  (`retry` / `defer` / `abort`).
- **Telemetry capture.** Every stage attempt appends a structured record (run id,
  item, stage, backend, attempt, status, verify results, failure reason, timestamps)
  to a per-run telemetry log. Capture-only in the MVP — written to be analyzed later.
- **Optional documentation stage.** An optional, gated `document` stage runs after
  `review` and before `commit`, driven by the `documentarian` agent. It reconciles what
  shipped against the design/spec and propagates the delta to outward-facing surfaces
  (README, CHANGELOG, reference docs), leaving a one-line *as-built* note on the spec
  where behavior diverged. It is **gated on source changes** — diffs that touch no source
  (docs-only, config-only, test-only) make it a no-op — so it costs nothing on the many
  runs that don't move a public contract. Off in the minimal preset; opt-in via config.
  The set of documented surfaces and what counts as "source" is repo-specific
  (overlay/config), not baked into the stage.
- **Backend seam.** The headless LLM invocation sits behind a single backend module
  (`run_stage(prompt, schema, tools) → result`). The MVP ships one implementation
  (`claude -p`), but the boundary is clean enough that a second backend (`codex`,
  etc.) is a drop-in addition, not a rewrite.
- **Installation.** A new top-level `harness/` directory (script + default config +
  prompt files + schemas + backend lib). `install.sh` is extended to propagate it —
  the harness is a *new kind of installable artifact* beyond the existing
  `skills/*/` and `agents/*.md` globs, which CLAUDE.md flags as needing a deliberate
  script update.

### Current State (in the sunken-spires script, pre-harness)

Already present in `process_issue`, to be generalized: staged BA→architect→
scaffold/lead/junior/direct→review-loop→BA-commit flow; typed stage outputs via
`--json-schema`; per-stage `--allowedTools`; label-based deferral
(`product-decision-review`, `planning`, `follow-up-issue`, `blocked`); dependency
detection and decision-required handling. **Missing, and added by this feature:**
file-based prompts, configurable stage definitions, verification gates, telemetry, and
the backend seam. Hardcoded today and to be made configurable: claude-specific CLI
flags, dotnet-specific check commands, the `Co-Authored-By` line.

## Open Questions

- **How to *act* on telemetry.** The MVP only captures it. The feedback loop —
  manual review, assisted pattern-surfacing, or in-run automated adaptation — is
  deliberately unresolved. Capturing the right fields now is what keeps that door open.
- **Overlay mechanism for harness config/prompts.** llm-academy customizes skills/
  agents via `.llm-academy/<slug>.md` overlays. The harness's per-repo customization
  is its config + prompt files. Whether `learn-repo` should generate a starter config
  and seed prompts (the way it generates skill overlays) is a candidate iteration, not
  yet decided.
- **Retry/escalation semantics beyond a static `max_retries`** (e.g. escalate
  junior→lead on repeated failure) — left to a later iteration.

## Out of Scope

- **The outer batch loop entirely**: item discovery/sourcing, dependency-sort
  ordering, `--loop-until-complete`, concurrency, the inter-item pause.
- **Git landing**: branch creation, merge, push, PR. The harness runs configured
  stages on the repo as-is; a commit is just another configured stage. Branching and
  landing belong to the caller.
- **A real second backend.** The MVP designs the seam and implements claude only;
  shipping codex is explicitly deferred.
- **Acting on telemetry** (see Open Questions) — capture only.
