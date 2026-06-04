# Repo Profile

_Written by /learn-repo on 2026-06-03. Re-run to refresh; hand edits are
respected (this skill surfaces a diff before overwriting)._

- Language: Markdown only — no compiled code. The "source" is the prose skill and
  agent definitions themselves.
- Build: none.
- Test: none in the conventional sense. The closest thing to a test is running
  `./install.sh` against a scratch target repo and confirming symlinks/overlays
  wire up correctly (see the install.sh verification notes in session memory).
- Source layout: `skills/<slug>/SKILL.md` (+ sibling files) and `agents/<name>.md`.
  These two trees are the **installable surface** — everything a consuming repo
  receives. `docs/` holds feature specs; `.local/` is private scratch (gitignored).
- Test layout: n/a.
- Default branch: main.

## Conventions

This repo is **self-hosting**: it installs its own skills/agents into `.claude/`
via symlinks (dogfooding the adoption model it ships). The `.claude/` symlinks
point back into this same repo and must stay out of version control — add
`.claude/` to `.gitignore` if not already ignored.

Load-bearing rules (full text in `CLAUDE.md`):

- **Installable surface = `skills/*/` + `agents/*.md`.** New skills/agents
  propagate by glob — no `install.sh` change needed. A *new kind* of artifact (new
  top-level dir, hooks file, shared settings) does NOT propagate until `install.sh`
  (and the future `install.ps1`) is taught about it — catch these.
- **Canonical definitions stay generic.** Per-repo customization lives in
  `.llm-academy/` overlays, never in forks or in edits to the symlinked files.
- **Dependency declarations** live in frontmatter: `requires: [...]` for skills,
  `requires-agents: [...]` for agents. This is the single source install.sh reads
  to resolve a selection — there is no separate manifest.
- **Overlay footer convention.** Every skill and agent carries a footer pointing
  at `.llm-academy/<slug>.md`. New skills/agents must include the same footer.
- **Branch naming:** `feature/issue-<number>`.
- **Co-Authored-By:** `Claude Opus 4.8 <noreply@anthropic.com>`.
- **Backlog:** `TODOS.md` (P1/P2/P3/Deferred). Named design surface registered in
  `FEATURE_LOG.md`. Feature specs live under `docs/<feature>/`.
