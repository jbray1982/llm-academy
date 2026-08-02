---
name: learn-repo
description: Read a consuming repo and write its `.llm-academy/` overlay files — a shared repo.md profile plus per-skill overlays — so symlinked llm-academy skills/agents customize to this project without being forked.
user-invocable: true
---

# Learn Repo Skill

> **Repo-specific guidance.** If `.llm-academy/learn-repo.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

When the user invokes `/learn-repo`, study the current repository and write the
`.llm-academy/` overlay files that customize the installed llm-academy skills and
agents to this project. This is the **semantic** half of adoption: the
`install.sh` setup script wires generic definitions in (deterministic); this
skill captures what makes *this* repo specific (judgment).

The canonical skills/agents are installed as symlinks and stay generic. Each one
carries a footer pointing at `.llm-academy/<slug>.md`. This skill writes those
overlays. **It never edits a file under `.claude/skills` or `.claude/agents`** —
those are symlinks into the shared clone; editing them would corrupt upstream and
defeat the no-fork design.

## When to run

- Right after `install.sh`, on first adoption.
- Again whenever the repo's shape changes materially (build/test commands move,
  a major directory restructure, a new settled convention) — re-run to refresh.

## Step 0: Confirm install happened

Check that `.claude/skills/` (or `.claude/agents/`) contains at least one entry.
If empty, tell the user to run `./install.sh` (from the llm-academy clone, with
this repo as the target) first, and stop. This skill writes overlays for what is
installed — there is nothing to customize otherwise.

Record which skills and agents are installed — the per-skill overlays in Step 2
are written only for these.

## Step 1: Write the shared profile (`.llm-academy/repo.md`)

This is the profile **every** skill and agent reads. Do the archaeology, then
write it.

Infer from the repo (read, don't guess):

- **Primary language(s)** — from file extensions, manifests (`package.json`,
  `*.csproj`, `Cargo.toml`, `pyproject.toml`, `go.mod`, etc.).
- **Build command** — from the manifest's scripts / conventional tooling.
- **Test command** — same; note the test framework.
- **Source layout** — where business logic lives (e.g. `src/`, `app/`, `lib/`).
- **Test layout** — where tests live and whether they mirror source.
- **Default branch** — `git symbolic-ref --short refs/remotes/origin/HEAD` or
  `git branch --show-current`.
- **Settled conventions** — read `CLAUDE.md` / `README.md` / `CONTRIBUTING.md`
  if present and distill the load-bearing rules (architecture principles,
  commit/PR conventions, attribution line, labels). Keep it short — pointers,
  not a copy.

Write `.llm-academy/repo.md`:

```markdown
# Repo Profile

_Written by /learn-repo on <date>. Re-run to refresh; hand edits are respected
(this skill surfaces a diff before overwriting)._

- Language: <primary language(s)>
- Build: <build command>
- Test: <test command>
- Source layout: <where business logic lives>
- Test layout: <where tests live, mirroring or not>
- Default branch: <branch>

## Conventions
- <settled convention 1>
- <settled convention 2>
```

If `.llm-academy/repo.md` already exists, **do not clobber blindly** — read it,
show the user a diff of what you'd change, and confirm before overwriting. Hand
edits made to the overlay are valuable and may post-date the last run.

## Step 2: Write per-skill overlays (only where needed)

For each **installed** skill that has genuine customization points, write
`.llm-academy/<slug>.md` with concrete, repo-specific guidance. Do **not** write
an overlay for a skill whose behavior is fully determined by the shared profile —
an empty overlay is noise. Say which skills you skipped and why.

Each canonical skill's customization surface is described in its own
`## Customization` / `Customization Points` section (read the installed skill to
find it). Common cases:

| Skill | Typical overlay content |
|-------|------------------------|
| `feature-flow` | Build/test commands, default branch, branch-naming convention, backlog filename, labels, Co-Authored-By line, epic/tracking structure |
| `ba-triage` | Project-specific defer labels beyond the defaults |
| `tech-debt-analysis` | Concrete source paths, source extension, priority tiers, which scan categories apply, the settled-decisions doc path |
| `review` | The adversarial-pass wrapper script path (if the project has one), any project-specific extension to the default secondary-model CLI candidate list, the project's check categories pointer |
| `worktree` | Worktree location and branch naming if not the defaults; the exact bootstrap steps a fresh worktree needs (env files to copy, dependency install command, whether to run them unprompted); whether the repo lands via PR at all; remote-branch cleanup policy |
| `feature-spec` / `noodle-on` / `feature-log` | Whether the project maintains `FEATURE_LOG.md` / `TODOS.md`; the docs/ layout for specs |

**Point-in-time probes vs. durable configuration.** Some overlay content is a
genuine, durable decision (a chosen wrapper script path, a build command, a
branch-naming convention) — write that plainly, it doesn't go stale. Other
content is the *result of an environment probe run right now* (is a secondary-
model CLI installed and on `PATH`, is a given tool authenticated) — that can
change between sessions independent of anything about the repo. Write
probe results with an explicit point-in-time qualifier so a later session reads
them as a hint to re-check, not as standing fact — e.g. "codex CLI was reachable
(probed `<YYYY-MM-DD>`; re-probe at run time before relying on this)", stamping
the actual date at probe time rather than copying one. This applies
specifically to environment-availability statements (is X installed/reachable),
not to configuration choices like a wrapper path or candidate-list override —
those stay durable and unqualified.

Overlay format is free markdown scoped to that skill. Lead with the most
load-bearing specifics. Example `.llm-academy/feature-flow.md`:

```markdown
# feature-flow — repo specifics

- Build: <command>
- Test: <command>
- Default branch: main
- Branch naming: feature/issue-<number>
- Backlog file: TODOS.md
- Co-Authored-By: <line>
- Tracking: link new issues to the milestone, no epics in use.
```

Write overlays only for installed skills. If `feature-flow` is not installed,
skip its overlay even if the repo could use one.

## Step 3: Report

Tell the user:

- The path to `.llm-academy/repo.md` and a one-line summary of what it captured.
- Each per-skill overlay written, and which installed skills were intentionally
  skipped (with the one-line reason).
- A reminder: **commit `.llm-academy/`** — overlays are team knowledge that
  travels with the repo. The `.claude/` symlinks should stay out of version
  control (they point at each developer's local clone); add them to
  `.gitignore` if they are not already ignored.
- When to re-run (repo shape changed, or new skills installed).

## What this skill does NOT do

- **Never edit `.claude/skills/**` or `.claude/agents/**`** — they are symlinks
  into the shared clone. All customization goes in `.llm-academy/`.
- Do not write overlays for skills that are not installed.
- Do not run `install.sh` — that is a separate, deterministic step the user runs
  first. This skill assumes the install already happened.
- Do not commit. Writing the overlay files is enough; the user commits them.
