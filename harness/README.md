# llm-academy harness

A headless single-work-item pipeline runner. Executes an ordered list of stages
defined in YAML config + prompt files, passing context between stages via handoff
documents. Each stage is gated by deterministic checks and/or an LLM judge; every
attempt is recorded to JSONL telemetry.

## Invocation

```bash
harness/run.sh <item> [--config <path>]
```

- `<item>` — work item identifier, typically a GitHub issue number (e.g. `42`)
- `--config <path>` — YAML config file (default: `harness/config/default.yaml`)

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0    | All stages completed (some possibly skipped) |
| 75   | Deferred — triage not-ready, decision-required, or guard-stage defer (EX_TEMPFAIL — retry later) |
| 1    | Stage aborted or max retries exhausted |
| 2    | Config or usage error |

**Requirements:** `yq` (mikefarah) must be on `PATH`. Install:
- macOS/Linux: `brew install yq`
- Linux: `snap install yq` or download from https://github.com/mikefarah/yq/releases
- Windows: not supported yet (install.ps1 does not exist)

## Config schema

See [`config/README.md`](config/README.md) for the full configuration reference
(all stage fields, predicate forms, approach enum, path resolution rules).
`config/default.yaml` is the annotated feature-flow preset. Key fields:

```yaml
backend: claude           # LLM backend; only 'claude' is implemented
co_author: "Co-Authored-By: ..."
run_dir: .harness/runs/{run_id}   # {run_id} = <item>-<UTC ts>

stages:
  - name: my-stage
    prompt: prompts/my-stage.md   # omit for pure-check stages (no LLM call)
    schema: schemas/my-stage.json # optional: enables structured output
    tools:                        # claude --allowedTools entries
      - "Read"
      - "Bash(gh issue view {item}*)"
    consumes:                     # handoff names injected via {{handoff:NAME}}
      - prior-stage
    produces: my-stage            # writes {run_dir}/handoffs/my-stage.md on pass

    # Skip this stage if the predicate is true (no LLM call, recorded as 'skipped')
    skip_when:
      field: approach             # reads from facts.json
      equals: "null"
    # OR:
    skip_when:
      command: "git diff --quiet HEAD"   # zero exit = skip

    # Exit EXIT_DEFERRED cleanly when this predicate is true
    terminal_when:
      field: ready
      equals: "false"
      status: deferred            # status field to record in telemetry

    # Gate: stage's own structured output must satisfy this predicate to pass
    gate:
      field: status
      in: ["approved", "non_blocking_issues"]

    verify:
      checks:                     # shell commands; non-zero exit = fail
        - "git log -1 --pretty=%B | grep -q '#{item}'"
      judge:                      # LLM judge (independent cross-check)
        prompt: prompts/judge-review.md
        schema: schemas/judge.json

    on_fail: retry    # retry | defer | abort
    max_retries: 2    # attempts before giving up (only meaningful with retry)
    recover_prompt: prompts/fix.md   # run between retry attempts
    recover_tools: "Read,Write,Edit"
```

### Facts store and branching

Each stage's structured output is merged into `{run_dir}/facts.json`. All
`skip_when`, `terminal_when`, and `gate` predicates evaluate against this store.
The triage stage writes `approach: scaffold|lead-dev|junior|direct|null`; the
architect stage overwrites it if needed; each implementation stage declares
`skip_when` on the approach value it doesn't handle. No multi-handoff lookup
required — branching is data-driven with one mechanism.

## Per-repo override

Drop a repo-local config file (e.g. `.harness/config.yaml`) and pass it via `--config`:

```bash
harness/run.sh 42 --config .harness/config.yaml
```

Override individual prompts by placing same-named `.md` files next to your config
file. Path resolution checks the config file's directory first, then falls back to
the canonical `harness/prompts/` directory. Everything not overridden inherits
the canonical harness definition automatically.

Example: to use a custom triage prompt for your repo, create
`.harness/prompts/triage.md` and reference it in your config:
```yaml
stages:
  - name: triage
    prompt: prompts/triage.md   # resolved relative to .harness/config.yaml → finds .harness/prompts/triage.md
```

## Telemetry

Every stage attempt appends one JSONL line to `{run_dir}/telemetry.jsonl`:

```json
{"run_id":"42-20260609T182000Z","item":"42","stage":"triage","backend":"claude","attempt":1,"status":"passed","verify":{},"failure_reason":"","started_at":"2026-06-09T18:20:00Z","ended_at":"2026-06-09T18:20:15Z"}
```

Run directories are timestamped (`<item>-<UTC ts>`) so reruns preserve history.

## Installation

The harness is installed into a consuming repo as a symlink by `install.sh`:

```bash
./install.sh --source /path/to/llm-academy --target /path/to/your-repo
```

The symlink points at the llm-academy clone so `git pull` in llm-academy
propagates harness updates automatically. Do not edit the symlinked files — use
per-repo config and prompt overrides instead.

Note: `install.ps1` does not exist yet; harness is Linux/macOS only.
