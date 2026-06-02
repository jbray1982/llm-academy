# 001 — Repo Customization MVP

## Goal

Prove the drift-cure end-to-end on one consuming repo: install selected
llm-academy skills/agents as symlinks, customize them via `.llm-academy/`
overlay files written by a `learn-repo` skill, and confirm the canonical
definitions read those overlays — all without forking a single canonical file.
When this works, a `git pull` in the llm-academy clone updates the consuming
repo's skills with no merge work and overlays untouched.

## In Scope

- **Overlay footer convention** added to every canonical skill (`skills/*/SKILL.md`)
  and agent (`agents/*.md`).
- **`requires:` / `requires-agents:` frontmatter** added to every skill and agent
  that depends on others.
- **`install.sh`** (bash): selector, dependency resolution, symlink/copy install,
  convention-file stub offer, headless slug args.
- **`learn-repo` skill** (`skills/learn-repo/SKILL.md`): reads the repo, writes
  `.llm-academy/repo.md` and per-skill overlays.
- **Dogfood pass**: run the full flow against one real consuming repo and confirm
  an installed skill picks up its overlay.

## Out of Scope (for MVP)

- `install.ps1` / any Windows-specific path handling — next iteration.
- A separate conversational `/setup` skill.
- Sync/doctor/staleness tooling.
- Overlays for *every* skill — `learn-repo` writes the shared profile plus
  overlays only where a skill needs specifics.
- Committing symlinks / cross-machine symlink portability beyond a single dev's setup.

## Data Model

**Frontmatter dependency fields** (added to existing YAML frontmatter):

```yaml
requires: [review, ba-triage]          # other skills this skill needs
requires-agents: [architect, ba]       # agents this skill drives
```

Absent fields mean no dependencies. Agents may declare `requires-agents:` too
(rare). The setup script treats the union as the install set.

**`.llm-academy/repo.md`** — shared profile, one file per consuming repo:

```markdown
# Repo Profile
- Language: <primary language>
- Build: <build command>
- Test: <test command>
- Source layout: <where business logic lives>
- Test layout: <where tests live>
- Default branch: <branch>
## Conventions
- <settled convention 1>
- <settled convention 2>
```

**`.llm-academy/<slug>.md`** — per-skill overlay, free-form markdown scoped to
that skill's customization points (e.g. `ba-triage.md` lists the project's defer
labels; `tech-debt-analysis.md` gives concrete source paths and principles).

## Behaviors

### Overlay footer (canonical definitions)

- Every skill and agent gains an identical block pointing at its overlay:

  > **Repo-specific guidance.** If `.llm-academy/<slug>.md` exists in the repo
  > root, read it before applying anything below — it overrides generic guidance
  > for this project. The shared profile `.llm-academy/repo.md` applies to all
  > skills.

- `<slug>` matches the skill's directory name / agent file name.
- With no overlay present, behavior is identical to today (graceful no-op).
- The footer is placed uniformly — chosen placement (top vs. trailing section)
  is a one-time decision applied to all files.

### `install.sh`

1. **Locate the llm-academy clone.** Resolve via (in order) `--source <path>`
   arg, `LLM_ACADEMY_HOME` env var, or the script's own directory (it lives in
   the clone). Error clearly if it can't be found.
2. **Determine the target repo.** Default: current working directory. The target
   must contain (or will create) `.claude/skills` and `.claude/agents`.
3. **Selection.** With no slug args: show an interactive selector listing every
   available skill (and a separate agent list), let the user pick. With slug args
   (`install.sh feature-flow review`): use those, non-interactively.
4. **Dependency resolution.** Parse `requires:` / `requires-agents:` from
   selected definitions (transitively). If resolution adds anything the user
   didn't select, list the additions and ask `[Y/n]` (interactive) or include
   them automatically when `--with-deps` is passed (headless). Without
   `--with-deps` in headless mode, error listing the missing deps.
5. **Install.** For each resolved slug, create a symlink from
   `.claude/skills/<slug>` (or `.claude/agents/<name>.md`) to the canonical file
   in the clone. On `--copy`, or when symlinking fails, copy instead and warn
   that copies won't auto-sync.
6. **Convention stubs.** After install, check the target repo root for `TODOS.md`
   and `FEATURE_LOG.md`. For each missing one, offer `[Y/n]` to scaffold a
   minimal stub (header + empty section). Skip in headless mode unless
   `--scaffold` is passed.
7. **Idempotent.** Re-running with the same selection is a no-op (existing correct
   symlinks left alone; stale ones repaired).

### `learn-repo` skill

1. Confirm at least one skill/agent is installed (else tell the user to run
   `install.sh` first).
2. Read the repo to infer: primary language, build command, test command, source
   and test directory layout, default branch, and a short list of settled
   conventions (consult `CLAUDE.md` / README if present).
3. Write `.llm-academy/repo.md` with the shared profile. If it exists, update it
   rather than clobbering hand edits — surface a diff.
4. For each *installed* skill that has customization points, write a
   `.llm-academy/<slug>.md` overlay with concrete repo-specific guidance. Skip
   skills that need nothing beyond the shared profile; say which were skipped and
   why.
5. Report what was written and remind the user overlays are committable team
   knowledge.

## Integration Points

- **Existing skills/agents** — all of `skills/` and `agents/` gain the footer and
  (where applicable) frontmatter deps. Mechanical but touches every file.
- **The optional convention files** (`TODOS.md`, `FEATURE_LOG.md`, `CLAUDE.md`)
  already referenced across the pipeline — the stub scaffolding and `repo.md`
  profile feed the same hooks those skills already look for.
- **`README.md`** — its Installation section currently documents fork-and-customize
  and must be rewritten to document install → learn-repo (see Acceptance Criteria;
  done as a deliberate, confirmed edit).

## Extension Hooks

- **`requires:` frontmatter** is the extension point for the dependency graph —
  new skills declare deps and the selector picks them up with no script change.
- **Per-skill overlay files** are the per-repo extension point — any skill can
  define its own customization surface and `learn-repo` can target it without
  touching the canonical file.
- **`--source` / `LLM_ACADEMY_HOME`** lets the install point at any clone
  location, enabling multiple consuming repos off one clone.

## Acceptance Criteria

- [ ] Every `skills/*/SKILL.md` and `agents/*.md` carries the overlay footer
      pointing at `.llm-academy/<slug>.md`.
- [ ] Skills/agents with dependencies declare them via `requires:` /
      `requires-agents:` frontmatter; `feature-flow`'s graph (review, ba-triage,
      architect, lead-dev, junior-dev, ba, reviewer) resolves correctly.
- [ ] `install.sh feature-flow` resolves and installs the full dependency set as
      symlinks under `.claude/`.
- [ ] `install.sh` with no args shows a working interactive selector.
- [ ] `install.sh --copy` produces copies and warns they won't auto-sync.
- [ ] On a repo with no `TODOS.md` / `FEATURE_LOG.md`, the script offers to create
      stubs and does so on `Y`.
- [ ] Re-running `install.sh` with the same selection is a clean no-op.
- [ ] `learn-repo` writes a correct `.llm-academy/repo.md` and at least one
      per-skill overlay for the dogfood repo.
- [ ] An installed skill, when invoked, demonstrably reads its overlay (verified
      by putting a distinctive instruction in the overlay and observing it apply).
- [ ] `README.md` Installation section rewritten to document the
      install → learn-repo flow; the old fork-and-customize copy removed or
      reframed as the legacy path.
