#!/usr/bin/env bash
# lib/verify.sh — M7: Stage verification (checks + optional LLM judge).
#
# Secret owned: how deterministic checks and an LLM judge compose into a
# single pass/fail verdict. This is the one module that is irreducibly code
# rather than config — the composition logic cannot be expressed as data.
#
# Verdict JSON schema emitted to stdout:
#   {
#     "passed": true|false,
#     "checks": [{"command":"...","exit_code":0},...],
#     "judge_verdict": "pass"|"fail"|null,
#     "judge_reason": "...",
#     "failure_reason": "human-readable summary when passed=false"
#   }
#
# Pass rule: ALL checks exit 0 AND (no judge configured OR judge returns "pass").
# A judge that fails to return a structured verdict is a verify FAILURE —
# never a silent pass. This prevents a broken judge from allowing bad code through.

# ---------------------------------------------------------------------------
# verify_stage  stage_record_dir  run_dir  item  co_author  →  verdict JSON on stdout
#
# contract: Runs the verification policy for one stage attempt.
#   stage_record_dir is a directory containing the stage's config fields as
#   individual text files (one per field: checks, judge, schema, backend, name).
#   Reads checks as a JSON array of shell command strings; runs each in order.
#   A non-zero exit from any check sets passed=false.
#   If a judge is configured (reads from stage_record_dir/judge as a JSON object
#   with prompt, criteria, schema fields): calls prompt_assemble + backend_invoke
#   + result_extract_field to get the judge verdict. A judge that cannot return
#   a structured {"verdict":"pass"|"fail"} is treated as failure.
#   Always emits valid verdict JSON — callers must not parse stderr.
#
#   DESIGN QUESTION: should {item} substitution be applied to check commands
#   (so checks can include issue-number-specific gh commands)? Assumed yes,
#   but prompt_assemble is not called for checks — a simple sed substitution
#   is used instead. Revisit if richer template grammar is needed in checks.
# ---------------------------------------------------------------------------
verify_stage() {
  local stage_record_dir="$1"
  local run_dir="$2"
  local item="$3"
  local co_author="$4"

  # Source necessary modules
  HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$HARNESS_DIR/lib/result.sh"
  # shellcheck source=/dev/null
  source "$HARNESS_DIR/lib/prompt.sh"
  # shellcheck source=/dev/null
  source "$HARNESS_DIR/lib/backend.sh"

  # Explicit temp file tracking — no EXIT trap to avoid overwriting executor's trap.
  # Both files are created only in the judge phase; we clean them up before returning.
  local _verify_prompt_file="" _verify_result_file=""
  _verify_cleanup() {
    rm -f "${_verify_prompt_file:-}" "${_verify_result_file:-}" 2>/dev/null || true
  }

  # Initialize verdict tracking
  local checks_passed=true
  local judge_passed=true
  local judge_verdict="null"
  local judge_reason=""
  local -a checks_array=()
  local failure_reason=""

  # Phase 1: Check phase
  local checks_json=""
  if [ -f "$stage_record_dir/checks" ]; then
    checks_json="$(cat "$stage_record_dir/checks")"
  fi

  if [ -n "$checks_json" ] && [ "$checks_json" != "null" ]; then
    # Iterate through checks array
    local check_count
    check_count="$(printf '%s' "$checks_json" | yq 'length' 2>/dev/null)" || true

    local i
    for ((i = 0; i < check_count; i++)); do
      local cmd
      cmd="$(printf '%s' "$checks_json" | yq ".[$i]" 2>/dev/null)" || true

      if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        # Strip surrounding JSON quotes
        cmd="${cmd#\"}"
        cmd="${cmd%\"}"

        # Substitute {item}
        cmd="${cmd//{item}/$item}"

        # Run the command in subshell
        local exit_code=0
        (eval "$cmd") >/dev/null 2>&1 || exit_code=$?

        # Record result
        local check_obj
        check_obj="$(jq -n --arg cmd "$cmd" --arg code "$exit_code" '{command: $cmd, exit_code: ($code | tonumber)}')"
        checks_array+=("$check_obj")

        # Mark passed=false if non-zero
        if [ "$exit_code" -ne 0 ]; then
          checks_passed=false
        fi
      fi
    done
  fi

  # Phase 2: Judge phase
  local judge_json=""
  if [ -f "$stage_record_dir/judge" ]; then
    judge_json="$(cat "$stage_record_dir/judge")"
  fi

  if [ -n "$judge_json" ] && [ "$judge_json" != "null" ]; then
    # Extract judge fields
    local judge_prompt
    judge_prompt="$(printf '%s' "$judge_json" | yq '.prompt' 2>/dev/null)" || true
    judge_prompt="${judge_prompt#\"}"
    judge_prompt="${judge_prompt%\"}"

    local judge_schema
    judge_schema="$(printf '%s' "$judge_json" | yq '.schema' 2>/dev/null)" || true
    judge_schema="${judge_schema#\"}"
    judge_schema="${judge_schema%\"}"

    if [ -n "$judge_prompt" ] && [ "$judge_prompt" != "null" ]; then
      # Resolve relative judge paths: config-dir override first, harness install fallback.
      # _HARNESS_DIR is set by config.sh (loaded before any stage runs).
      local _h="${_HARNESS_DIR:-$HARNESS_DIR}"
      local _cd="${_CONFIG_DIR:-}"
      if [ -n "$_cd" ] && [ -f "$_cd/$judge_prompt" ]; then
        judge_prompt="$_cd/$judge_prompt"
      elif [ -f "$_h/prompts/$(basename "$judge_prompt")" ]; then
        judge_prompt="$_h/prompts/$(basename "$judge_prompt")"
      fi
      if [ -n "$judge_schema" ] && [ "$judge_schema" != "null" ]; then
        if [ -n "$_cd" ] && [ -f "$_cd/$judge_schema" ]; then
          judge_schema="$_cd/$judge_schema"
        elif [ -f "$_h/schemas/$(basename "$judge_schema")" ]; then
          judge_schema="$_h/schemas/$(basename "$judge_schema")"
        fi
      fi

      # Assemble judge prompt
      _verify_prompt_file="$(mktemp "/tmp/harness-verify-XXXXXX")"

      if prompt_assemble "$judge_prompt" "$item" "$run_dir" "$co_author" > "$_verify_prompt_file"; then
        # Get backend from stage record
        local backend
        backend="$(cat "$stage_record_dir/backend" 2>/dev/null)" || true
        backend="${backend:-claude}"

        # Invoke backend
        _verify_result_file="$(mktemp "/tmp/harness-verify-XXXXXX")"

        if backend_invoke "$backend" "$_verify_prompt_file" "$judge_schema" "" > "$_verify_result_file" 2>/dev/null; then
          local envelope_json
          envelope_json="$(cat "$judge_result_file")"

          # Normalize and extract verdict
          local structured
          structured="$(result_normalize "$envelope_json")"

          judge_verdict="$(result_extract_field "$structured" "verdict")" || true
          judge_reason="$(result_extract_field "$structured" "reason")" || true

          # Validate verdict
          if [ "$judge_verdict" != "pass" ] && [ "$judge_verdict" != "fail" ]; then
            judge_verdict="fail"
            judge_reason="judge did not return a structured verdict"
            judge_passed=false
          else
            judge_passed=$([ "$judge_verdict" = "pass" ] && printf 'true' || printf 'false')
          fi
        else
          # Judge invocation failed
          judge_verdict="fail"
          judge_reason="judge invocation failed"
          judge_passed=false
        fi
      else
        # Judge prompt assembly failed
        judge_verdict="fail"
        judge_reason="judge prompt assembly failed"
        judge_passed=false
      fi
    fi
  fi

  # Compose final verdict
  local passed=true
  if ! $checks_passed || ([ "$judge_verdict" != "null" ] && ! $judge_passed); then
    passed=false
  fi

  # Build failure reason if not passed
  if ! $passed; then
    if ! $checks_passed; then
      failure_reason="One or more checks failed"
    elif ! $judge_passed; then
      failure_reason="Judge verdict: $judge_reason"
    fi
  fi

  # Build checks JSON array
  local checks_json_out="["
  local first=true
  for check_obj in "${checks_array[@]}"; do
    if [ "$first" = true ]; then
      checks_json_out="$checks_json_out$check_obj"
      first=false
    else
      checks_json_out="$checks_json_out,$check_obj"
    fi
  done
  checks_json_out="$checks_json_out]"

  # Clean up temp files before emitting verdict.
  _verify_cleanup

  # Emit verdict JSON
  jq -n \
    --argjson passed "$passed" \
    --argjson checks "$(printf '%s' "$checks_json_out")" \
    --arg judge_verdict "$judge_verdict" \
    --arg judge_reason "$judge_reason" \
    --arg failure_reason "$failure_reason" \
    '{
      passed: $passed,
      checks: $checks,
      judge_verdict: ($judge_verdict | if . == "null" then null else . end),
      judge_reason: $judge_reason,
      failure_reason: $failure_reason
    }' | jq -c '.'
}
