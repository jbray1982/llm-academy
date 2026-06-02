# llm-academy — project conventions

Settled decisions for working in this repo. The harness auto-loads this file
every session.

## What this repo is

A library of **generic, project-agnostic** Claude Code skills (`skills/`) and
agents (`agents/`). Consuming repos adopt them by running `install.sh` (symlinks
the chosen definitions into their `.claude/`) and then the `learn-repo` skill
(writes their `.llm-academy/` overlays). Canonical definitions stay generic;
per-repo customization lives in overlays, never in forks. See `README.md` and
`docs/repo-customization/` for the full model.

## Adding files — does the setup script carry it over?

Whenever you add a file that is part of the **installable surface** (the things a
consuming repo is meant to receive — currently anything under `skills/` or
`agents/`), stop and ask: **will `install.sh` (and, once it exists, `install.ps1`)
carry this over?**

- **New skills** (`skills/<slug>/SKILL.md`, plus any sibling files in that skill
  directory) and **new agents** (`agents/<name>.md`) are discovered automatically
  by glob — no script change needed. This is the intended default: **propagation
  is handled by convention, not by enumeration.** The answer should usually be
  "no change needed."
- The exception to catch: a **new *kind* of installable artifact** that the
  existing globs don't match — a new top-level directory, a hooks file, a shared
  settings template, anything outside `skills/*/` and `agents/*.md`. The setup
  scripts will **silently fail to propagate it** until they're updated. When you
  add something like that, either update `install.sh` (and `install.ps1`) to carry
  it, or make a deliberate decision that it stays out — don't let it slip through
  unnoticed.
- **Docs and meta files** (`README.md`, `LICENSE`, `docs/`, `.local/`, this file)
  are **not** part of the installable surface and need no script change.

The goal isn't to touch the scripts often — it's to never let a newly added,
genuinely installable artifact silently not carry over.

## Dependency declarations

Skills/agents that depend on others declare it in YAML frontmatter
(`requires: [...]` for skills, `requires-agents: [...]` for agents). This is the
single source of truth the setup script reads to resolve a selection — there is
no separate manifest. When a skill starts driving another skill or agent, update
its frontmatter so installs pull the dependency in.

## Overlay footer convention

Every skill and agent carries a footer pointing at `.llm-academy/<slug>.md`. When
you add a new skill or agent, include the same footer so consuming repos can
overlay it. `learn-repo` writes those overlay files; canonical definitions only
reference them.
