# Generic Claude Code Agent & Skill Definitions

This folder contains **generic, project-agnostic** agent and skill definitions for use with [Claude Code](https://claude.ai/code). They define a structured software development pipeline where specialized agents handle different phases of work.

These are **templates** meant to be refined for your specific project. Before using them, have your LLM review and refine each definition for your specific codebase, tech stack, domain terminology, and workflow preferences. The placeholders (`[your project]`, `[your domain]`, etc.) should be replaced with concrete details, and project-specific conventions (test frameworks, build commands, folder structures) should be filled in.

## Installation

Copy the contents into your project's `.claude/` directory:

```bash
cp -r agents/ /path/to/your/project/.claude/agents/
cp -r skills/ /path/to/your/project/.claude/skills/
```

Then customize each file for your project.

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
| **next-issue** | `/next-issue [number]` | Compact context and begin working on the next GitHub issue |
| **ba-triage** | `/ba-triage <issue-number>` | BA readiness triage on a single issue — assess ready/deferred and recommend approach (scaffold / lead-dev / junior / needs-architect). Leaves a machine-readable footer for `/feature-flow` to reuse |
| **feature-spec** | `/feature-spec [feature-name]` | Interview-driven feature specification — produces a vision doc, MVP spec, MVP GitHub issue, and next-iteration issue. Re-invokable on existing features for next-iteration planning with contradiction-surfacing |
| **feature-flow** | `/feature-flow <issue-number>` | Run the full implementation pipeline for a single issue (BA triage → architect → implementation → review → PR). Worktree-aware, with a human checkpoint after triage |
| **tech-debt-analysis** | `/tech-debt-analysis` | Architect-persona codebase audit (dead code, test gaps, pattern violations, tight coupling, parameter proliferation). Deduplicates against backlog and open issues; offers up to five findings for disposition |
| **feature-log** | `/feature-log` | Query and navigate `FEATURE_LOG.md` — the registry of every named concept in the project's design surface (conviction × status, blocking relationships, `See:` links). Maintained automatically by `/feature-spec`, `/noodle-on`, and `/feature-flow` |

## Recommended Pipeline

For most features, the pipeline flows:

```
feature-creator (if design is unclear)
    → architect (design document)
        → lead-dev (scaffold + manifest)
            → junior-dev (implement bodies)
                → reviewer (check implementation)
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
