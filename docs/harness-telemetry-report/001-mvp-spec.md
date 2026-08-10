# Harness Telemetry Report — 001 MVP Spec

## Goal

Ship `harness/report.sh`: a read-only CLI that aggregates the telemetry JSONL
records the harness already writes into per-stage, per-item, and
failure-reason summaries, in three output formats, robust to malformed or
incomplete records. The MVP must demonstrate that one command turns a
directory of historical runs into an accurate picture of pipeline health, and
it must do so without touching the telemetry write path.

## In Scope

- `harness/report.sh [--runs-dir <path>] [--item <id>] [--stage <name>]
  [--since <iso8601>] [--format text|json|md]` executable.
- Aggregation library `harness/lib/report.sh` following the existing lib
  conventions: a module header comment declaring the secret the module owns,
  and all functions prefixed `report_`.
- Three output formats; text is the default.
- Malformed-record tolerance with explicit accounting.
- A "Reporting" section in `harness/README.md` documenting invocation, the
  JSON output schema, and exit codes.

## Out of Scope (for MVP)

- Cross-repo / multi-root aggregation.
- Trend comparison between time windows.
- Any change to `lib/telemetry.sh` or the record schema it owns.
- HTML or any other additional output format.
- New dependencies: the tool must work with bash + jq, which the harness
  already requires. No python, no awk-only reimplementation of jq.

## Data Model

### Input — telemetry record (pinned by `lib/telemetry.sh`)

One JSON object per line in `{runs root}/<run dir>/telemetry.jsonl`:

```json
{"run_id":"42-20260609T182000Z","item":"42","stage":"review","backend":"claude",
 "attempt":2,"status":"failed","failure_reason":"…","started_at":"<iso8601>",
 "ended_at":"<iso8601>","verify":{…}}
```

`status` is one of `passed | failed | deferred | skipped`. `attempt` is a
number, 1-based. Run directories are named `<item>-<UTC timestamp>`.

### Output — JSON format (stable; this spec pins it)

```json
{
  "generated_at": "<iso8601>",
  "runs_scanned": 3,
  "records": 17,
  "warnings": { "malformed_lines": 1, "empty_runs": 1 },
  "stages": [
    { "stage": "triage", "attempts": 3, "passed": 3, "failed": 0,
      "deferred": 0, "skipped": 0, "retry_rate": 0.0,
      "duration_seconds": { "p50": 14, "p95": 22, "max": 22 } }
  ],
  "items": [
    { "item": "42", "runs": 2, "total_attempts": 11, "last_status": "passed" }
  ],
  "failure_reasons": [ { "reason": "…", "count": 2 } ]
}
```

Top-level keys are exactly these seven; additions are a schema change and
belong to a later iteration.

### Definitions (normative)

- **Retry**: any record with the same `(run_id, stage)` beyond the first.
  `retry_rate` = retries / attempts for that stage, rounded to 2 decimals.
- **Duration**: `ended_at − started_at` in whole seconds, per record. Records
  missing either timestamp are excluded from duration stats only.
- **Percentiles**: nearest-rank method (ceil(p/100 × N)th value of the sorted
  list), computed over all of a stage's records that have durations.
- **`last_status`** for an item: the `status` of the final record of that
  item's lexicographically-last `run_id`.
- **Stage ordering** in all formats: order of first appearance, scanning run
  directories in lexicographic order and lines in file order. (This
  reconstructs pipeline order without hardcoding stage names.)

## Behaviors

1. Resolve the runs root: `--runs-dir` if given, else `.harness/runs` relative
   to the current directory. Nonexistent root, or no run directories matching
   the filters: print an explanatory message to stderr, exit `3`.
2. Scan every `<run dir>/telemetry.jsonl`. A line that fails to parse as JSON
   is skipped and counted in `warnings.malformed_lines`. A run directory whose
   telemetry file is missing or empty counts in `warnings.empty_runs`. Neither
   is fatal; the report still renders and exits `0`.
3. Apply filters before aggregation: `--item` matches the record's `item`
   field exactly; `--stage` matches `stage` exactly; `--since` keeps records
   with `started_at >=` the given ISO-8601 instant (string comparison is
   acceptable given the fixed format).
4. Aggregate and render:
   - **text** (default): a per-stage table, a per-item rollup, and top failure
     reasons, human-aligned. If any warnings were counted, print exactly one
     summary line to stderr (e.g. `warning: 1 malformed line, 1 empty run
     skipped`). Data goes only to stdout; diagnostics only to stderr.
   - **json**: the document above, exactly once, nothing else on stdout.
     Warnings appear in the `warnings` object, not on stderr.
   - **md**: the same tables as GitHub-flavored Markdown.
5. Usage errors (unknown flag, bad `--format` value, missing flag argument):
   usage text to stderr, exit `2`.
6. Exit codes: `0` report rendered (warnings allowed), `2` usage error, `3` no
   data to report.

### Edge cases

- A record whose `failure_reason` contains escaped quotes/newlines (the writer
  escapes them) must round-trip into the failure-reason rollup intact.
- An interrupted run (telemetry ends mid-pipeline) is just fewer records — no
  inference about missing stages.
- Records from a future schema with extra fields: ignore unknown fields,
  aggregate the pinned ones. Records *missing* pinned fields other than
  timestamps: treat the line as malformed. (If a different tolerance policy
  seems warranted, that is an architectural decision to surface, not to make
  silently.)
- Duplicate `attempt` numbers for the same `(run_id, stage)` (writer bug or
  manual edit): count both as attempts; do not dedupe.

## Integration Points

- **`lib/telemetry.sh`** — read-only consumer of its pinned schema. The writer
  is not modified.
- **`harness/README.md`** — gains a "Reporting" section (invocation, JSON
  schema, exit codes) alongside the existing Telemetry section.
- **`install.sh`** — no change: `harness/` is propagated as a whole directory
  symlink, so new files inside it carry over automatically.
- **Lib conventions** — `harness/lib/report.sh` is sourced by the entry point
  the same way `run.sh` sources its modules; module header declares its owned
  secret; functions are `report_`-prefixed.

## Extension Hooks (wired now, even if empty)

- Format rendering dispatched through one function per format
  (`report_render_text|json|md`), so a new format is one function + one
  dispatch entry.
- Runs root is a parameter everywhere internally (no hardcoded `.harness/runs`
  below the entry point), so multi-root aggregation is an argument-parsing
  change later.
- The `warnings` object is extensible by key; renderers iterate it rather than
  hardcoding the two current keys.

## Acceptance Criteria

- [ ] `harness/report.sh` with no arguments renders the text report for
      `.harness/runs` — data on stdout only, diagnostics on stderr only
- [ ] `--format json` emits one JSON document that `jq empty` accepts, with
      top-level keys exactly `generated_at, runs_scanned, records, warnings,
      stages, items, failure_reasons`
- [ ] `--format md` renders the same tables as GitHub-flavored Markdown
- [ ] Per-stage rows report attempts, passed, failed, deferred, skipped,
      retry_rate, and p50/p95/max duration; percentiles use nearest-rank
- [ ] Retries are counted as records beyond the first per `(run_id, stage)`;
      retry_rate rounds to 2 decimals
- [ ] Durations are `ended_at − started_at` in seconds; records missing a
      timestamp are excluded from duration stats only
- [ ] `--item`, `--stage`, and `--since` filter as specified; `--since`
      compares against `started_at`
- [ ] Malformed JSONL lines are skipped, counted in
      `warnings.malformed_lines`, and the run still exits 0; text mode prints
      exactly one stderr warning summary; json mode keeps stderr silent
- [ ] Empty/missing telemetry files count in `warnings.empty_runs` without
      aborting
- [ ] Missing runs root or zero matching records exits 3 with an explanation
      on stderr; usage errors exit 2 with usage on stderr
- [ ] Stage rows appear in first-seen order scanning run dirs
      lexicographically
- [ ] Aggregation logic lives in `harness/lib/report.sh` with `report_`-
      prefixed functions and a module header declaring its owned secret;
      `harness/report.sh` is a thin entry point
- [ ] bash + jq only; no new dependencies introduced
- [ ] `harness/README.md` gains a Reporting section; `lib/telemetry.sh` and
      `install.sh` are unchanged
