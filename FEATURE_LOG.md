# Feature Log

Registry of every named feature, mechanic, or cross-cutting system in this
project's design surface. See the `/feature-log` skill for status/conviction
vocabulary and entry format.

Format: `- **[conviction | status]** **Name** — one-line description.`

- **[must-have | live]** **Orchestration Harness** — generic headless single-work-item pipeline runner ("feature-flow, headless + configurable + instrumented + pluggable"); generalizes sunken-spires' inner batch-process pipeline.
  Surfaced: feature-spec session, 2026-06-08. See: docs/orchestration-harness/vision.md, docs/orchestration-harness/001-mvp-spec.md, #11, PR #14.

- **[must-have | partially-live]** **Verification Plugin System** — formal verifier plugin architecture for the harness. Ships in two iterations: the existing LLM judge migrated as the first plugin (behavior-preserving refactor that defines and validates the contract, #15 — shipped in PR #17), then TVR (traceability verification via embeddings + batched LLM judgment per requirement, #16) as the second plugin and the framework-generalization proof; TVR catches "we built the wrong thing" misses that the holistic judge doesn't. Inspired by arXiv 2504.15427. Vision amended 2026-06-09: plugin discovery moves from pure-filesystem to a declared manifest/registry to support multi-developer plugin contribution.
  Surfaced: feature-spec session, 2026-06-09; restructured judge-first 2026-06-09. See: docs/verification-plugin/vision.md, docs/verification-plugin/001-mvp-spec.md, docs/verification-plugin/002-tvr-spec.md, #15, #16, PR #17.
