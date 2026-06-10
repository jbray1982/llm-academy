# Spec 001 — Verification Plugin System MVP

## Goal

Implement a formal verifier plugin architecture for the orchestration harness, with the TVR (Traceability Verification) plugin as the first working example. The MVP demonstrates that:
1. A stage can opt into TVR verification with a minimal config declaration
2. TVR's per-requirement confidence scores produce actionable, named retry feedback
3. The embedding module interface is clean enough that a second backend can be added without touching TVR or `verify.sh`

## In Scope

- `lib/embed/embed.sh` — embedding dispatch (analog to `lib/backend/backend.sh`)
- `lib/embed/embed-openai.sh` — OpenAI embeddings implementation
- `lib/plugins/tvr.sh` — TVR verifier plugin
- `lib/verify.sh` — plugin dispatch: scan stage config for keys matching `lib/plugins/<key>.sh` and invoke
- `harness/config/default.yaml` — add `embed_backend: openai` global key
- Verdict JSON schema extension — `coverage` array field, `tvr_verdict` field

## Out of Scope (for MVP)

- A second embed backend (Voyage, local, or other)
- A second verifier plugin (test-coverage, lint, or other)
- Per-stage `embed_backend` override (global only)
- `spec_source: both` (issue AND handoff simultaneously)
- Embedding cache or vector store
- Chunking beyond: one-bullet-per-chunk for spec, one-file-hunk-per-chunk for diff

## Data Model

**Embed backend contract** (`lib/embed/embed.sh` sources the active backend, which must implement):
```bash
embed_chunks "$chunks_json"   # chunks_json: JSON array of strings
                               # stdout: JSON array of float arrays
```

**TVR stage config** (under `verify:`):
```yaml
tvr:
  spec_source: issue    # required: issue | handoff
  threshold: 0.7        # optional, default 0.7
  target: diff          # optional: diff | handoff, default diff
```

**Global harness config** (alongside `backend:`):
```yaml
embed_backend: openai   # required when any stage uses tvr:
```

**Verdict JSON** (extended schema, fully backward-compatible — new fields are additive):
```json
{
  "passed": true,
  "checks": [],
  "judge_verdict": null,
  "judge_reason": null,
  "tvr_verdict": "pass",
  "coverage": [
    { "requirement": "Acceptance criterion text", "confidence": 0.92, "covered": true },
    { "requirement": "Another criterion",         "confidence": 0.41, "covered": false }
  ],
  "failure_reason": "Requirements not covered by implementation: [criterion text]"
}
```

## Behaviors

1. **Plugin dispatch** — `verify.sh` reads the stage config's verify block. For each key present, it checks whether `lib/plugins/<key>.sh` exists. If so, it invokes the plugin with `(stage_record_dir, run_dir, item)` and parses stdout as a verdict JSON. Any plugin `passed: false` makes the overall verdict `passed: false`. Plugin failures do not suppress the judge verdict (both run independently).

2. **Spec retrieval** — For `spec_source: issue`: run `gh issue view {item}` and extract acceptance criteria bullets (lines under an "Acceptance Criteria" or "AC" heading, or `- [ ]` checkbox lines anywhere in the body). For `spec_source: handoff`: read the architect handoff file from the run directory.

3. **Implementation retrieval** — For `target: diff` (default): run `git diff HEAD` and split into per-file hunks. Each hunk is a chunk. For `target: handoff`: read the stage's output handoff.

4. **Embedding** — Source `lib/embed/embed.sh` which resolves the active backend from the harness global `embed_backend`. Call `embed_chunks` with the JSON array of spec chunks and separately with the JSON array of diff chunks.

5. **Retrieval** — For each spec chunk embedding, compute cosine similarity against all diff chunk embeddings. Select top-3 diff chunks.

6. **LLM judgment** — Prompt the harness LLM backend: "Given this requirement: [spec chunk text] and this implementation evidence: [top-3 diff chunks], does the evidence address the requirement? Respond with a confidence score 0.0–1.0 and a one-sentence reason." Parse confidence from structured output.

7. **Threshold application** — Any spec chunk with `confidence < threshold` is marked `covered: false`. If any chunk is uncovered, `tvr_verdict: "fail"` and `passed: false`. `failure_reason` names the uncovered requirement texts.

8. **Missing API key** — If `OPENAI_API_KEY` is absent when the OpenAI backend is invoked, `tvr.sh` emits `passed: false` with `failure_reason: "TVR skipped: OPENAI_API_KEY not set"` rather than crashing or silently passing.

9. **No acceptance criteria found** — If the spec source yields zero extractable chunks, `tvr.sh` emits `passed: true` with `tvr_verdict: null` and a warning in `failure_reason` (advisory, not blocking). This prevents a malformed issue body from blocking the pipeline.

## Integration Points

| Component | Change |
|---|---|
| `lib/verify.sh` | Plugin dispatch block added after existing checks + judge logic |
| `harness/config/default.yaml` | New `embed_backend: openai` global key |
| `lib/backend/backend.sh` | Used by `tvr.sh` for LLM judgment — no changes needed |
| `lib/config.sh` | Must surface `embed_backend` global value to calling scripts |

## Extension Hooks

- `lib/embed/` — new backends implement `embed_chunks`; `embed.sh` routes by `$EMBED_BACKEND`
- `lib/plugins/` — new plugins are self-registering via filesystem discovery; zero verify.sh changes required

## Acceptance Criteria

- [ ] `embed_backend: openai` is read from global harness config and available to `lib/embed/embed.sh`
- [ ] `lib/embed/embed-openai.sh` implements `embed_chunks` using the OpenAI embeddings API; requires `OPENAI_API_KEY`
- [ ] `lib/plugins/tvr.sh` accepts `(stage_record_dir, run_dir, item)` and writes verdict JSON to stdout
- [ ] Adding `tvr:\n  spec_source: issue` to a stage's verify block causes TVR to run for that stage
- [ ] A second plugin script dropped in `lib/plugins/` is automatically dispatched when its key appears in a stage verify block — no `verify.sh` edit needed
- [ ] TVR verdict includes a `coverage` array with per-requirement confidence scores and `covered` booleans
- [ ] When any requirement's confidence is below threshold, `passed: false` and `failure_reason` names the uncovered requirements
- [ ] Missing `OPENAI_API_KEY` produces an informative failure, not a crash or silent pass
- [ ] Zero extractable acceptance criteria is advisory (does not block the stage)
- [ ] End-to-end: running the harness on a real issue with `tvr: {spec_source: issue}` produces a coverage report that can be manually inspected for plausibility
