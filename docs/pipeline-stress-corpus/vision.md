# Pipeline Stress Corpus — Vision

## Vision

A curated library of graded, real-feeling work items used to stress-test the
orchestration harness pipeline as it evolves. Where public coding benchmarks test
*models*, this corpus tests *the pipeline*: triage routing, architect decisions,
handoff fidelity between stages, the review→fix retry loop, verification gates,
deferral behavior, and telemetry quality. Each case is a synthetic-but-plausible
feature (payload) with its own vision/spec docs and GitHub issues, paired with a
grading rubric that scores two independent axes: **pipeline behavior** (did the
stages do their jobs?) and **product correctness** (is the thing it built right?).

The dream version spans domains. The harness is generic; its failure modes are
not. A case that exercises bash infra work in this repo says nothing about how
the pipeline handles a web feature with visual acceptance criteria, a game
mechanic with emergent behavior, or an ETL job with data-quality gates. The
corpus grows one case at a time across these domains, and re-running the corpus
after every harness change becomes the regression suite for the pipeline itself.

## User Experience

A harness developer changes a prompt, a gate predicate, or the retry policy.
They pick a corpus case, stand up its payload artifacts (branch + issues), run
`harness/run.sh <issue>` against it, then grade the run: procedural checks
against the produced artifact, telemetry assertions against the run's
`telemetry.jsonl`, and an LLM-rubric pass for the judgment calls. The result is
a per-case scorecard that is comparable across harness versions, so "did my
change make triage worse?" has an empirical answer.

## Mechanics & Systems

- **Case anatomy.** Each case `tc-NNN` consists of: (1) payload feature docs
  (`docs/<payload>/vision.md` + numbered spec), written straight — no hint they
  are synthetic, because the pipeline's agents read them; (2) a GitHub issue
  pair — an MVP issue the harness runs against, and a next-iteration issue
  blocked on it (exercising the blocked-deferral path); (3) a grading rubric in
  the case spec; (4) a run + teardown protocol.
- **Two-axis grading.** *Pipeline behavior*: assertions over the run's
  telemetry and artifacts (routing decision, retry counts, handoff-carried
  constraints present in the final diff, clean exit codes). *Product
  correctness*: procedural checks (fixtures, expected outputs, exit codes) run
  against the pipeline's commit, independent of whatever verification the
  pipeline itself performed — this catches verify-gate blind spots.
- **Pipeline failure-mode taxonomy** (what cases are engineered to surface):
  - Triage misrouting — wrong fast-track bucket, or deferring ready work.
  - Handoff context loss — a constraint stated once early (in the spec or by
    the architect) absent from the final implementation.
  - Review-loop pathologies — non-convergence, oscillation, fixes that don't
    fix, judge false-pass/false-fail.
  - Deferral errors — proceeding on blocked work, or spurious deferral.
  - Convention violations — repo rules (CLAUDE.md, lib structure, doc updates)
    ignored despite being discoverable.
  - Verify-gate blind spots — all gates pass but the product is wrong.
  - Telemetry gaps — failures recorded without a usable `failure_reason`.
- **Cross-domain growth.** Future cases live in (or simulate) consuming repos:
  web development (visual/UX acceptance), game development (mechanic +
  playtest rubric), ETL pipelines (data-quality gates). The corpus index in
  this directory tracks every case, its domain, and the failure modes it
  targets.
- **Contamination control.** Corpus docs describe payloads as synthetic; the
  payload docs do not. When running a case, prefer a worktree with
  `docs/pipeline-stress-corpus/` removed so pipeline agents cannot discover the
  rubric; at minimum, never reference corpus docs from payload docs or issues.

## Open Questions

- Score aggregation: per-case scorecards exist first; whether a cross-case
  weighted score is meaningful is unresolved.
- Re-runnability: payload issues get closed by successful runs; the protocol
  for resetting a case (reopen vs. re-file) needs to settle after a few runs.
- Whether telemetry assertions should become an executable grader script per
  case or stay a manual checklist (start manual, extract on third occurrence —
  WET rule).

## Out of Scope

- Testing models themselves — model capability benchmarks are someone else's
  corpus. A case failing because the underlying model is weak is noise here
  unless the pipeline could have caught/recovered it.
- Automated corpus runners / CI integration — cases are run by hand for now.
- Payloads intended to merge. Payload code may be good enough to keep, but the
  corpus makes no promise; teardown is the default.
