---
name: noodle-on
description: Generate structured design proposals about a product aspect, saved sequentially in ./noodles
user-invocable: true
---

# Noodle On Skill

When the user invokes `/noodle-on [topic]`, generate thoughtful proposals and considerations about that aspect of the product, saved as a sequentially numbered markdown file.

## Process

### 1. Check Sequence Number
- Check if `./noodles/` directory exists, create if needed
- Read the `./noodles/` directory to find the highest numbered file
- Next file will be `{N+1:D3}-{topic-slug}.md` (e.g., `001-notification-system.md`, `002-user-roles.md`)
- If no files exist yet, start with `001`

### 2. Consider the Topic Deeply
Think through multiple angles:
- How this aspect fits into the current architecture and codebase
- Possible implementation approaches (at least 2-5 distinct angles)
- Trade-offs and design considerations
- Integration points with existing features and systems
- Alignment with project conventions and architecture
- Open questions worth exploring

### 3. Generate Proposals
Create 2-5 distinct proposals or angles on the topic. Each proposal should have:
- **Clear description** - What this approach entails
- **Pros** - Benefits and advantages (2-4 points)
- **Cons** - Drawbacks and challenges (2-4 points)
- **Complexity** - Low/Medium/High estimate
- **Dependencies** - What needs to exist first
- **Architectural fit** - How it aligns with established project patterns

If the direction is already very clear (e.g., PM has already made key decisions, or there's really only one sensible approach), you don't need to force multiple proposals. A single clear explanation of the approach along with open questions, edge cases, and implementation considerations is sufficient. Save the noodle in the same format but with just one "proposal" section.

### 4. Cross-Reference
- Note any related previous noodles
- Link bidirectionally when relevant

### 5. Save the Noodle
Create the markdown file in `./noodles/` using the template structure below.

### 6. Update FEATURE_LOG (if the project uses one)

If `FEATURE_LOG.md` exists at the repo root, update it after saving the noodle:

1. For each named concept the noodle explored, search FEATURE_LOG for its entry by name (fuzzy match).
2. If found: add the noodle file as a `See:` reference. Status stays `concept` until a vision doc exists — do not bump status.
3. If not found for any concept: flag it in an end-of-run summary:
   > "The following concepts surfaced in this noodle with no FEATURE_LOG entry: [list]. Want me to add them? I'll default conviction to `probably-need` — correct any that are wrong."
   Write confirmed entries as `[probably-need | concept]` with the noodle as `Surfaced:` provenance.
4. Skip silently if no FEATURE_LOG changes are needed, or if the project does not maintain a FEATURE_LOG. See `/feature-log` for the registry's format and vocabulary.

## File Template

```markdown
# Noodle #{N}: {Topic}

**Date**: {YYYY-MM-DD}
**Status**: Active

## Context

[Brief overview of what aspect of the product this explores and why it's worth considering]

## Proposals

### Proposal 1: {Descriptive Name}

**Description**: [What this approach entails - 2-3 sentences]

**Pros**:
- [Benefit 1]
- [Benefit 2]
- [Benefit 3]

**Cons**:
- [Drawback 1]
- [Drawback 2]

**Complexity**: Low/Medium/High

**Dependencies**: [What needs to exist first, or "None"]

**Architectural Fit**: [How this aligns with established project patterns]

### Proposal 2: {Descriptive Name}

[Same structure as Proposal 1]

### Proposal 3: {Descriptive Name}

[Same structure as Proposal 1]

## Open Questions

- [Question 1 - things to explore or decide]
- [Question 2]
- [Question 3]

## Related

- **Previous Noodles**: [Links to related previous noodles, or "None"]
- **Implemented**: [If portions implemented later, note which features — initially "Not yet implemented"]

## Additional Thoughts

[Any extra considerations, tangential ideas, or notes that don't fit in proposals]

```

## Response Format

After creating the noodle file, respond with:

```
Created noodle #{N} on {topic} with {X} proposals.
Saved to: ./noodles/{NNN}-{topic-slug}.md

Key proposals:
1. {Brief 1-line summary of proposal 1}
2. {Brief 1-line summary of proposal 2}
3. {Brief 1-line summary of proposal 3}

```

## Design Philosophy

**Noodles vs Plan Mode**:

- **Noodles** (this skill) - Quick proposal generation for a specific aspect, exploring multiple angles
  - Fast, structured brainstorming
  - Multiple concrete proposals with pros/cons
  - Saved chronologically for easy reference

- **Plan Mode** - Approved implementation plans ready for coding
  - Specific file changes and implementation steps
  - Requires user approval to proceed
  - Prescriptive and actionable

**When to use /noodle-on**:
- User wants quick structured proposals on a topic
- Need to compare 2-5 different approaches side-by-side
- Want a chronological record of what was considered when
- Topic is specific enough to generate concrete proposals

**When NOT to use /noodle-on**:
- Ready to implement (use plan mode)
- Just asking questions (answer directly)

## Notes

- Noodles are exploratory, not commitments
- They can be revisited and updated as thinking evolves
- Sequential numbering preserves chronology of exploration
- Keep proposals concrete and actionable, not abstract philosophizing
- Focus on architectural fit within the project's established patterns
