---
name: tech-debt-analysis
description: Architect-persona codebase audit for dead code, test gaps, pattern violations, tight coupling, and parameter proliferation. Deduplicates against the project backlog and open issues, then offers up to five findings for disposition (backlog entry or GitHub issue).
user-invocable: true
---

# Tech Debt Analysis Skill

> **Repo-specific guidance.** If `.llm-academy/tech-debt-analysis.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

When the user invokes `/tech-debt-analysis`, adopt the **architect persona** and run a structured audit of the codebase. The goal is to surface actionable tech debt — not minor style nits — and help the user decide what to do with each finding.

Stop and present findings after **five net-new items** are identified. Never pile up a long list; five is the session limit. The user can re-invoke to continue.

## Architect persona

Read everything through the lens of:
- The project's settled architectural principles (typically captured in `CLAUDE.md` or an equivalent design doc — e.g. data-driven values, extension hooks, vertical feature slices, no hardcoded magic numbers in business code)
- Any design-pattern reference the project commits to (e.g. `docs/patterns.md`, GoF, language-specific idioms) — observable violations are finding candidates
- The project's stance on legacy debt — if the project has a "no legacy debt" or "early-stage, rewrite freely" philosophy, treat existing code as fair game; if it has a "preserve stability" stance, weight findings by blast radius

Do not surface hypothetical future problems. Findings must be observable right now in the codebase.

## Phase 1 — Pre-flight (run in parallel)

Before scanning, build a **known-issues set** to deduplicate against. Run these simultaneously:

1. **Read the project backlog file** (e.g. `TODOS.md`, `BACKLOG.md`, or whatever the project uses) — extract every open item. Note the priority tier (P1/P2/P3/Deferred or equivalent) and a short description. Skip resolved items.

2. **Fetch open GitHub issues** — `gh issue list --state open --limit 80 --json number,title,labels`. Extract titles and labels. Flag any with labels `tech-debt`, `refactor`, `architecture`, or titles containing those words. (If the project uses a different issue tracker, adapt the command.)

3. **Search memory** — `mcp__plugin_claude-mem_mcp-search__memory_search` (load via ToolSearch) with query `"tech debt refactor coupling dead code test coverage"`. Collect any prior findings that were surfaced but not yet actioned.

Build a plain-English deduplication list from steps 1–3. A finding is a **duplicate** if it describes the same root problem as an existing item — not just if it mentions the same file. Use judgment: "PathFinder allocations" and "FindPath allocates a new collection per call" are the same; "PathFinder correctness" and "PathFinder allocations" are not.

Report the deduplication list to the user in one sentence: `"Found N open backlog items and M tech-debt issues already tracked — will skip those."` Then proceed to scanning.

## Phase 2 — Scanning (bail when five net-new findings accumulate)

Run scans in the order below. After each scan completes, add any net-new findings to the running list. Stop scanning as soon as the list hits five — do not start the next scan category. Partial progress through a category is fine; report what you found.

### 2A — Hardcoded magic values (data-driven principle)

If the project commits to a data-driven principle (numeric tunables live in configuration/JSON/YAML/DB, not source), scan business-logic source folders for non-trivial numeric literals.

```
grep -rn --include="<source-extension>" \
  -E "(= [2-9][0-9]|= [1-9][0-9][0-9]|= 0\.[1-9])" \
  <business-logic-path>/
```

Customize `<source-extension>` (e.g. `*.cs`, `*.ts`, `*.py`, `*.go`) and `<business-logic-path>` (e.g. `src/Features/`, `app/services/`) for the project. Skip configuration directories, content directories, and tests.

Ignore:
- `0` and `1` (structural/boolean sentinels)
- Numbers inside string literals or comments
- Array sizes / capacity hints (these are implementation detail, not tunable data)
- Test files

For each hit, check: is this a tunable (a value a non-engineer would plausibly want to adjust without a code change — pricing, thresholds, retry counts, durations, weights)? If yes → finding. If it's a pure algorithm constant (e.g. Bresenham step, atlas cell size, byte alignment), skip it.

Skip this scan entirely if the project does not have a data-driven principle.

Finding form: `Hardcoded value — <Module>/<File>:<line> — <value> <what it controls>. Should move to configuration/data.`

### 2B — Missing extension hooks

Any mechanic that resolves an outcome may need to consult external state, configuration, or layered behavior before resolving. Look for resolution methods that compute a result without consulting an injected modifier list, when the project's architectural principles call for extensibility.

Scan for resolution-style methods:

```
grep -rn --include="<source-extension>" \
  "public.*Resolve\|public.*Calculate\|public.*Apply\|public.*Compute" \
  <business-logic-path>/
```

For each hit, check: does this method's class constructor accept an `IEnumerable<ISomething>` (or language-equivalent injection point)? If the method resolves a meaningful outcome (pricing, eligibility, validation, transformation) and has no such hook, and the project's architecture calls for extensibility there → potential finding.

Only flag as a finding if:
- The mechanic is in a live module (not archive)
- The mechanic could plausibly need per-feature, per-tenant, or per-effect modification
- There is no existing modifier interface for it
- The project's settled principles support such hooks (don't invent a need)

Finding form: `Missing extension hook — <Module>/<File>: <MethodName> resolves <outcome> with no injected modifier list. Per project principles, needs an <ISomeModifier> hook so plugins/effects can layer behavior without rewriting the resolver.`

### 2C — Parameter proliferation

Methods or constructors with five or more parameters are candidates for a parameter object refactor. This is especially worth flagging in orchestrator/coordinator classes, which tend to accumulate parameters as features are added.

```
grep -rn --include="<source-extension>" \
  -E "\(([^)]*,){4,}[^)]*\)" \
  <source-paths>/
```

Filter out:
- Test files
- Method calls (not declarations) — focus on `public`, `private`, `protected` declarators (or language-equivalent visibility keywords)
- Attribute / annotation / decorator constructors

For each hit, read the method signature. Is this a real smell (unrelated concerns mixed together, caller must know too much) or a legitimate tuple-style aggregate (positional args that belong together)? Flag only real smells.

Finding form: `Parameter proliferation — <File>:<line> — <MethodOrClass> takes N parameters. Candidates for a parameter object: [list the ones that feel like a group].`

### 2D — Test coverage gaps

If the test structure mirrors the source structure, compare module/feature folders in the source tree vs the test tree. Run something like:

```
diff <(ls <source-modules-path>/) <(ls <tests-modules-path>/)
```

Adapt paths for the project (e.g. `src/Features/` vs `tests/Features/`, or `app/services/` vs `spec/services/`). If the project has no mirroring convention, skip this scan or use a coverage-tool report instead.

A missing test folder is a gap only if the corresponding source folder has non-trivial logic (more than just a data type or marker interface). Check file count:

```
find <source-modules-path>/<name> -name "<source-extension>" | wc -l
```

If 3+ source files and no test folder → likely gap. If 1 file (probably just a record or interface) → skip.

For modules that have test folders, do a quick ratio check — if a module has 8+ files and tests has 1 test file → possible undercoverage. Check the module name against the backlog (undercoverage items may already be logged).

Finding form: `Test coverage gap — <Module>/<name>/ has N files but tests/<name>/ [is missing | has only M test file(s)]. <What the module does> is untested or thinly tested. Key untested path: [infer from file names what the riskiest untested path is].`

### 2E — Tight coupling (cross-module direct dependencies)

Modules should communicate via events, interfaces, or through an orchestrator, not by directly mutating each other's state. Check for cross-module imports of mutable state.

The exact grep depends on the language and module convention. Examples:

```
# C# / Java-style namespaces
grep -rn --include="*.cs" "using <root>.Features\." <root>.Features/

# TypeScript / JavaScript
grep -rn --include="*.ts" "from ['\"].*features/" src/features/

# Python
grep -rn --include="*.py" "from app\.features\." app/features/
```

From inside any `<module-A>/` file, look for imports that pull in `<module-B>/` where B ≠ A. This is only a finding if the usage is **state mutation** (calling a setter, writing to a field, calling a mutating method) rather than consuming a data type or interface. Reading another module's immutable records is acceptable; calling a method that mutates it is not.

Finding form: `Tight coupling — <FileA> directly calls <ModuleB> state mutation via <method/property>. Should go through an event or orchestrator instead.`

### 2F — Dead code

Look for:
- Deprecation markers (e.g. `[Obsolete]`, `@Deprecated`, `# DEPRECATED`) in live code (not archive)
- Private methods that are never referenced within their own file
- Classes / functions with no usages outside their own namespace (rough: check if the symbol name appears anywhere outside its own file)

```
# Adapt the deprecation marker for the language
grep -rn --include="<source-extension>" "\[Obsolete\]\|@Deprecated\|# DEPRECATED" <source-paths>/
```

For private method dead code, a targeted check per suspicious file is more reliable than a broad grep. Only do this if earlier scans haven't hit five findings yet.

Finding form: `Dead code — <File>: <ClassName or MethodName> appears unused. [Deprecation marker / no callers found / archived system still has live reference].`

## Phase 3 — Deduplication pass

Before presenting findings, walk through each candidate against the known-issues set from Phase 1. Remove any that describe the same root problem as an open backlog item or open GitHub issue. If a finding is related but narrower/deeper than an existing item (e.g. the backlog says "PathFinder allocations" and you found a specific call site), it is **not** a duplicate — it is a refinement.

If deduplication reduces the list below five, note how many you filtered and why, then present what remains (even if fewer than five). Do not go back and scan more categories to pad back to five.

## Phase 4 — Present findings

Present findings as a numbered list with:
- **Category** (hardcoded value / missing hook / param proliferation / test gap / tight coupling / dead code)
- **Location** (file:line or module/)
- **Description** — what the problem is and why it matters
- **Recommended disposition** — backlog entry (with suggested priority) or GitHub issue (for things that need design discussion or significant scope)

Use the project backlog for: well-understood fixes with no design ambiguity, under ~2 hours of work.
Use a GitHub issue for: things that need architectural discussion, have multiple design options, or are significant enough to want CI tracking.

Then use `AskUserQuestion` to let the user choose disposition for each finding. Group them into one question per finding (multi-select). Offer:
- Add to backlog as P1 / P2 / P3 / Deferred (use the project's priority tiers)
- Create GitHub issue
- Skip (not worth tracking)

## Phase 5 — Execute dispositions

For each finding the user chose to act on:

**Backlog entry**: Append to the appropriate priority section in the project backlog file. Format to match existing entries — typically a label line, then 1–3 sentences of description, then `Surfaced by: /tech-debt-analysis <date>`.

**GitHub issue**: Draft body in `/tmp/tech-debt-<slug>-body.md` using the Write tool (never heredoc). Then:
```
gh issue create \
  --title "<concise title>" \
  --body-file /tmp/tech-debt-<slug>-body.md \
  --label "tech-debt"
```
Label with `tech-debt`. If it's a significant architectural change, also add `architecture`. Avoid auto-tagging into epic/tracking issues unless the finding is clearly a blocker for a specific feature — tech debt issues are their own backlog.

**Skip**: Acknowledge and move on. No file changes.

After executing, report:
- Which backlog sections were updated
- Which GitHub issues were created (with numbers/URLs)
- Any skipped findings

## Notes

- This skill reads the codebase but does not write code. It finds and files, not fixes.
- If the user wants to immediately implement a finding, direct them to `/feature-flow <issue-number>` or `/next-issue`.
- If the codebase is too clean to find five findings (lucky), say so. Don't manufacture issues.
- Re-invoking `/tech-debt-analysis` in the same session is safe — Phase 1 will re-read the backlog and issues including anything just created, and scanning will skip already-offered findings from this session.

## Customization Points

Before running this skill on a new project, fill in the placeholders or remove scan categories that don't apply:

- **Source paths** — replace `<business-logic-path>`, `<source-paths>`, `<source-modules-path>`, `<tests-modules-path>` with concrete project paths.
- **Source extension** — replace `<source-extension>` with the project's primary file extension (`*.cs`, `*.ts`, `*.py`, `*.go`, `*.rb`, etc.).
- **Backlog file** — replace references to "the project backlog file" with the actual filename if the project has one (`TODOS.md`, `BACKLOG.md`, etc.). If the project tracks everything in GitHub issues, drop the backlog scan and treat all dispositions as issues.
- **Priority tiers** — replace `P1 / P2 / P3 / Deferred` with the project's actual priority tiers.
- **Architectural principles** — point Phase 1 at the project's actual settled-decisions document (CLAUDE.md, ARCHITECTURE.md, etc.) and remove scan categories (2A, 2B) if the project has no equivalent principle.
- **Issue tracker** — if the project uses something other than GitHub issues, replace `gh issue list` and `gh issue create` with the equivalent commands.
