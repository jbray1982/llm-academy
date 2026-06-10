# Harness configuration reference

The harness is driven entirely by a single YAML file. `default.yaml` in this
directory is the canonical feature-flow preset. Pass a different file via
`--config` to override the whole pipeline, or use per-repo prompt files next to
your config to override individual stages (see [Per-repo overrides](#per-repo-overrides)).

---

## Global fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backend` | string | `claude` | LLM backend. Only `claude` is implemented. |
| `co_author` | string | `Co-Authored-By: Claude <noreply@anthropic.com>` | Injected into commit messages via `{co_author}` in prompts. |
| `run_dir` | string | `.harness/runs/{run_id}` | Directory for this run's handoffs, facts store, and telemetry. Tokens: `{run_id}` (= `<item>-<UTC ts>`), `{item}`. |

---

## Stage fields

Each entry under `stages:` accepts the following fields.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Stage identifier. Used in telemetry and handoff filenames. |
| `prompt` | path | no | Prompt template. Omit for pure-check stages (no LLM call). |
| `schema` | path | no | JSON Schema for structured output. When present the backend is asked for structured JSON; the result is merged into the facts store. |
| `tools` | string[] | no | `--allowedTools` entries for the claude CLI. Supports `{item}` substitution (e.g. `"Bash(gh issue view {item}*)"`). JSON array format. |
| `consumes` | string[] | no | Handoff names whose content is injected into the prompt via `{{handoff:NAME}}`. Files are read from `{run_dir}/handoffs/`. |
| `produces` | string | no | If set and the stage passes, writes a handoff document to `{run_dir}/handoffs/<produces>.md`. |
| `skip_when` | predicate | no | Skip the stage (no LLM call, recorded as `skipped`) when the predicate is true. |
| `terminal_when` | predicate | no | Exit the pipeline with `EXIT_DEFERRED` when the predicate is true after a successful backend call. |
| `gate` | predicate | no | Stage's own structured output must satisfy this predicate to count as passed. |
| `verify.checks` | string[] | no | Shell commands run after the backend call. Any non-zero exit fails the stage. |
| `verify.judge` | object | no | LLM judge for independent cross-check. Fields: `prompt` (path), `schema` (path). A broken judge is a hard failure — it does not silently pass. |
| `on_fail` | string | `abort` | What to do when the stage fails: `retry`, `defer`, or `abort`. |
| `max_retries` | int | `1` | Maximum number of retries (total attempts = `max_retries + 1`). Only meaningful with `on_fail: retry`. |
| `recover_prompt` | path | no | Prompt assembled and invoked between retry attempts. Its structured output is merged into the facts store so the next attempt has the feedback. |
| `recover_tools` | string[] | no | Tools allowed for the recover invocation. Same `{item}` substitution as `tools`. |
| `backend` | string | global `backend` | Per-stage backend override. |

### Path resolution

`prompt`, `schema`, `recover_prompt`, and judge `prompt`/`schema` paths are
resolved in this order:

1. `<config-file-directory>/<value>` — repo-local override wins.
2. `<harness-directory>/prompts/<basename>` (or `schemas/`) — canonical fallback.

This means you can override `prompts/triage.md` for your repo by placing a file
at `.harness/prompts/triage.md` (next to your `.harness/config.yaml`) without
touching the canonical harness.

---

## Predicate reference

`skip_when`, `terminal_when`, and `gate` all accept the same predicate shapes.
Predicates read from `{run_dir}/facts.json` (the accumulated structured output of
all prior stages). A missing or `null` fact is treated as the string `"null"`.

### Field equals

```yaml
skip_when:
  field: approach
  equals: "null"
```

True when `facts.approach == "null"`. Add `negate: true` to invert:

```yaml
skip_when:
  field: approach
  negate: true
  equals: "scaffold"    # skip when approach is anything other than "scaffold"
```

### Field in set

```yaml
gate:
  field: status
  in:
    - "approved"
    - "non_blocking_issues"
```

True when `facts.status` is any value in the list. Supports `negate`:

```yaml
skip_when:
  field: approach
  negate: true
  in:
    - "scaffold"
    - "scaffold-lead"   # skip unless approach is scaffold or scaffold-lead
```

### Shell command

```yaml
skip_when:
  command: "git diff --quiet HEAD"   # zero exit = predicate true
```

Runs in a subshell. Zero exit = true (skip/trigger). Non-zero = false (don't
skip/trigger). Useful for checking working-tree state without touching the facts
store.

### terminal_when status field

`terminal_when` supports an extra `status` field recorded in telemetry on exit:

```yaml
terminal_when:
  field: ready
  equals: "false"
  status: deferred
```

---

## Approach enum

The `approach` field (written by the triage or architect stage) controls which
implementation stages run. Each stage uses `skip_when` to opt out when the
approach doesn't apply to it.

| Value | Meaning | Stages that run |
|-------|---------|-----------------|
| `scaffold` | Lead scaffolds interfaces and a manifest; junior implements all stubs. | scaffold-lead, scaffold-junior |
| `scaffold-lead` | Lead scaffolds and implements the complex/high-risk parts; junior fills remaining stubs. | scaffold-lead, scaffold-junior, implement-lead |
| `lead-dev` | Too complex for junior; lead implements everything directly. | implement-lead |
| `junior` | Simple enough for junior to implement directly. | implement-junior |
| `direct` | Architect implements directly (spike or experimental). | implement-direct |
| `decision-required` | Product ambiguity; human decision required. Pipeline defers. | *(none — pipeline exits 75)* |

The `scaffold-lead` approach runs `implement-lead` **after** `scaffold-junior`
completes, so lead sees what junior already filled in and implements only the
complex bodies flagged in the scaffold manifest.

---

## Facts store

Every stage's structured JSON output is merged into `{run_dir}/facts.json` using
last-writer-wins semantics. Later stages read this store via `skip_when`, `gate`,
and `terminal_when` predicates — no custom inter-stage wiring needed.

Example after triage and architect stages:

```json
{
  "ready": "true",
  "approach": "scaffold-lead",
  "reasoning": "...",
  "requires_product_review": "false"
}
```

---

## Per-repo overrides

To customise the pipeline for a specific repo without forking the harness:

1. Create a config file in your repo (e.g. `.harness/config.yaml`).
2. Copy and edit only the stages you want to change. Inherit the rest from
   `default.yaml` by running the harness with your config.
3. Place prompt overrides next to your config file — they are resolved before
   the canonical `harness/prompts/` fallback.

```bash
harness/run.sh 42 --config .harness/config.yaml
```

You can also pass `--config` to a completely different file to run an entirely
different pipeline (e.g. a documentation-only or review-only pipeline) against
the same harness runtime.
