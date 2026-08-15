# tech-debt-analysis — repo specifics

Two kinds of "source" here, with different debt profiles:

- **Prose definitions** — scan `skills/*/SKILL.md` (+ sibling files) and
  `agents/*.md` (extension `.md`). Debt is **definition drift and convention
  violations**, not dead code:
  - Skills/agents missing the overlay footer (`.llm-academy/<slug>.md` pointer).
  - Stale or incorrect `requires:` / `requires-agents:` frontmatter (the
    dependency graph install.sh reads).
  - A new installable artifact that `install.sh` does not propagate (anything
    outside `skills/*/`, `agents/*.md`, and `harness/`).
  - Project-specific assumptions leaked into a canonical definition (those
    belong in overlays).
  - Docs drift: README / harness README / CLAUDE.md lagging the actual
    installable surface (pattern of issue #25).
- **Shell code** — scan `install.sh` and `harness/**/*.sh` (extension `.sh`).
  Conventional debt categories apply here (dead functions, duplicated logic,
  unguarded edge cases). Known and already filed: no test harness for
  `harness/lib/` modules (issue #32) — dedupe against it.

Settled-decisions doc: `CLAUDE.md`. Backlog for findings: `TODOS.md`
(P1/P2/P3/Deferred); issue labels `tech-debt` / `follow-up-issue` are in use —
check open issues before filing (several debt items are already tracked:
#25, #26, #27, #28, #32).
