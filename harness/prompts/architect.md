Act as architect: Review issue #{item}.

## Triage context
{{handoff:triage}}

Recommend one approach:
- 'scaffold': Complex, needs lead-dev to scaffold interfaces + junior-dev to implement
- 'lead-dev': Too complex for junior-dev, lead-dev should implement directly
- 'junior': Simple enough for junior-dev to implement directly
- 'direct': Architect will implement directly
- 'decision-required': User-facing functionality ambiguity exists, requires human decision (not just code organization). This includes gameplay, UI/UX, content tooling, or any product-level choice.

If you make a product decision that should be reviewed:
- Set 'requires_product_review' to true
- Provide 'review_issue_title' and 'review_issue_body' for the follow-up issue

Output JSON with 'approach', 'reasoning', 'requires_product_review', 'review_issue_title', 'review_issue_body' fields.
