# tech-debt-analysis — repo specifics

This repo has **no compiled code** — the "source" is prose. Reframe the standard
scan categories accordingly:

- Scan scope: `skills/*/SKILL.md` (+ sibling files) and `agents/*.md`. Extension:
  `.md`.
- Relevant debt categories here are about **definition drift and convention
  violations**, not dead code or coupling:
  - Skills/agents missing the overlay footer (`.llm-academy/<slug>.md` pointer).
  - Stale or incorrect `requires:` / `requires-agents:` frontmatter (the
    dependency graph install.sh reads).
  - A new installable artifact that `install.sh` does not propagate (a new kind
    of file outside `skills/*/` and `agents/*.md`).
  - Divergence between a generic canonical definition and project-specific
    assumptions that leaked into it (those belong in overlays, not the canonical).
- Settled-decisions doc: `CLAUDE.md`. Backlog for findings: `TODOS.md`.
