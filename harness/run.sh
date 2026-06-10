#!/usr/bin/env bash
# run.sh — M0: Harness entry point.
#
# Parses <item> and --config <path>, resolves paths to absolute, preflights
# that yq (mikefarah) is installed and the config file exists, then delegates
# to executor_run. Propagates the executor's exit code exactly — callers branch
# on the exit codes defined in lib/result.sh (0/75/1/2).
#
# Usage:
#   harness/run.sh <item> [--config <path>]
#
# Defaults:
#   --config harness/config/default.yaml (relative to this script's directory)
#
# Exit codes:
#   0  — all stages completed (some possibly skipped)
#   75 — deferred (EX_TEMPFAIL) — triage not-ready, decision-required, guard defer
#   1  — stage aborted or max retries exhausted
#   2  — config/usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Preflight: yq (mikefarah) is the one hard runtime dependency.
# ---------------------------------------------------------------------------
if ! command -v yq >/dev/null 2>&1; then
  echo "error: 'yq' is required but not installed." >&2
  echo "  Install with: brew install yq   (macOS/Linux via Homebrew)" >&2
  echo "  Or: snap install yq             (Linux via Snap)" >&2
  echo "  Or: https://github.com/mikefarah/yq/releases" >&2
  exit 2
fi

# jq is required for telemetry and verdict JSON assembly.
if ! command -v jq >/dev/null 2>&1; then
  echo "error: 'jq' is required but not installed." >&2
  echo "  Install with: brew install jq   (macOS/Linux via Homebrew)" >&2
  echo "  Or: https://stedolan.github.io/jq/download/" >&2
  exit 2
fi

# Verify it's mikefarah yq (not the Python yq), which supports the eval-all subcommand.
if ! yq --version 2>&1 | grep -qi 'mikefarah\|https://github.com/mikefarah'; then
  # mikefarah yq reports version as "yq (https://github.com/mikefarah/yq) version X.Y.Z"
  # If we can't confirm, do a functional check: eval-all is mikefarah-specific.
  if ! yq eval-all 'null' /dev/null >/dev/null 2>&1; then
    echo "error: found 'yq' but it does not appear to be mikefarah/yq." >&2
    echo "  This harness requires mikefarah yq (not the Python yq wrapper)." >&2
    echo "  Install: brew install yq  or  https://github.com/mikefarah/yq/releases" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ITEM=""
CONFIG=""
DEFAULT_CONFIG="$SCRIPT_DIR/config/default.yaml"

usage() {
  echo "Usage: $0 <item> [--config <path>]" >&2
  echo "  <item>           Work item identifier (e.g. GitHub issue number)" >&2
  echo "  --config <path>  Path to YAML config (default: harness/config/default.yaml)" >&2
  echo "" >&2
  echo "Exit codes: 0=completed, 75=deferred, 1=aborted, 2=config/usage error" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      [ $# -ge 2 ] || { echo "error: --config requires a path argument" >&2; usage; exit 2; }
      CONFIG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [ -n "$ITEM" ]; then
        echo "error: unexpected argument '$1' (item already set to '$ITEM')" >&2
        usage
        exit 2
      fi
      ITEM="$1"
      shift
      ;;
  esac
done

if [ -z "$ITEM" ]; then
  echo "error: <item> is required" >&2
  usage
  exit 2
fi

# Apply default config if not specified.
CONFIG="${CONFIG:-$DEFAULT_CONFIG}"

# Resolve config path to absolute.
case "$CONFIG" in
  /*) : ;;
  *)  CONFIG="$(pwd)/$CONFIG" ;;
esac

if [ ! -f "$CONFIG" ]; then
  echo "error: config file not found: $CONFIG" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Delegate to executor.
# ---------------------------------------------------------------------------
# shellcheck source=lib/executor.sh
source "$SCRIPT_DIR/lib/executor.sh"

executor_run "$CONFIG" "$ITEM"
