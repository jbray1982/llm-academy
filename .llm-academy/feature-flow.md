# feature-flow — repo specifics

- Build: none. Test: none. **Skip the build/test gate** — this is a Markdown-only
  repo. "Verification" means re-reading the changed skill/agent prose for
  correctness and, when `install.sh` is touched, running it against a scratch
  target repo to confirm symlinks + overlays wire up.
- Default branch: `main`.
- Branch naming: `feature/issue-<number>`.
- Backlog file: `TODOS.md` (sections: P1/P2/P3/Deferred).
- Co-Authored-By: `Claude Opus 4.8 <noreply@anthropic.com>`.
- Labels: stock GitHub labels; no custom workflow labels in use yet.
- Tracking: link issues directly (no epics/milestones in use). Issues #2 (MVP,
  closed) and #3 (PowerShell port) are the live thread.
- **Before merging a new skill or agent:** confirm `install.sh` still propagates
  it. New `skills/*/` and `agents/*.md` are glob-discovered (no change needed); a
  new *kind* of artifact needs an install.sh update. See `CLAUDE.md`.
