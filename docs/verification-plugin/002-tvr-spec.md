# Spec 002 — TVR (Traceability Verification) Plugin

## Goal

Implement TVR as the second verifier plugin, applying the RAG+LLM pattern from arXiv 2504.15427: for each requirement in the spec, retrieve the most semantically similar implementation evidence and have an LLM judge whether the evidence addresses it. TVR answers the question neither checks nor the judge does — "did the agent actually address what was asked?" — and, as the second plugin through the contract defined in spec 001, proves the framework generalizes: if the contract is clean, TVR requires zero changes to `verify.sh`.

## In Scope

- `harness/lib/embed.sh` — embedding dispatch (flat-convention analog of `lib/backend.sh`)
- `harness/lib/embed-openai.sh` — OpenAI embeddings implementation (analog of `lib/backend-claude.sh`)
- `harness/lib/plugins/tvr.sh` — the TVR verifier plugin
- `harness/config/default.yaml` — `embed_backend: openai` global key; `tvr:` opted into the review stage's verify block
- Preflight additions in `config.sh` for TVR's runtime dependencies

## Out of Scope

- A second embed backend (Voyage, local, or other)
- Per-stage `embed_backend` override (global only)
- `spec_source: both` (issue AND handoff simultaneously)
- Embedding cache or vector store
- Chunking beyond: one-bullet-per-chunk for spec, one-file-hunk-per-chunk for diff
- Any changes to `verify.sh`, `executor.sh`, or the verdict schema — if TVR needs them, that is a spec 001 contract defect to fix there

## Data Model

**Embed backend contract** (`lib/embed.sh` sources `lib/embed-$EMBED_BACKEND.sh`, which must implement):

```bash
embed_chunks "$chunks_json"   # chunks_json: JSON array of strings
                              # stdout: JSON array of float arrays, same order/length
```

The OpenAI implementation uses `text-embedding-3-small`, batches all chunks into one API request (chunked into batches of 100 if needed), and truncates any chunk exceeding ~8000 tokens (the model's 8191 limit) with a stderr warning.

**TVR stage config** (under `verify:`; dispatched by spec 001's framework):

```yaml
tvr:
  spec_source: issue    # required: issue | handoff
  threshold: 0.7        # optional, default 0.7
  target: diff          # optional: diff | handoff, default diff
  handoff: architect    # required when spec_source/target is handoff: which named handoff
```

**Global harness config** (alongside `backend:`):

```yaml
embed_backend: openai   # required when any stage declares tvr:
```

**TVR verdict** (lives at `plugins.tvr` in the composed verdict — per spec 001, no top-level fields):

```json
{
  "passed": false,
  "coverage": [
    { "requirement": "Acceptance criterion text", "confidence": 0.92, "applicable": true,  "covered": true },
    { "requirement": "Run manually end-to-end",   "confidence": 0.10, "applicable": false, "covered": null },
    { "requirement": "Another criterion",          "confidence": 0.41, "applicable": true,  "covered": false }
  ],
  "reason": "Requirements not covered by implementation: [Another criterion]"
}
```

## Behaviors

1. **Spec retrieval** — For `spec_source: issue`: `gh issue view {item} --json body --jq .body`, then extract requirement bullets: lines matching `- [ ]` / `- [x]` / `- [X]` checkboxes anywhere in the body, or plain bullets under an "Acceptance Criteria" or "AC" heading. Checked boxes are included — issue ACs get ticked over time and remain requirements. Top-level bullets only; nested sub-bullets stay attached to their parent chunk. For `spec_source: handoff`: read the named handoff (config `handoff:` key) from the run directory; chunk by top-level markdown bullets.

2. **Implementation retrieval** — For `target: diff` (default): `git diff HEAD`, split into per-file hunks; each hunk is a chunk. For `target: handoff`: read the named handoff from the run directory. Note: a stage's own `produces` handoff is written only after verify passes, so `target: handoff` can only reference handoffs from earlier stages — the config names which one.

3. **Embedding** — source `lib/embed.sh`, resolve `EMBED_BACKEND` from the harness global `embed_backend`, call `embed_chunks` once for spec chunks and once for implementation chunks.

4. **Retrieval** — for each spec chunk embedding, cosine similarity against all implementation chunk embeddings (jq/awk — no new runtime dependency); select top-3.

5. **Judgment — one batched call** — a single `backend_invoke` against the stage backend (from `stage_record_dir/backend`) with all requirement/evidence pairings and a structured-output schema returning, per requirement: `confidence` (0.0–1.0), `applicable` (boolean — false for requirements that cannot be evidenced by code changes: process steps, manual verification, out-of-repo work), and a one-sentence `reason`. One call instead of N: cheaper, faster, and a single parse-failure surface.

6. **Threshold application** — applicable requirements with `confidence < threshold` get `covered: false`. Any uncovered applicable requirement → `passed: false`, with `reason` naming the uncovered requirement texts (this feeds `failure_reason` and the executor's existing retry context — no executor changes). Non-applicable requirements are listed in `coverage` with `covered: null` and never count against the threshold.

7. **Zero spec chunks** — advisory, not blocking: `passed: true`, empty `coverage`, and a warning ("TVR: no extractable requirements in <source>") surfaced via the spec 001 `warnings` channel. A malformed issue body must not block the pipeline.

8. **Zero implementation chunks** (empty diff / empty handoff) — `passed: false` with reason "TVR: no implementation changes found to verify against". (In the default pipeline the review stage's `skip_when: git diff --quiet HEAD` makes this unreachable; the behavior is defined for configs without that guard.)

9. **Missing dependencies** — if `OPENAI_API_KEY` is unset or `curl` is missing when the OpenAI backend is invoked, emit `passed: false` with an informative reason — never a crash with unparseable output, never a silent pass. Additionally, `config_load` preflights both (plus `embed_backend` being set) whenever any stage declares `tvr:`, so the common case fails at load time, before any LLM spend.

10. **Failure-path parse errors** — if the embeddings API call fails or the batched judgment returns unparseable output, `passed: false` with the upstream error summarized in `reason` (spec 001's never-silently-pass rule applies regardless).

## Integration Points

| Component | Change |
|---|---|
| `harness/lib/embed.sh`, `harness/lib/embed-openai.sh` | New — embedding dispatch + OpenAI implementation |
| `harness/lib/plugins/tvr.sh` | New — dispatched automatically by spec 001's framework |
| `harness/config/default.yaml` | `embed_backend: openai` global; `tvr: {spec_source: issue}` added to the review stage's verify block (its `on_fail: retry` + `recover_prompt: fix.md` loop consumes TVR's named gaps as fix feedback) |
| `harness/lib/config.sh` | Conditional preflight: `OPENAI_API_KEY` / `curl` / `embed_backend` when any stage declares `tvr:` |
| `harness/lib/verify.sh`, `harness/lib/executor.sh` | **No changes** — this is the framework-generalization proof |

As-built note (#18, landed before this spec's implementation): plugin discovery is now manifest-based, so `tvr` must additionally be declared in `harness/lib/plugins/manifest.yaml` (a declared-but-missing script is a preflight error, which is why #18 shipped the manifest with only `judge`).

## Notes for consuming repos

TVR sends spec text and diff content to the configured embedding provider (OpenAI by default) and requirement/evidence text to the LLM backend. Repos with private code should know this before opting in — document in `harness/config/README.md` alongside the `embed_backend` key.

TVR runs on every verify attempt; with the review stage's `max_retries: 2` that is up to three embedding+judgment rounds per issue. The batched judgment call keeps this to one LLM call per attempt plus one embeddings call.

## Acceptance Criteria

- [ ] `embed_backend: openai` is read from global harness config and resolves `lib/embed-openai.sh`
- [ ] `lib/embed-openai.sh` implements `embed_chunks` (batched request, truncation rule) using the OpenAI embeddings API
- [ ] `lib/plugins/tvr.sh` follows the spec 001 plugin contract: `(stage_record_dir, run_dir, item, co_author)` in, verdict JSON on stdout, config read from `stage_record_dir/tvr`
- [ ] Adding `tvr:\n  spec_source: issue` to a stage's verify block causes TVR to run for that stage — with zero changes to `verify.sh` or `executor.sh` (framework-generalization proof)
- [ ] TVR verdict includes a `coverage` array with per-requirement `confidence`, `applicable`, and `covered`
- [ ] Checked (`- [x]`) and unchecked checkboxes are both extracted as requirements
- [ ] Non-code-addressable requirements are judged `applicable: false` and do not fail the stage
- [ ] When any applicable requirement is below threshold, `passed: false` and the reason names the uncovered requirements verbatim
- [ ] Missing `OPENAI_API_KEY` fails informatively at `config_load` when a stage declares `tvr:`, and at runtime as a backstop
- [ ] Zero extractable requirements is advisory (warning, not a block); zero implementation chunks is a failure with a named reason
- [ ] End-to-end: a harness run with TVR on the review stage produces a coverage report on a real issue that is plausible under manual inspection, and an artificially-omitted requirement shows up uncovered
