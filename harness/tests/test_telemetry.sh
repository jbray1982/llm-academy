#!/usr/bin/env bash
# tests/test_telemetry.sh — cases for lib/telemetry.sh (telemetry_record).
#
# Run via tests/run_tests.sh, which executes each test_ function in its own
# bash process. Each case writes into its own mktemp -d, cleaned up by an
# EXIT trap (safe because of the one-process-per-case execution model).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/telemetry.sh"

# _record run_dir failure_reason [usage_json]
# Records one stage attempt with fixed boilerplate fields. When usage_json is
# not passed, telemetry_record's 12th arg is genuinely omitted (not empty),
# exercising the ${12:-"{}"} default.
_record() {
  local run_dir="$1" failure_reason="$2"
  telemetry_record "$run_dir" run-1 item-1 stage-1 claude 1 failed '{"passed":false}' \
    "$failure_reason" 2026-06-11T00:00:00Z 2026-06-11T00:00:05Z "${@:3}"
}

test_failure_reason_round_trips_quotes_backslash_newline() {
  local tmp reason got lines
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"' EXIT
  reason=$'verify said "no" \\ twice\nsecond line of reason'

  _record "$tmp" "$reason" '{"input_tokens":5,"output_tokens":7}' || {
    echo "telemetry_record failed"; return 1; }
  local file="$tmp/telemetry.jsonl"

  # Exactly one line, and that line is valid JSON (i.e. compact JSONL — the
  # embedded newline must have been encoded, not written literally).
  lines="$(wc -l < "$file")"
  [ "$lines" -eq 1 ] || { echo "expected 1 line, got $lines"; return 1; }
  jq -e '.' "$file" >/dev/null || { echo "line is not valid JSON"; return 1; }

  got="$(jq -r '.failure_reason' "$file")"
  [ "$got" = "$reason" ] || {
    printf 'round-trip mismatch\n  sent: %q\n  got:  %q\n' "$reason" "$got"
    return 1
  }
}

test_usage_falls_back_to_empty_object_when_omitted() {
  local tmp got
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"' EXIT

  _record "$tmp" "plain reason" || { echo "telemetry_record failed"; return 1; }
  got="$(jq -c '.usage' "$tmp/telemetry.jsonl")"
  [ "$got" = "{}" ] || { echo "expected usage {}, got $got"; return 1; }
}

test_usage_falls_back_to_empty_object_when_invalid() {
  local tmp got
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"' EXIT

  _record "$tmp" "plain reason" 'not json at all' || {
    echo "telemetry_record failed"; return 1; }
  got="$(jq -c '.usage' "$tmp/telemetry.jsonl")"
  [ "$got" = "{}" ] || { echo "expected usage {}, got $got"; return 1; }
}
