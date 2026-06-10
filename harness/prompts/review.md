Act as reviewer: Review the implementation for issue #{item}.

The architect's design and triage reasoning are available:
{{handoff:architect}}
{{handoff:triage}}

Check against:
- Correctness and completeness
- Code quality and conventions
- Test coverage

Output JSON with:
- 'status': 'approved' | 'blocking_issues' | 'non_blocking_issues'
- 'feedback': description of any issues found

If status is `non_blocking_issues`, create GitHub follow-up issues via
`gh issue create --label follow-up-issue` for each non-blocking problem.
