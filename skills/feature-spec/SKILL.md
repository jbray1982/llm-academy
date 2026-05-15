---
name: feature-spec
description: Interview-driven feature specification. Produces a vision doc, an MVP spec, an MVP GitHub issue, and a next-iteration GitHub issue. Re-invokable on an existing feature to plan the next iteration with contradiction-surfacing.
user-invocable: true
---

# Feature Spec Skill

When the user invokes `/feature-spec [feature-name or topic]`, run a structured interview using the **feature-creator** agent's persona and operating principles (`.claude/agents/feature-creator.md`). The skill has two distinct paths — **NEW** (no prior docs) and **ITERATE** (vision doc + next-step issue already exist).

The goal is **not** to produce a noodle. Noodles are exploration. This skill is the step **after** exploration is settled enough to commit to a direction: it produces a vision document, a concrete MVP specification, a GitHub issue for the MVP, and a follow-up GitHub issue for what comes after.

## Adopt the Feature Creator persona

Before starting the interview, re-read `.claude/agents/feature-creator.md` and operate as that agent for the duration of the conversation. That means:

- Mirror back creative intent frequently — show you understand where the user is steering things.
- Flag architectural and extensibility concerns honestly, framed as design opportunities.
- Reference the project's architecture docs, CLAUDE.md settled decisions, and existing code where relevant.
- Use rigorous systems thinking, but stay fluid — treat the interview as collaborative co-design, not requirements extraction.

This skill **does not** spawn the feature-creator as a subagent (subagents can't hold a multi-turn interview). The main thread adopts the persona directly.

## Routing: NEW vs ITERATE

When the skill fires, decide which path to run:

1. Slugify `[feature-name or topic]` to a `<feature-name>` directory slug (kebab-case, e.g. "User Notifications" → `user-notifications`).
2. Check whether `docs/<feature-name>/` exists and contains a `vision.md`.
   - If **no**: run the **NEW** path.
   - If **yes**: run the **ITERATE** path.
3. If the user explicitly says "new feature" or "restart" or "from scratch" even when docs exist, ask before clobbering — but default to ITERATE when docs are present.

Tell the user which path you've selected and why in one sentence before starting the interview.

## Path A — NEW feature

### A.1. Orient (1 short message)

- State the feature-name slug you'll use.
- Note any architecture docs or CLAUDE.md settled decisions that the feature obviously touches, so the user can correct misalignment early.
- Pull relevant past work via claude-mem if useful (`mcp__plugin_claude-mem_mcp-search__memory_search` — load via ToolSearch). Don't sink time here; one targeted query, not a fishing trip.

### A.2. Interview in three passes

The interview has **three explicit phases**. Tell the user which phase you're in at the top of each. Use `AskUserQuestion` for branching choices; use direct conversational questions for open exploration. Ask 2–4 questions per turn, not 10.

**Phase 1 — Full imagined scope.** Goal: capture the "dream version" of this feature. The polished, full-fat, "if we had infinite time" version. Push for ambition here — this is the vision doc.

- What does this feature ultimately want to be?
- Who's the user and what's the headline experience?
- What systems does it touch? What does it enable that doesn't exist yet?
- What's the closest reference (other product, existing noodle, real-world analog)?
- What would make this feature feel distinctly "on brand" for this project?

End Phase 1 by mirroring the vision back in 3–5 bullets and confirming before moving on.

**Phase 2 — Minimum Valuable Product.** Goal: identify the smallest slice that proves the core idea is valuable. The MVP must be usable/observable, not just architectural plumbing.

- What's the single most load-bearing thing this feature does? Cut everything else.
- What can be hardcoded, stubbed, or placeholder for MVP and still let the user feel the idea?
- What data structures and storage decisions must be made now?
- What extension hooks must be designed in now, even if empty?
- Is there an existing feature it slots cleanly beside in the codebase?

End Phase 2 by mirroring the MVP back in 3–5 bullets and getting an explicit yes.

**Phase 3 — Next iteration after MVP.** Goal: name the *single* next iteration. Not a full roadmap — just the one most-valuable next step once the MVP is in hand.

- After using the MVP, what's the first thing you'd want to add?
- Is the next step "make it deeper" (more content, more variation) or "make it richer" (new mechanic, new interaction)?
- What does this next step **prove** that the MVP doesn't?

### A.3. Surface contradictions

Throughout the interview, flag any tension between what the user is saying now and:
- CLAUDE.md settled decisions or existing architecture docs
- The current state of the codebase (existing patterns, archived systems)
- Statements the user made earlier in this same interview

Don't bury contradictions — name them clearly and let the user choose.

### A.4. Convergence — write the artifacts

Once Phase 3 is settled, generate the four artifacts. Do this **without further questions** unless something critical was left ambiguous.

1. **`docs/<feature-name>/vision.md`** — the full imagined scope. Sections:
   - **Vision** — 1–2 paragraph statement of the dream version.
   - **User Experience** — what it feels like to use this feature when it's done.
   - **Mechanics & Systems** — bullet list of mechanics, data shapes, integration points.
   - **Open Questions** — anything left unresolved.
   - **Out of Scope** — explicitly things this feature is *not*.

2. **`docs/<feature-name>/001-mvp-spec.md`** — concrete spec for the MVP slice. Spec files are numerically prefixed (`001-`, `002-`, …) so the evolution of the feature is readable at a glance from a directory listing. The MVP is always `001-`. Sections:
   - **Goal** — one paragraph, what the MVP must demonstrate.
   - **In Scope** — bullet list of what's included.
   - **Out of Scope (for MVP)** — bullet list of things explicitly deferred.
   - **Data Model** — data structures and storage shapes.
   - **Behaviors** — concrete behaviors with edge cases.
   - **Integration Points** — which existing systems it touches and how.
   - **Extension Hooks** — what extension points must be wired now (even if empty).
   - **Acceptance Criteria** — checklist of observable outcomes.

3. **MVP GitHub issue** — created via `gh issue create --body-file /tmp/feature-spec-mvp-body.md` (draft body in `/tmp/` first, never use heredoc). Body should be a tight summary that points at `docs/<feature-name>/001-mvp-spec.md` for full detail, then inline the acceptance criteria checklist. Title: `Implement <feature-name> MVP`. Link to the appropriate epic or tracking issue per the project's workflow rules.

4. **Next-iteration GitHub issue** — created the same way. Title: `<feature-name>: next iteration — <one-line description>`. Body briefly states what this iteration proves beyond the MVP, references `docs/<feature-name>/vision.md`, and explicitly notes it is **blocked on the MVP issue**. Label appropriately (e.g. `blocked`).

After writing artifacts, report to the user:
- The four artifact paths/URLs
- Which tracking issue you added them to
- Any open questions that need follow-up

### A.5. Memory hygiene

After artifacts ship, optionally drop a claude-mem observation for future sessions if the design surfaced something non-obvious (a settled architectural choice, a deferred mechanic, a constraint the user feels strongly about). Use `mcp__plugin_claude-mem_mcp-search__observation_add` (load via ToolSearch). Skip this if the spec is straightforward and the docs already capture everything — don't pad memory with restatements of what's in the spec.

Save **why** decisions were made, not **what** they are. The spec captures the what.

## Path B — ITERATE on an existing feature

### B.1. Re-orient (read first, then talk)

Before asking anything, do the homework. The user has explicitly said they may have forgotten what's in the docs or changed their mind, so come in fully briefed.

1. Read `docs/<feature-name>/vision.md` end to end.
2. Read the most recent spec file in `docs/<feature-name>/`. Spec files are numerically prefixed (`001-mvp-spec.md`, `002-<iteration>-spec.md`, …) — the highest-numbered file is the most recent. Read it, and skim the prior ones for evolution context if anything in the conversation hinges on history.
3. Identify the open "next iteration" GitHub issue for this feature (search by feature-name in title, or by label). Read it.
4. **Trust the latest spec doc as roughly correct.** Only check the code if something in the conversation suggests the doc and code diverged. If you do check code, scope to the feature's directory or wherever it lives.
5. Pull any claude-mem memories tagged to this feature.

Report back in one message:
- 1-paragraph summary of the vision as currently written
- 1-paragraph summary of what the last spec built / is supposed to have built
- The current open next-iteration issue (title + 1-line of what it proposes)
- Any obvious tension between the vision and the open issue

### B.2. Interview — "next most valuable iteration"

The interview is shorter than the NEW path. Three passes:

**Pass 1 — Re-confirm the vision.** Walk through the vision doc with the user. For each major bullet, ask: *"Still true? Changed? Lost interest?"* Use `AskUserQuestion` with options like:
- Still aligned
- Refined (small change — capture the refinement)
- Pivoted (different direction now — capture new direction)
- Dropped (no longer part of the vision)

If a vision item has been superseded, drop it from the vision doc rather than preserving it out of inertia.

**Pass 2 — Re-confirm what's actually built.** Briefly check the user's recollection against the most recent spec. If there's a mismatch ("I thought we already did X"), that's a contradiction to surface — either the spec is wrong, the code is wrong, or the memory is wrong. Don't bulldoze past it; resolve it.

**Pass 3 — Choose the next iteration.** Look at the open next-iteration issue and ask whether it still represents the most valuable next step. Possibilities:

- **Confirm**: the open issue is still right. Sharpen its spec.
- **Adjust**: the open issue is roughly right but the scope/shape has shifted. Update it.
- **Replace**: the open issue is no longer the right next step. Replace it with a new direction (close the old issue with a comment explaining why, file a new one).

### B.3. Surface contradictions aggressively

The whole point of this path is that the user expects to have forgotten things and/or changed their mind. Be explicit and direct when you see tension:

- **Vision-vs-current direction**: "The vision doc says X but you just said Y — do we update the vision or pull back to X?"
- **Spec-vs-code drift**: "The spec says the system does Z but the code appears to do W — which is the source of truth?"
- **Architecture conflict**: same handling as the NEW path — screen against settled decisions, surface the conflict, let the user decide.
- **Issue-vs-vision drift**: "The open next-iteration issue is heading toward thing-A, but in re-reading the vision it looks like thing-B would advance the headline experience more — worth a rethink?"

Don't editorialize on which the user should pick — just name the tension and let them choose.

### B.4. Write the artifacts

After the interview converges, produce:

1. **Update the next-iteration GitHub issue** with a concrete spec. Body references the new spec doc. Title may need updating. Use `gh api repos/<owner>/<repo>/issues/<N> -X PATCH -F "body=@/tmp/feature-spec-iter-body.md"` — never `mcp__github__issue_write`, which mangles markdown.

2. **Write a new spec file** at `docs/<feature-name>/NNN-<iteration-slug>-spec.md`, where `NNN` is the next zero-padded number after the highest existing spec file in the folder. Same shape as the MVP spec (Goal / In Scope / Out of Scope / Data Model / Behaviors / Integration Points / Extension Hooks / Acceptance Criteria). The numeric prefix lets the directory listing tell the story of the feature's evolution.

3. **Update `docs/<feature-name>/vision.md`** if anything in the vision shifted during Pass 1. Don't rewrite cosmetically — only touch what changed. If a section was dropped, delete it.

4. **File the next-next iteration GitHub issue** for what comes after the iteration you just speced. Same format as Path A's next-iteration issue. Block it on the iteration you just speced.

5. If you **replaced** the existing next-iteration issue, close the old one with a comment explaining the pivot.

Report back to the user with paths/URLs, the diff to the vision (sections updated/removed/added), and any contradictions that were surfaced but **not** resolved.

### B.5. Memory hygiene

Drop an `observation_add` call if the iteration surfaced a real design shift (e.g. "abandoned approach X because of constraint Y", "confirmed direction Z after considering W"). Skip if the iteration was just a straight continuation. Apply the same "save the why, not the what" rule.

## Common rules across both paths

### Issue body discipline

- **Always** write issue/PR bodies to `/tmp/<descriptive-name>.md` using the Write tool, then pass `--body-file`.
- **Never** use bash heredoc redirects.
- **Never** use `mcp__github__issue_write` to update issue bodies.
- For updating existing issues: `gh api repos/<owner>/<repo>/issues/N -X PATCH -F "body=@/tmp/<file>"`.

### Tracking discipline

- Every new issue must be linked to the relevant epic or tracking issue. If unclear which epic, ask the user before filing — don't create orphan issues.

### Doc style

- Markdown, no emoji unless the user adds them. Concise.
- The MVP spec is for an implementing engineer/agent — it should be implementable without further questions.
- The vision doc is for future-you (and future agents running this skill in ITERATE mode). Write it so it can survive being read cold months later.

### When to bail

Stop and ask the user instead of pressing on if:
- Phase 1 keeps shifting and a vision won't settle — suggest `/noodle-on` first to explore.
- The feature collides head-on with a CLAUDE.md settled decision and the user wants to override it — that's a design review conversation, not a spec interview.
- The user names a feature that already has an active in-progress branch/PR (`gh pr list`, `git branch -a`) — surface it; don't shadow live work.
