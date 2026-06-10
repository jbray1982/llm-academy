# Verification Plugin System

## Vision

The orchestration harness currently verifies stage outputs through two mechanisms: deterministic shell checks and a holistic LLM judge. Both answer "is this implementation correct?" — neither answers "did the agent actually address what was asked?" Traceability verification fills that gap: for each requirement in the spec, does the implementation contain evidence of addressing it?

The verification plugin system makes verification extensible. A verifier plugin is a bash script with a standard I/O contract; any plugin can be opted into from stage config by declaring its key. The TVR (Traceability Verification) plugin — applying the RAG+LLM pattern from arXiv 2504.15427 to the harness context — is the first plugin and the demonstration that the architecture works.

The holistic judge and the TVR verifier are complementary, not competing. The judge catches "this is wrong" (bugs, missing error handling, pattern violations). TVR catches "this is missing" (requirements the agent silently skipped). Running both gives a stronger signal.

## User Experience

An engineer running the harness on a feature that partially misses the spec gets immediate, itemized feedback: "Requirements 2 and 4 have no evidence in the diff (confidence: 0.3, 0.2 — threshold: 0.7)." The retry agent gets those specific requirements as structured feedback, not a vague "the implementation is incomplete."

Over time, teams add new verifier plugins to `lib/plugins/` and opt into them with a one-line config declaration — no changes to the core harness machinery.

## Mechanics & Systems

- **Plugin contract**: A plugin is a bash script at `lib/plugins/<name>.sh`. It receives `(stage_record_dir, run_dir, item)` as arguments and writes a verdict JSON to stdout compatible with the schema verify.sh already emits.
- **Plugin dispatch**: `verify.sh` scans the stage config's verify block for keys matching `lib/plugins/<key>.sh` and invokes them automatically. Self-registering: dropping a new script in `lib/plugins/` and declaring its key in config is sufficient — no changes to verify.sh.
- **TVR two-stage algorithm**:
  1. Fetch spec source (issue acceptance criteria, architect handoff, or both — declared per-stage)
  2. Chunk spec into discrete requirements (one bullet per chunk); chunk implementation target (diff by default)
  3. Embed all chunks via the modular embedding backend
  4. For each spec chunk, retrieve top-N most similar implementation chunks (cosine similarity)
  5. LLM judges each spec-chunk / evidence pairing: "does this evidence address this requirement?" → confidence 0–1
  6. Apply threshold; below-threshold chunks populate `failure_reason` for retry feedback
- **Embedding backend module**: `lib/embed/` with a standard function contract (`embed_chunks`), analogous to `lib/backend/`. The OpenAI implementation ships first; future backends (Voyage, local) implement the same interface.
- **Harness config**: `embed_backend: openai` is a global key (alongside `backend: claude`). Per-stage TVR declaration: `tvr:\n  spec_source: issue`. Optional overrides: `threshold`, `target`.
- **Retry integration**: verdict `failure_reason` lists uncovered requirements by text. `executor.sh` already passes `failure_reason` as retry context; no executor changes needed.

## Open Questions

- What is the right chunking strategy for spec requirements? Acceptance criteria bullets are natural atomic units, but nested lists and long prose descriptions may need splitting heuristics.
- Should the LLM judge for TVR use the harness global `backend` or be independently configurable per-plugin?
- What top-N value for retrieval is most useful? Too few and the judge lacks context; too many and the prompt becomes noisy.
- How should TVR behave when the spec source has no structured acceptance criteria (e.g. a very short issue body)?

## Out of Scope

- A vector store or persistent embedding cache — embeddings are computed fresh each run
- Simultaneous multi-source spec (issue + handoff in one TVR run) — each stage picks one source
- Plugin versioning or a registry manifest — discovery is purely filesystem-based
- GUI / dashboard for coverage score visualization
- Embedding backend configuration per-stage (global only)
