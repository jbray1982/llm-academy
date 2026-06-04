# review — repo specifics

- There is **no adversarial-pass script** in this project — run the primary
  reviewer pass only (or a cross-model pass if explicitly requested). Don't hunt
  for a script path.
- No build/test to run as part of review — this is a Markdown-only repo. Review
  the changed prose for correctness instead.
- Project-specific check categories, in priority order:
  1. Overlay footer present on any new/changed skill or agent.
  2. `requires:` / `requires-agents:` frontmatter accurate for any new
     skill→skill or skill→agent dependency.
  3. `install.sh` (and future `install.ps1`) still propagates the change — new
     `skills/*/` and `agents/*.md` are glob-covered; a new *kind* of artifact is
     the case to flag.
  4. Canonical definitions stayed generic — repo-specific assumptions belong in
     `.llm-academy/` overlays, not in the symlinked files.
