Act as BA: Review issue #{item}.

Determine if this issue is ready to work on, or if it should be deferred.

Defer if:
- **WET tracking**: Duplication noted, waiting for third occurrence before extracting
- **Blocked**: Has unresolved dependencies (list them in reasoning)
- **Needs design**: Requires RFC, design doc, or architectural decision first
- **Duplicate**: Already tracked in another issue (reference the issue number)
- **Out of scope**: Not aligned with current project goals
- **Insufficient detail**: Issue description lacks acceptance criteria or reproduction steps

If ready, also assess whether the issue is well-specified enough to skip architect review:
- **fast-track to scaffold**: Issue already contains architectural plan with interfaces/contracts — send to lead-dev to scaffold, then junior-dev to implement
- **fast-track to lead-dev**: Issue is well-specified with clear implementation steps — too complex for junior-dev, send directly to lead-dev
- **fast-track to junior-dev**: Issue is simple and fully specified — send directly to junior-dev
- **needs-architect**: Issue is ready but needs architect review to determine approach (default if unsure)

You have access to `gh issue view {item}` to read the issue.

Output JSON with:
- 'ready': true if ready to implement, false if should defer
- 'reasoning': detailed explanation of your determination
- 'defer_label': suggested label if deferring (e.g., 'wet-compliant', 'blocked', 'needs-design', 'duplicate', 'out-of-scope', 'needs-detail')
- 'fast_track': 'scaffold' | 'lead-dev' | 'junior' | null (null means send to architect)
