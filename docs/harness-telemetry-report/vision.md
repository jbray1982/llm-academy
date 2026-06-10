# Harness Telemetry Report — Vision

## Vision

The harness MVP deliberately shipped telemetry as capture-only: every stage
attempt appends one JSONL record, and nothing reads them. This feature is the
reader. `harness/report.sh` turns accumulated run records into answers —
which stages retry most, where time goes, what defers and why — first for a
single repo's `.harness/runs/`, eventually across repos and harness versions.
The long-term ambition is for telemetry to drive harness tuning: when a prompt
or gate changes, the report is the before/after evidence. The report tool is
the first consumer of the pinned telemetry schema and therefore also the thing
that keeps the schema honest.

## User Experience

After a few harness runs, you type `harness/report.sh` and get an immediate
per-stage table: attempts, pass/fail/defer/skip counts, retry rate, p50/p95
durations — plus a per-item rollup and the most common failure reasons. You
narrow with `--item 42` or `--stage review` or `--since 2026-06-01`, and you
pipe `--format json` into `jq` or a dashboard without ever parsing tables.
Diagnostics never pollute the data: stdout is the report, stderr is for
warnings. It never dies on a half-written record from an interrupted run — it
counts the damage and reports anyway.

## Mechanics & Systems

- Scan a runs root (default `.harness/runs/`), parse every
  `*/telemetry.jsonl`, tolerate malformed lines and empty files.
- Aggregate per stage (counts by status, retry rate, duration percentiles),
  per item (runs, attempts, last status), and failure-reason frequency.
- Output formats: human text table (default), `json` (stable schema for
  tooling), `md` (paste into issues/PRs).
- Entry point `harness/report.sh` stays thin (args + dispatch); aggregation
  logic lives in `harness/lib/report.sh` following the existing lib module
  conventions.
- Reads only — the telemetry write path (`lib/telemetry.sh`) is untouched and
  remains the single owner of the record schema.

## Open Questions

- Cross-repo aggregation: a consuming repo's runs live in that repo's
  `.harness/runs`; comparing across repos needs a multi-root story.
- Schema evolution: the record schema is pinned now, but a future version bump
  needs a tolerance policy in the reader (ignore vs. warn vs. per-version
  handling).
- Trend deltas: comparing two time windows ("did review retries drop after the
  prompt change?") is the obvious next iteration once single-window
  aggregation exists.

## Out of Scope

- Dashboards, web UI, or any long-running process — this is a CLI that prints
  and exits.
- Changing what telemetry is recorded or how (writer side is pinned).
- Automated adaptation (feeding reports back into config) — reports inform
  humans first.
