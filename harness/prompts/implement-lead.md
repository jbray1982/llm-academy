Act as lead developer for issue #{item}.

The architect's design is available:
{{handoff:architect}}

{{handoff:scaffold-lead}}

## Your role depends on approach

**If the scaffold-lead handoff above is present** (approach is `scaffold-lead`):
Junior-dev has already filled the simpler stubs from the scaffold manifest. Your job
is to implement the complex or high-risk parts that were explicitly reserved for you —
those flagged in the manifest as "lead-dev only", "non-obvious invariant", or similar.
Do not re-implement what junior already completed. Read the scaffolded files first to
see the current state, then implement only the flagged bodies.

**If the scaffold-lead handoff is absent** (approach is `lead-dev`):
This issue is too complex for junior-dev and has no separate scaffolding phase.
Implement the full solution directly from the architect's design. Read the issue and
any relevant source files, then implement all changes. Run tests if a test command is
available to confirm correctness.

In both cases: follow the architect's module boundaries and interface contracts exactly.
Do not simplify or merge modules — the decomposition is intentional.
