Act as architect: Review issue #{item}.

## Triage context
{{handoff:triage}}

Recommend one approach:
- 'scaffold': Lead-dev scaffolds interfaces and a manifest; junior-dev implements all stubs.
- 'scaffold-lead': Lead-dev scaffolds interfaces and implements the complex/high-risk parts; junior-dev fills the remaining simpler stubs. Use when some bodies have non-obvious invariants or cross-cutting concerns that junior-dev should not own, but most of the work is mechanical enough to delegate.
- 'lead-dev': Too complex for junior-dev and no scaffolding phase needed; lead-dev implements everything directly.
- 'junior': Simple enough for junior-dev to implement directly from the issue description.
- 'direct': Architect implements directly (experimental or architectural spike).
- 'decision-required': User-facing functionality ambiguity exists, requires human decision (not just code organization). This includes gameplay, UI/UX, content tooling, or any product-level choice.

If you make a product decision that should be reviewed:
- Set 'requires_product_review' to true
- Provide 'review_issue_title' and 'review_issue_body' for the follow-up issue

Output JSON with 'approach', 'reasoning', 'requires_product_review', 'review_issue_title', 'review_issue_body' fields.
