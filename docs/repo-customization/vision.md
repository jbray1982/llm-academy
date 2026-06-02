# Repo Customization — Vision

## Vision

llm-academy ships generic agent and skill templates. Today the only documented
way to adopt them is **fork-and-customize**: copy the files into your repo's
`.claude/` directory and have an LLM rewrite each one for your stack. That works
once, then rots — the consuming repo immediately drifts from upstream and never
receives later improvements. The repo's own `.local/docs/DRIFT-REPORT.md` is the
evidence: keeping a real project in sync with these templates is manual,
error-prone, and perpetual.

The vision is to **kill drift by separating the generic definition from the
repo-specific guidance.** Canonical skills and agents are installed as
**symlinks** into a consuming repo, so a `git pull` in the llm-academy clone
propagates every upstream fix automatically. Repo-specific customization lives
*beside* them as **overlay files** in a `.llm-academy/` directory that the
canonical definitions reference but never contain. Customization becomes data,
not a fork. You install once, pull forever, and tailor locally without ever
editing a canonical file.

Two tools deliver this, split along a clean seam — deterministic work in a
script, semantic work in a skill:

- **`install.sh` / `install.ps1`** — a setup script that selects which
  skills/agents to install, resolves their dependencies, symlinks (or copies)
  them in, and offers to scaffold the optional convention files the skills hook
  into. Every decision it makes is deterministic, so no LLM is involved.
- **`learn-repo`** — a skill that reads the actual repo and writes the overlay
  files: a shared profile plus per-skill guidance. This is where intelligence
  belongs, because inferring a project's conventions requires reading it.

The adoption flow becomes: **clone llm-academy → run the setup script →
run `learn-repo`.**

## User Experience

A developer adopting llm-academy in their project:

1. Clones llm-academy somewhere stable.
2. Runs `install.sh` from inside their own repo. The script shows a selector:

   ```
   [ ] feature-flow    [ ] feature-spec    [ ] review
   [ ] ba-triage       [ ] tech-debt-analysis  ...
   ```

   They tick `feature-flow`. The script reads its `requires:` frontmatter and
   asks: *"feature-flow also pulls in review, ba-triage and the
   architect / lead-dev / junior-dev / ba / reviewer agents — install them too?
   [Y/n]"*. They confirm.
3. The script symlinks the selected definitions into `.claude/skills/` and
   `.claude/agents/`, then notices there's no `TODOS.md` or `FEATURE_LOG.md` and
   asks: *"These skills work best with a backlog file and a feature registry —
   create stubs? [Y/n]"*.
4. They invoke `learn-repo`. It reads the codebase, infers the language, build
   and test commands, directory layout, and settled conventions, then writes
   `.llm-academy/repo.md` plus a handful of per-skill overlays (e.g.
   `.llm-academy/ba-triage.md` with the project's defer labels).
5. From then on, every installed skill reads its overlay automatically. When
   llm-academy improves upstream, the developer runs `git pull` in the clone and
   their skills update with zero merge work — overlays untouched.

## Mechanics & Systems

- **Overlay seam (the footer convention).** Every canonical skill and agent
  carries a standard, identical block:

  > *Repo-specific guidance: if `.llm-academy/<slug>.md` exists, read it first;
  > it overrides anything generic below.*

  The footer lives in the upstream definition (not the consuming repo), so it
  ships with the symlink. A definition with no overlay present behaves exactly as
  it does today.

- **Overlay layering.** `learn-repo` writes two tiers:
  - `.llm-academy/repo.md` — the shared profile every skill needs: primary
    language, build command, test command, source/test directory layout, default
    branch, and a short list of settled conventions.
  - `.llm-academy/<slug>.md` — per-skill overlays, written only where a skill
    genuinely needs specifics (e.g. `ba-triage`'s defer-label enumeration,
    `tech-debt-analysis`'s source paths and architectural principles). Skills
    that need nothing beyond the shared profile get no per-skill file.

- **Dependency graph via frontmatter.** Each skill/agent declares its
  dependencies in YAML frontmatter:

  ```yaml
  requires: [review, ba-triage]
  requires-agents: [architect, lead-dev, junior-dev, ba, reviewer]
  ```

  The frontmatter is the single source of truth; the setup script parses it to
  resolve the selection. No separate manifest file to drift.

- **Setup script (deterministic).** Interactive selector; dependency resolution
  with a confirm prompt; symlink-default / copy-fallback install (copy on
  Windows-without-dev-mode or when `--copy` is passed); convention-file stub
  scaffolding; accepts explicit slugs as args for headless/CI use; idempotent and
  re-runnable.

- **`learn-repo` skill (semantic).** Reads the repo, infers shape, writes the
  overlays. Re-runnable when the repo shape changes.

## Open Questions

- **Commit boundary in the consuming repo.** Overlays (`.llm-academy/`) are team
  knowledge and should be committed. Symlinks under `.claude/skills` are
  machine-specific (they point at a developer's local llm-academy clone) and
  probably should *not* be committed — implying install is a per-developer step
  and `.claude/skills` (or the symlinks within) belong in the consuming repo's
  `.gitignore`. Needs to be settled in the MVP spec.
- **Where does the consuming repo point the symlinks?** The script needs to know
  the path to the llm-academy clone — argument, env var, or prompt? Convention TBD.
- **Footer placement.** Top-of-file (near frontmatter, most discoverable on load)
  vs. a dedicated trailing section. The MVP picks one and applies it uniformly.
- **Stub content.** How much should the scaffolded `TODOS.md` / `FEATURE_LOG.md`
  contain — empty headers, or a worked example? Lean toward minimal headers.

## Out of Scope

- **Windows / PowerShell support** — `install.ps1` is the named next iteration,
  not part of the MVP.
- A separate conversational `/setup` skill — deliberately rejected. The install
  decisions are deterministic, so a well-written script handles them; the LLM's
  value is concentrated in `learn-repo`.
- A sync/doctor command that detects upstream or overlay staleness — a possible
  later iteration, not the MVP.
- Auto-updating overlays when the repo changes — `learn-repo` is re-run manually.
- Publishing llm-academy as an installable package / marketplace plugin.
