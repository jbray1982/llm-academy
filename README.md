# Generic Claude Code Agent & Skill Definitions

This folder contains **generic, project-agnostic** agent and skill definitions for use with [Claude Code](https://claude.ai/code). They define a structured software development pipeline where specialized agents handle different phases of work.

These definitions stay **generic on purpose**. Instead of forking and hand-editing them per project (which immediately drifts from upstream), you **install them as symlinks** and layer your project's specifics into a separate `.llm-academy/` overlay directory that each definition references but never contains. Customization becomes data, not a fork: a `git pull` in this clone propagates improvements to every repo that installed from it, and your overlays are left untouched.

## Installation

Clone this repo somewhere stable, then from inside your project run the setup script:

```bash
/path/to/llm-academy/install.sh                        # interactive selector
/path/to/llm-academy/install.sh feature-flow review    # specific slugs (+ deps)
```

`install.sh` lets you pick which skills/agents to install, resolves their dependencies (declared via `requires:` / `requires-agents:` frontmatter), symlinks them into your `.claude/` directory (use `--copy` for a non-synced copy, e.g. on Windows without Developer Mode), and offers to scaffold the optional convention files (`TODOS.md`, `FEATURE_LOG.md`) the skills hook into. Re-running is safe and idempotent: it reports only what actually changed, so an unchanged install shows zero changes. Because the symlinks point at your local clone, the script also offers to add just those paths to your `.gitignore` (pass `--gitignore` to do it without prompting) rather than ignoring all of `.claude/` — keeping any tracked files like `settings.local.json` under version control. Run `install.sh --help` for all options.

Then, from your project, run the **`learn-repo`** skill. It reads your codebase and writes the `.llm-academy/` overlays — a shared `repo.md` profile (language, build/test commands, layout, conventions) plus per-skill guidance where a skill needs specifics. **Commit `.llm-academy/`** (it is team knowledge); leave the installed `.claude/` symlinks out of version control (they point at each developer's local clone — the `--gitignore` step above handles exactly those paths).

The adoption flow is: **clone → `install.sh` → `learn-repo`.**

### How customization works

Every skill and agent carries a footer like *"if `.llm-academy/<slug>.md` exists, read it first."* When the overlay is present it overrides the generic guidance for your project; when absent, the definition behaves generically. You never edit a canonical file, so upstream and local stay cleanly separated.

> **Legacy path (manual fork).** You can still `cp -r agents/ skills/` into `.claude/` and hand-edit the placeholders (`[your project]`, build commands, etc.) directly. It works, but it drifts from upstream — prefer the install + overlay flow above.

## Agents

### Pipeline Agents (recommended workflow order)

| Agent | Role | When to Use |
|-------|------|-------------|
| **architect** | Designs features — produces design documents with data models, integration points, and implementation manifests | Before implementation of non-trivial features |
| **lead-dev** | Scaffolds interfaces, stubs, and produces implementation manifests for junior devs | When the design requires careful interface work before body implementation |
| **junior-dev** | Fills in method bodies from a lead-dev manifest, one function at a time | Mechanical implementation work with clear specifications |
| **reviewer** | Reviews implementations against the architect's design and project conventions | After implementation is complete |
| **ba** | Manages the GitHub backlog — creates/updates issues, tracks progress | Issue management and closing completed work |

### Supporting Agents

| Agent | Role |
|-------|------|
| **feature-creator** | Explores product feature design space, generates structured proposals, bridges from ideation to GitHub issues |
| **content-assistant** | Creates and maintains non-code domain content (documentation, copy, marketing material, style guides) |
| **qa-assist** | Generates actionable smoke test plans mapping code changes to user-facing verification steps |

## Skills

| Skill | Invocation | Purpose |
|-------|-----------|---------|
| **noodle-on** | `/noodle-on [topic]` | Generate 2-5 structured design proposals on a topic, saved sequentially in `./noodles/` |
| **interview-me** | `/interview-me [issue or topic]` | BA-style requirements gathering interview with the product owner |
| **next-issue** | `/next-issue [number]` | Pick up the next GitHub issue — suggests candidates when none is named, then summarizes it and opens the discussion |
| **ba-triage** | `/ba-triage <issue-number>` | BA readiness triage on a single issue — assess ready/deferred and recommend approach (scaffold / lead-dev / junior / needs-architect). Leaves a machine-readable footer for `/feature-flow` to reuse |
| **feature-spec** | `/feature-spec [feature-name]` | Interview-driven feature specification — produces a vision doc, MVP spec, MVP GitHub issue, and next-iteration issue. Re-invokable on existing features for next-iteration planning with contradiction-surfacing |
| **feature-flow** | `/feature-flow <issue-number>` | Run the full implementation pipeline for a single issue (BA triage → architect → implementation → review → PR). Worktree-aware, with a human checkpoint after triage |
| **tech-debt-analysis** | `/tech-debt-analysis` | Architect-persona codebase audit (dead code, test gaps, pattern violations, tight coupling, parameter proliferation). Deduplicates against backlog and open issues; offers up to five findings for disposition |
| **feature-log** | `/feature-log` | Query and navigate `FEATURE_LOG.md` — the registry of every named concept in the project's design surface (conviction × status, blocking relationships, `See:` links). Maintained automatically by `/feature-spec`, `/noodle-on`, and `/feature-flow` |
| **review** | `/review [base-branch]` | Pre-landing review of a branch's diff: primary `reviewer` pass + a cross-model adversarial pass whenever a secondary-model CLI is on `PATH` (no setup required) + synthesis + fix-first (auto-fix trivial, batch-ask substantive). Writes `handoffs/review-{issue}-{round}.md` (one file per round — re-reviews never overwrite earlier ones) and emits a verdict `/feature-flow` Step 4 consumes. Headless-safe for CI/batch use |
| **handoff** | `/handoff [slug]` | Write a minimal `/tmp/` handoff prompt so a fresh context (post-`/clear`, or a new session for the next step) can resume the current task. Leans on the auto-loaded instructions file + any session-memory index — captures only the edge state those don't already provide |
| **learn-repo** | `/learn-repo` | Read the repo and write its `.llm-academy/` overlay files — a shared `repo.md` profile plus per-skill guidance — so installed skills/agents customize to the project without being forked. The semantic half of adoption; pairs with the `install.sh` setup script |

## Harness (headless pipeline runner)

`harness/` is a headless single-work-item pipeline runner that executes the
feature-flow stages (triage → architect → implement → review → commit) as
declarative YAML config rows through one generic executor loop. It is the
machine-readable companion to `/feature-flow`: same stages, same agents, no
interactive prompts.

```bash
harness/run.sh <issue-number> [--config <path>]
```

Exit codes: `0` completed · `75` deferred (retry later) · `1` aborted · `2` config error.

- [`harness/README.md`](harness/README.md) — invocation, exit codes, per-repo override model, telemetry, installation
- [`harness/config/README.md`](harness/config/README.md) — full configuration reference: stage fields, predicate forms, approach enum, facts store, path resolution, verification plugin manifest

---

## Recommended Pipeline

For most features, the pipeline flows:

```
feature-creator (if design is unclear)
    → architect (design document)
        → lead-dev (scaffold + manifest)
            → junior-dev (implement bodies)
                → /review skill (reviewer pass + adversarial pass if a secondary CLI is on PATH + fix-first)
                    → ba (commit, close issue)
```

**Fast-tracking**: For small or well-understood changes, skip early steps and go straight to implementation. If the issue already has clear acceptance criteria and touches few files, you don't need a full architect design.

**Complexity-based routing**: The architect assesses implementation complexity and recommends one of:
1. **Trivial** — architect implements directly
2. **Junior-dev solo** — clear requirements, existing patterns to follow
3. **Lead-dev scaffold + junior-dev** — needs interface design, then mechanical implementation
4. **Lead-dev direct** — complex/high-risk, no delegation

## Project Conventions

Several skills assume a few lightweight project-root conventions. None are mandatory, but skills work best when they exist:

### Backlog file (`TODOS.md` / `BACKLOG.md`)

A markdown file at the project root that holds work items not yet promoted to GitHub issues — small fixes, deferred refactors, follow-ups, and ideas that don't justify a full issue. Organized into priority tiers (suggested: **P1 / P2 / P3 / Deferred**), with each item being a short labeled paragraph. Resolved items can be marked with ✅ or removed.

**Who reads it:**
- `feature-flow` — Step 1c sweeps the backlog for items that could be cheaply bundled into the current issue's scope.
- `tech-debt-analysis` — Phase 1 reads it as part of the dedup set, so audits don't re-surface known items.

**Who writes it:**
- You, manually, when capturing follow-ups during other work.
- `tech-debt-analysis` — Phase 5 appends findings the user disposes as backlog entries.
- The `ba` agent / `/feature-flow` Step 4a — when a reviewer finding is classified as backlog rather than a new issue.

If a project tracks everything in GitHub issues and has no markdown backlog, skills will skip the corresponding scans / sweeps. Adopt the file when accumulated follow-ups start outpacing what's worth filing as issues.

### Settled-decisions doc (`CLAUDE.md`)

A project-root file that captures architectural principles and settled design decisions. `tech-debt-analysis` reads it (or an equivalent) to know which violations to flag (e.g. data-driven principle, extension-hook principle). The harness also auto-loads it into every session.

### Feature registry (`FEATURE_LOG.md`)

A flat markdown file at the repo root listing every named feature, mechanic, or cross-cutting system that has surfaced in design conversations, tagged with **conviction** (`must-have` / `probably-need` / `cool-if`) and **status** (`concept` / `unknown` / `code-present` / `defined` / `partially-live` / `live` / `dropped` / `superseded`). An orthogonal `blocked: <name>` modifier captures dependencies. Each entry carries `See:` links to the noodles, specs, issues, and PRs that built it.

It is **not** a backlog (that's `TODOS.md`), **not** an issue tracker (that's GitHub), and **not** a spec (that's `docs/<feature>/`). It answers: *what named concepts exist and where do they stand?*

**Who reads it:**
- `/feature-log` — the dedicated query interface (lookup by name, filter by status/conviction, blocking queries, dashboard).
- `/feature-spec` — checks the entry on entry to NEW or ITERATE so the interview starts informed.

**Who writes it:**
- `/feature-spec` — creates/updates entries at convergence (status → `defined`); captures any tangent concepts mentioned during the interview.
- `/noodle-on` — adds noodle files to relevant entries' `See:` lines; offers to add new entries for any new concepts.
- `/feature-flow` Step 6a — promotes status to `partially-live` / `live` / `code-present` when a PR merges.

If a project doesn't maintain a `FEATURE_LOG.md`, all of these hooks skip silently. Adopt the file when named-concept tracking becomes useful — typically once a few features have shipped and design exploration starts referencing prior work by name. `/feature-log` can scaffold the file on first invocation.

### Handoff docs (`handoffs/`)

A directory where the `architect` agent writes implementation handoff documents that `lead-dev` and `junior-dev` consume. Created on demand by the pipeline; no setup required.

## License

[MIT](LICENSE) — borrow freely, modify, redistribute. Attribution appreciated but not enforced beyond what the license requires.
