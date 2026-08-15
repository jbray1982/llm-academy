# review — repo specifics

- No pinned wrapper — this project has not adopted a
  `tools/adversarial-review-pass.sh` (or equivalent), and doesn't need one.
  Step 3's probe covers us.
- So: probe `command -v` for the default candidate CLIs (`codex`, `gemini`) at
  run time and, if one is reachable, invoke it directly with the adversarial
  prompt from Step 3. Re-probe every session — whether a CLI is currently
  installed is a point-in-time fact, not something this file should assert one
  way or the other.
- No build/test to run as part of review (no automated tests — issue #32).
  For changed shell scripts (`install.sh`, `harness/**/*.sh`), run `bash -n`
  as a minimum syntax gate; shellcheck is NOT installed. For prose, review the
  changed definition text for correctness.
- Project-specific check categories, in priority order:
  1. Overlay footer present on any new/changed skill or agent.
  2. `requires:` / `requires-agents:` frontmatter accurate for any new
     skill→skill or skill→agent dependency.
  3. `install.sh` (and future `install.ps1`) still propagates the change —
     new `skills/*/` and `agents/*.md` are glob-covered; `harness/` is carried
     by `install_harness()`; a new *kind* of artifact is the case to flag.
  4. Canonical definitions stayed generic — repo-specific assumptions belong
     in `.llm-academy/` overlays (or `.harness/config.yaml` for the harness),
     not in the symlinked files.
  5. Harness changes: config schema (`harness/config/README.md`), prompts,
     and JSON schemas stay in sync — a stage added to default.yaml needs its
     prompt file and (if structured) schema file.
