#!/usr/bin/env bash
# lib/backend.sh — M5 dispatch: Backend selection and routing.
#
# Secret owned (dispatch half): how a backend name maps to a backend
# implementation file. The executor calls backend_invoke with a name; this
# module sources the matching backend-<name>.sh and delegates to backend_run.
# Adding a new backend (e.g. openai) requires only a new backend-openai.sh file.
#
# No other module names a specific backend implementation; the name is a
# config-supplied string that flows through executor -> backend_invoke -> here.

_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# backend_invoke  backend_name  prompt_file  schema_file  tools_csv
#                 →  envelope JSON on stdout
#
# contract: Loads lib/backend-<backend_name>.sh and calls backend_run with
#   the remaining arguments. Returns the backend's envelope JSON on stdout.
#   If no backend-<backend_name>.sh exists, prints a clear error to stderr
#   (naming the file it looked for) and returns 2 (EXIT_CONFIG_ERROR).
#   schema_file and tools_csv may be empty strings — backends must handle
#   both absent and present values.
# ---------------------------------------------------------------------------
backend_invoke() {
  local backend_name="$1"
  local prompt_file="$2"
  local schema_file="$3"
  local tools_csv="$4"

  local backend_impl="$_HARNESS_DIR/lib/backend-${backend_name}.sh"

  # Check if backend implementation exists
  if [ ! -f "$backend_impl" ]; then
    echo "error: no backend implementation found: lib/backend-${backend_name}.sh" >&2
    return 2
  fi

  # Source the backend and call backend_run
  # shellcheck source=/dev/null
  source "$backend_impl"

  backend_run "$prompt_file" "$schema_file" "$tools_csv"
}
