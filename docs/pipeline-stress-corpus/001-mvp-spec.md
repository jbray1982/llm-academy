# Pipeline Stress Corpus — 001 MVP Spec (case tc-001)

## Goal

Stand up the corpus with one fully-built case in this repo: **tc-001, the
harness telemetry report tool**. The case must demonstrate the full corpus
mechanic end to end — straight-written payload docs, an MVP + blocked
next-iteration issue pair, engineered stress points mapped to pipeline failure
modes, and a two-axis grading rubric — so that running `harness/run.sh` against
the payload issue produces a gradable scorecard.

## In Scope

- Payload artifacts for tc-001: `docs/harness-telemetry-report/vision.md`,
  `docs/harness-telemetry-report/001-mvp-spec.md`, an MVP GitHub issue, and a
  next-iteration issue blocked on the MVP.
- This spec's stress-point map and grading rubric (below).
- Run + teardown protocol.

## Out of Scope (for MVP)

- A second case, any non-bash domain, executable grader scripts, CI wiring.
- Resetting/re-running protocol beyond "close issues, delete branch".

## Payload choice and why

The harness MVP spec explicitly deferred a telemetry reader ("capture only; no
reader in the MVP"), so a report tool is the most plausible next piece of real
work in this repo — triage has no textual reason to smell a test. It is
self-contained (touches no in-flight feature), yet genuinely complex: JSONL
parsing with malformed-line tolerance, multi-run aggregation, percentile math,
three output formats, pinned exit codes, and repo-convention obligations.

## Stress-point map

Each engineered element of the payload spec/issue, and the failure mode it probes:

| Payload element | Pipeline failure mode probed |
|---|---|
| Spec is thorough with clear steps, but contains one real architectural judgment (schema-drift tolerance for older telemetry records) | Triage routing: lead-dev fast-track vs needs-architect is a genuine judgment call; either is defensible, the decision and its reasoning get recorded |
| Cross-cutting constraints stated exactly once (stdout/stderr discipline; `report_` function prefix + module "Secret owned:" header; stage ordering rule) | Handoff context loss: constraints stated early must survive to the final diff |
| 14 strict, mechanically-checkable acceptance criteria (nearest-rank percentiles, exact JSON top-level keys, exact exit codes, retry definition) | Review→fix loop: a plausible first pass misses some; the loop must converge with fixes that actually fix |
| README update + lib structure + bash/jq-only obligations; `harness/` propagates via existing symlink (no install.sh change needed) | Convention adherence: repo rules are discoverable (CLAUDE.md, existing lib headers) but not restated in the issue |
| Next-iteration issue filed blocked on the MVP | Deferral: running the harness on the blocked issue must exit 75 (deferred), not proceed |
| Fixture-based correctness checks below, independent of pipeline gates | Verify-gate blind spots: gates can pass while the tool is wrong |

## Grading rubric

### Axis 1 — pipeline behavior (from the run's telemetry + artifacts)

- [ ] Triage: `ready=true`; routing decision and reasoning recorded (note which
      bucket — both lead-dev and needs-architect are acceptable; absence of
      reasoning is a fail)
- [ ] No stage aborted; final exit code 0; commit message references the issue
- [ ] Each cross-cutting constraint (stderr/stdout discipline, `report_`
      prefix, module header, stage-ordering rule) is present in the final
      diff — score each separately; misses indicate handoff context loss
- [ ] If review failed an attempt, the subsequent fix attempt changed the diff
      and the re-review addressed the named failure (no oscillation: same
      criterion failing twice with the same reason is a loop pathology)
- [ ] Every `failed` telemetry record carries a non-empty, specific
      `failure_reason`
- [ ] README gained a Reporting section; no edits to `install.sh` or the
      telemetry write path
- [ ] Blocked next-iteration issue: a harness run against it defers cleanly
      (exit 75) with the dependency named in the triage reasoning

### Axis 2 — product correctness (procedural, run after the pipeline commits)

Construct a fixture runs root with: run A (multi-stage, one stage with 3
attempts: failed, failed, passed), run B (contains one malformed JSONL line and
one record with a quoted/newline-escaped `failure_reason`), run C (empty
telemetry file). Then assert:

- [ ] Text mode: aggregates on stdout, exactly one malformed-line summary on
      stderr, exit 0
- [ ] `--format json` passes `jq empty`; top-level keys exactly
      `generated_at, runs_scanned, records, warnings, stages, items,
      failure_reasons`; `warnings.malformed_lines == 1`;
      `warnings.empty_runs == 1`
- [ ] The 3-attempt stage reports `attempts=3, passed=1, failed=2` and retries
      counted as 2 (attempts beyond the first per run_id+stage)
- [ ] p50/p95 match nearest-rank hand-computation for the fixture durations
- [ ] `--item`/`--stage`/`--since` filters produce the expected subsets
- [ ] Nonexistent runs root → exit 3; bad flag → exit 2 with usage on stderr
- [ ] LLM-rubric pass: code reads like the existing `harness/lib/` modules
      (header style, error handling, no needless dependencies); spec drift
      noted

## Run protocol

1. Payload docs + FEATURE_LOG entry live on a disposable branch; issues filed
   in this repo. Pipeline runs from a checkout of that branch — preferably a
   worktree with `docs/pipeline-stress-corpus/` removed (contamination
   control).
2. `harness/run.sh <mvp-issue>` with the default config. Capture the run dir.
3. Grade Axis 1 from `{run_dir}/telemetry.jsonl` + handoffs + the diff; grade
   Axis 2 against the committed tree.
4. Optionally run `harness/run.sh <next-iteration-issue>` before the MVP lands
   to grade the deferral row.

## Teardown

Close both payload issues with a comment noting the corpus run, delete the
payload branch. Keep the scorecard (append a dated results note under this
directory). Corpus docs themselves are keepable real work.

## Acceptance Criteria

- [ ] tc-001 payload docs exist and read as a genuine feature (no corpus
      references, no synthetic tells)
- [ ] MVP + next-iteration issues filed; next-iteration explicitly blocked on
      the MVP, matching this repo's issue style
- [ ] Every stress-point row above maps to at least one concrete element in
      the payload spec or issue
- [ ] Both grading axes are executable as written by a human with the repo and
      the run dir — no missing definitions
