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
