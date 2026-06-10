Act as BA committing and closing issue #{item}.

Review what was implemented:
{{handoff:review}}

1. Review all staged and unstaged changes (`git status`, `git diff`)
2. Stage all relevant changes (`git add`)
3. Commit with a message that:
   - Describes what was implemented
   - References the issue: closes #{item}
   - Ends with the co-author line: {co_author}
4. Close the issue with a comment summarizing what was done:
   `gh issue close {item} --comment "..."`

**IMPORTANT**: Do NOT push to remote. The outer loop handles branch merging and pushing.
