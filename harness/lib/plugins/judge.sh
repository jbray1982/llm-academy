#!/usr/bin/env bash
# lib/plugins/judge.sh — Verification plugin: LLM judge.
#
# Secret owned: how to assemble a judge prompt, invoke a backend, and
# normalize the result into a structured pass/fail verdict. This is the
# only module that knows the judge config schema (prompt, schema fields)
# and the path-resolution convention for judge assets.
#
# Plugin contract: invoked as
#   lib/plugins/judge.sh  stage_record_dir  run_dir  item  co_author
#
# Reads:  stage_record_dir/judge  — JSON object: {prompt, schema}
#         stage_record_dir/backend — backend name string
#
# Emits to stdout: {"passed": true|false, "verdict": "pass"|"fail", "reason": "..."}
# All diagnostic output goes to stderr.
#
# Failure contract: any failure (prompt assembly, backend invocation, invalid
# verdict) emits {"passed": false, "verdict": "fail", "reason": "<specific>"}.
# A broken judge always fails the stage — it never silently passes.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$HARNESS_DIR/lib/result.sh"
# shellcheck source=/dev/null
source "$HARNESS_DIR/lib/prompt.sh"
# shellcheck source=/dev/null
source "$HARNESS_DIR/lib/backend.sh"

stage_record_dir="$1"
run_dir="$2"
item="$3"
co_author="$4"

# ---------------------------------------------------------------------------
# _judge_fail  reason
#
# contract: Emits a failed verdict JSON to stdout and exits 0.
#   All failure paths call this so the caller always receives parseable JSON.
# ---------------------------------------------------------------------------
_judge_fail() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    '{"passed": false, "verdict": "fail", "reason": $reason}'
  exit 0
}

# Explicit temp file tracking — uses an EXIT trap, which is safe here because
# judge.sh runs as a subprocess, not sourced, so its trap does not interfere
# with the parent executor trap.
_judge_prompt_file=""
_judge_result_file=""
_judge_cleanup() {
  rm -f "${_judge_prompt_file:-}" "${_judge_result_file:-}" 2>/dev/null || true
}
trap _judge_cleanup EXIT

# Read judge config from stage_record_dir/judge
judge_json=""
if [ -f "$stage_record_dir/judge" ]; then
  judge_json="$(cat "$stage_record_dir/judge")"
fi

if [ -z "$judge_json" ] || [ "$judge_json" = "null" ]; then
  _judge_fail "judge config is missing or null"
fi

# Extract prompt and schema fields
judge_prompt="$(printf '%s' "$judge_json" | yq '.prompt' 2>/dev/null)" || true
judge_prompt="${judge_prompt#\"}"
judge_prompt="${judge_prompt%\"}"

judge_schema="$(printf '%s' "$judge_json" | yq '.schema' 2>/dev/null)" || true
judge_schema="${judge_schema#\"}"
judge_schema="${judge_schema%\"}"

if [ -z "$judge_prompt" ] || [ "$judge_prompt" = "null" ]; then
  _judge_fail "judge config missing required 'prompt' field"
fi

# Resolve prompt path: config-dir override first, then harness prompts fallback.
_h="${_HARNESS_DIR:-$HARNESS_DIR}"
_cd="${_CONFIG_DIR:-}"

if [ -n "$_cd" ] && [ -f "$_cd/$judge_prompt" ]; then
  judge_prompt="$_cd/$judge_prompt"
elif [ -f "$_h/prompts/$(basename "$judge_prompt")" ]; then
  judge_prompt="$_h/prompts/$(basename "$judge_prompt")"
fi

# Resolve schema path if present.
if [ -n "$judge_schema" ] && [ "$judge_schema" != "null" ]; then
  if [ -n "$_cd" ] && [ -f "$_cd/$judge_schema" ]; then
    judge_schema="$_cd/$judge_schema"
  elif [ -f "$_h/schemas/$(basename "$judge_schema")" ]; then
    judge_schema="$_h/schemas/$(basename "$judge_schema")"
  fi
fi

# Assemble judge prompt.
_judge_prompt_file="$(mktemp "/tmp/harness-judge-XXXXXX")"
if ! prompt_assemble "$judge_prompt" "$item" "$run_dir" "$co_author" > "$_judge_prompt_file"; then
  _judge_fail "judge prompt assembly failed"
fi

# Read backend from stage record.
backend=""
if [ -f "$stage_record_dir/backend" ]; then
  backend="$(cat "$stage_record_dir/backend")"
fi
backend="${backend:-claude}"

# Invoke backend.
_judge_result_file="$(mktemp "/tmp/harness-judge-XXXXXX")"
if ! backend_invoke "$backend" "$_judge_prompt_file" "${judge_schema:-}" "" > "$_judge_result_file" 2>/dev/null; then
  _judge_fail "judge invocation failed"
fi

# Read backend output and normalize.
envelope_json="$(cat "$_judge_result_file")"

structured="$(result_normalize "$envelope_json")"

judge_verdict="$(result_extract_field "$structured" "verdict")" || true
judge_reason="$(result_extract_field "$structured" "reason")" || true

# Validate verdict value.
if [ "$judge_verdict" != "pass" ] && [ "$judge_verdict" != "fail" ]; then
  _judge_fail "judge did not return a structured verdict"
fi

# Emit successful verdict.
passed="false"
if [ "$judge_verdict" = "pass" ]; then
  passed="true"
fi

jq -n \
  --argjson passed "$passed" \
  --arg verdict "$judge_verdict" \
  --arg reason "${judge_reason:-}" \
  '{"passed": $passed, "verdict": $verdict, "reason": $reason}'
