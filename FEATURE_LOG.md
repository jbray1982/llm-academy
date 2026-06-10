# Feature Log

Registry of every named feature, mechanic, or cross-cutting system in this
project's design surface. See the `/feature-log` skill for status/conviction
vocabulary and entry format.

Format: `- **[conviction | status]** **Name** — one-line description.`

- **[must-have | defined]** **Orchestration Harness** — generic headless single-work-item pipeline runner ("feature-flow, headless + configurable + instrumented + pluggable"); generalizes sunken-spires' inner batch-process pipeline.
  Surfaced: feature-spec session, 2026-06-08. See: docs/orchestration-harness/vision.md, docs/orchestration-harness/001-mvp-spec.md, #11.

- **[must-have | defined]** **Verification Plugin System** — formal verifier plugin architecture for the harness; TVR (traceability verification via embeddings + LLM judgment per requirement) is the first plugin; catches "we built the wrong thing" misses that the holistic judge doesn't. Inspired by arXiv 2504.15427.
  Surfaced: feature-spec session, 2026-06-09. See: docs/verification-plugin/vision.md, docs/verification-plugin/001-mvp-spec.md, #15, #16.
