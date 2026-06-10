#!/usr/bin/env bash
# lib/handoff.sh — M4: Handoff document read/write.
#
# Secret owned: the 3-part handoff document format. No other module knows
# what a handoff file looks like — they call handoff_write to produce one and
# handoff_read to consume one. This is also the sole git call site outside
# configured stage prompts (git diff --name-only for the changed-file list).
#
# Document layout (markdown):
#   ## Structured Output
#   ```json
#   <structured_json>
#   ```
#
#   ## Summary
#   <prose>
#
#   ## Changed Files
#   <git diff --name-only HEAD, one file per line>
#
# Files live at $run_dir/handoffs/<name>.md.

# ---------------------------------------------------------------------------
# handoff_write  run_dir  name  structured_json  prose
#
# contract: Writes the 3-part handoff document for the named stage to
#   $run_dir/handoffs/<name>.md. Overwrites any existing file with the same
#   name (last-writer-wins — retries can produce a fresh handoff).
#   structured_json may be "{}" if the stage produced no structured output.
#   prose may be empty string.
#   The changed-file section is always captured at write time via
#   `git diff --name-only HEAD`; if git is unavailable the section is omitted.
# ---------------------------------------------------------------------------
handoff_write() {
  local run_dir="$1"
  local name="$2"
  local structured_json="$3"
  local prose="$4"

  local handoff_file="$run_dir/handoffs/$name.md"

  # Get changed files via git diff
  local changed_files=""
  if git diff --name-only HEAD >/dev/null 2>&1; then
    changed_files="$(git diff --name-only HEAD 2>/dev/null)" || true
  fi

  # Build the handoff document
  {
    printf '## Structured Output\n'
    printf '```json\n'
    printf '%s\n' "$structured_json"
    printf '```\n'
    printf '\n'
    printf '## Summary\n'
    printf '%s\n' "$prose"
    printf '\n'
    printf '## Changed Files\n'
    if [ -n "$changed_files" ]; then
      printf '%s\n' "$changed_files"
    else
      printf 'No changes.\n'
    fi
  } > "$handoff_file"

  return 0
}

# ---------------------------------------------------------------------------
# handoff_read  run_dir  name  →  file contents on stdout
#
# contract: Reads $run_dir/handoffs/<name>.md and emits its full contents to
#   stdout. Returns empty string (exit 0) if the file does not exist — callers
#   who depend on a handoff being present should check the return value; the
#   template grammar ({{handoff:NAME}}) handles absence as empty expansion.
# ---------------------------------------------------------------------------
handoff_read() {
  local run_dir="$1"
  local name="$2"

  local handoff_file="$run_dir/handoffs/$name.md"

  # Return empty (exit 0) if file does not exist
  if [ ! -f "$handoff_file" ]; then
    return 0
  fi

  # Emit file contents
  cat "$handoff_file"
}
