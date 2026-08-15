# Repo Profile

_Written by /learn-repo on 2026-06-11. Re-run to refresh; hand edits are
respected (this skill surfaces a diff before overwriting)._

- Language: Markdown (skill/agent definitions, docs) + Bash (`install.sh`,
  `harness/**/*.sh`). The prose definitions are still the primary "source";
  the harness is the substantial shell codebase.
- Build: none.
- Test: none — no automated test infrastructure (tracked as issue #32 for the
  harness shell modules). Closest verifications: `bash -n` on changed scripts,
  running `./install.sh` against a scratch target repo, and a `harness/run.sh`
  dry run against a real issue.
- Source layout — three installable artifact kinds:
  - `skills/<slug>/SKILL.md` (+ sibling files) — glob-discovered by install.sh.
  - `agents/<name>.md` — glob-discovered by install.sh.
  - `harness/` — the headless pipeline runner (run.sh, lib/, prompts/,
    schemas/, config/), symlinked **wholesale** into the consuming repo's root
    by `install_harness()` in install.sh (not under `.claude/`).
  `docs/<feature>/` holds vision docs + numbered specs; `handoffs/` holds
  review handoffs; `.local/` is private scratch (gitignored).
- Test layout: n/a.
- Default branch: main.

## Conventions

This repo is **self-hosting**: it installs its own skills/agents into `.claude/`
via symlinks (dogfooding the adoption model it ships). The `.claude/` symlinks
must stay out of version control.

Load-bearing rules (full text in `CLAUDE.md`):

- **Installable surface = `skills/*/` + `agents/*.md` + `harness/`.** New
  skills/agents propagate by glob — no `install.sh` change needed. A *new kind*
  of artifact (new top-level dir, hooks file, shared settings) does NOT
  propagate until `install.sh` (and the future `install.ps1`, issue #3) is
  taught about it — the harness was exactly this case and got its own
  `install_harness()` step.
- **Canonical definitions stay generic.** Per-repo customization lives in
  `.llm-academy/` overlays for skills/agents, and in a repo-local
  `.harness/config.yaml` (passed via `--config`) + override prompt files for
  the harness — never in forks or edits to symlinked files.
- **Dependency declarations** live in frontmatter: `requires: [...]` for
  skills, `requires-agents: [...]` for agents. This is the single source
  install.sh reads — there is no separate manifest.
- **Overlay footer convention.** Every skill and agent carries a footer
  pointing at `.llm-academy/<slug>.md`. New skills/agents must include it.
- **Branch naming:** `feature/issue-<number>`.
- **Co-Authored-By:** `Claude Fable 5 <noreply@anthropic.com>` (current model;
  older commits carry Opus/Sonnet lines).
- **Backlog:** `TODOS.md` (P1/P2/P3/Deferred) for items too small for an issue;
  most work is promoted to GitHub issues. Labels in use: `tech-debt`,
  `follow-up-issue`. Named design surface registered in `FEATURE_LOG.md`;
  feature specs live under `docs/<feature>/`.
- **Harness runs** write to `.harness/runs/` (gitignored) with JSONL telemetry.
