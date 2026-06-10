# Verification Plugin System

## Vision

The orchestration harness currently verifies stage outputs through two mechanisms baked into `verify.sh`: deterministic shell checks and a holistic LLM judge. The verification plugin system makes verification extensible: a verifier plugin is a bash script with a standard I/O contract, opted into from a stage's `verify:` block by declaring its key. Declaring a script in the plugin manifest and opting into its key in config is sufficient — no changes to the core harness machinery.

The system ships in two iterations:

1. **Framework + judge migration** (#15). The existing LLM judge becomes the first plugin. This is deliberately a behavior-preserving refactor: the plugin contract is defined against a mechanism that already works, so "the framework is correct" is verifiable as equivalence with current behavior. The judge exercises every hard part of the contract — per-plugin config delivery, prompt assembly, backend invocation, path resolution, and the never-silently-pass rule — before any new functionality lands.
2. **TVR as the second plugin** (#16). TVR (Traceability Verification — applying the RAG+LLM pattern from arXiv 2504.15427 to the harness context) answers a question neither checks nor the judge does: "did the agent actually address each requirement in the spec?" As the second plugin through the contract, it also surfaces any accidental coupling to judge-specific behavior.

The holistic judge and the TVR verifier are complementary, not competing. The judge catches "this is wrong" (bugs, missing error handling, pattern violations). TVR catches "this is missing" (requirements the agent silently skipped). Running both gives a stronger signal.

## User Experience

An engineer's existing harness config keeps working unchanged — `verify: judge:` is already plugin-shaped, and after #15 it simply dispatches through the plugin framework instead of inline verify.sh code.

After #16, an engineer running the harness on a feature that partially misses the spec gets immediate, itemized feedback: "Requirements 2 and 4 have no evidence in the diff (confidence: 0.3, 0.2 — threshold: 0.7)." The retry agent gets those specific requirements as structured feedback, not a vague "the implementation is incomplete."

Over time, teams register new verifier plugins in the manifest and opt into them with a one-line config declaration — no changes to the core harness machinery.

## Mechanics & Systems

- **Plugin contract**: A plugin is a bash script (harness-shipped plugins live at `lib/plugins/<name>.sh` under `harness/`; third-party scripts may live anywhere a manifest can reach). It is invoked with `(stage_record_dir, run_dir, item, co_author)` and writes a verdict JSON object to stdout: `{"passed": true|false, ...}` plus any plugin-specific fields. Its own config (the value of its key in the stage's `verify:` block) is provided as JSON at `stage_record_dir/<name>`; the stage backend is at `stage_record_dir/backend`. Plugins may source harness libs (`prompt.sh`, `backend.sh`, `result.sh`) — they are part of the harness tree, not hermetic.
- **Plugin dispatch**: `verify.sh` iterates the keys of the stage's `verify:` block. `checks` is the one reserved built-in; every other key is resolved through a plugin manifest (see Manifest declaration below). A verify key not declared in any manifest is a config preflight error (fail at load, never silently skip verification).
- **Manifest declaration**: plugins are declared in `lib/plugins/manifest.yaml` (harness-shipped) or at `lib/plugins/manifest.yaml` relative to a consuming repo's config file's directory (extends/overrides the harness manifest — config-dir wins on name conflicts). Each entry maps a plugin name to its script path (relative to the manifest's own directory, so third-party plugins can live anywhere). `config_load` validates at preflight that every declared script exists and is executable, and that every verify key in the config is declared in a manifest; the unknown-key error message lists the available plugin names.
  - As-built (#18): the shipped harness manifest declares only `judge` — diverged from the issue #18 sketch, which declared both `judge` and `tvr`; a declared-but-missing script is a preflight error, so `tvr` enters the manifest when #16 ships `lib/plugins/tvr.sh`.
- **Verdict composition**: overall `passed` = all checks exit 0 AND every declared plugin reports `passed: true`. Per-plugin results are namespaced in the verdict JSON under `plugins: {<name>: {...}}` — no plugin owns top-level fields, so new plugins never force a schema change. A plugin that crashes or emits unparseable stdout is a verify FAILURE, never a silent pass (generalizing the existing judge rule). `failure_reason` concatenates all failing sources.
- **Judge plugin** (#15): the current inline judge logic — prompt/schema path resolution, prompt_assemble, backend_invoke, structured verdict extraction — moves into `lib/plugins/judge.sh` verbatim in behavior. Existing `verify: judge:` config keys work unchanged.
- **TVR two-stage algorithm** (#16):
  1. Fetch spec source (issue acceptance criteria or a named handoff — declared per-stage)
  2. Chunk spec into discrete requirements (one bullet per chunk); chunk implementation target (diff by default)
  3. Embed all chunks via the modular embedding backend
  4. For each spec chunk, retrieve top-N most similar implementation chunks (cosine similarity)
  5. One batched LLM call judges all spec-chunk / evidence pairings: confidence 0–1 each, plus an `applicable` flag for requirements that can't be evidenced by code (process steps, manual tests)
  6. Apply threshold; below-threshold applicable chunks populate `failure_reason` for retry feedback
- **Embedding backend module** (#16): `lib/embed.sh` dispatching to `lib/embed-<backend>.sh` with a standard function contract (`embed_chunks`), following the flat `lib/backend.sh` / `lib/backend-claude.sh` convention. The OpenAI implementation ships first; future backends (Voyage, local) implement the same interface.
- **Harness config**: `embed_backend: openai` is a global key (alongside `backend: claude`). Per-stage TVR declaration: `tvr:\n  spec_source: issue`. Optional overrides: `threshold`, `target`.
- **Retry integration**: verdict `failure_reason` lists uncovered requirements by text. `executor.sh` already passes `failure_reason` as retry context; no executor changes needed for retry. (The executor does change in #15 to pass the full `verify:` block into the stage record — today it forwards only `checks` and `judge`.)

## Open Questions

- What is the right chunking strategy for spec requirements? Acceptance criteria bullets are natural atomic units, but nested lists and long prose descriptions may need splitting heuristics.
- What top-N value for retrieval is most useful? Too few and the judge lacks context; too many and the prompt becomes noisy. (MVP: fixed at 3.)
- Should `checks` itself eventually become a plugin, making verify.sh a pure dispatcher? Deferred — checks are the zero-dependency base layer and migrating them adds risk without proving anything judge+TVR don't.

## Resolved Questions

- **Which backend does a plugin's LLM call use?** The stage's backend, read from `stage_record_dir/backend`. Already plumbed; no new config knob.
- **How does TVR behave with no extractable acceptance criteria?** Advisory: `passed: true` with a warning in a `warnings` field (not `failure_reason`) — a malformed issue body must not block the pipeline.

## Out of Scope

- A vector store or persistent embedding cache — embeddings are computed fresh each run
- Simultaneous multi-source spec (issue + handoff in one TVR run) — each stage picks one source
- Plugin versioning — the manifest entry is where `version`, `author`, `requires`, etc. will live when multi-developer contribution arrives, but none of that is in scope now
- GUI / dashboard for coverage score visualization
- Embedding backend configuration per-stage (global only)
- Migrating `checks` into the plugin framework
