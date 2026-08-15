# feature-flow — repo specifics

- Build: none. Test: none (no automated test infrastructure — issue #32).
  **Verification gate** instead of build/test:
  - Prose changes (skills/agents/docs): re-read the changed definition for
    correctness and check the overlay footer + `requires:` frontmatter.
  - Shell changes (`install.sh`, `harness/**/*.sh`): `bash -n` each changed
    script; for install.sh changes, run it against a scratch target repo; for
    harness changes, a `harness/run.sh` dry run when feasible.
- Default branch: `main`.
- Branch naming: `feature/issue-<number>`.
- Backlog file: `TODOS.md` (sections: P1/P2/P3/Deferred).
- Co-Authored-By: `Claude Fable 5 <noreply@anthropic.com>`.
- Labels: `tech-debt` and `follow-up-issue` exist; otherwise stock GitHub labels.
- Tracking: link issues directly (no epics/milestones in use).
- **Headless twin:** `harness/run.sh <issue>` runs this same pipeline
  (triage → architect → implement → review → commit) unattended, driven by
  `harness/config/default.yaml`. When changing this skill's flow, consider
  whether the harness preset/prompts need the matching change.
- **Before merging a new skill or agent:** confirm `install.sh` still
  propagates it. New `skills/*/` and `agents/*.md` are glob-discovered (no
  change needed); a new *kind* of artifact needs an install.sh update (the
  harness needed `install_harness()`). See `CLAUDE.md`.
