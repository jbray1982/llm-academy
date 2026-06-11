#!/usr/bin/env bash
# lib/executor.sh — M1: Pipeline composition root and retry/defer/abort state machine.
#
# Secret owned: the run control flow — stage ordering, retry/defer/abort
# transitions, and the recover-then-retry step. Every other module is called
# from here but never knows what stage comes next or how many retries remain.
#
# contract for executor_run:
#   Runs the full pipeline defined by config_path for the given item.
#   Composes config.sh, prompt.sh, backend.sh, result.sh, verify.sh,
#   handoff.sh, and telemetry.sh — never re-implementing their secrets.
#   Exit codes: EXIT_COMPLETED / EXIT_DEFERRED / EXIT_ABORTED / EXIT_CONFIG_ERROR
#   from result.sh.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/result.sh
source "$HARNESS_DIR/lib/result.sh"
# shellcheck source=lib/config.sh
source "$HARNESS_DIR/lib/config.sh"
# shellcheck source=lib/prompt.sh
source "$HARNESS_DIR/lib/prompt.sh"
# shellcheck source=lib/backend.sh
source "$HARNESS_DIR/lib/backend.sh"
# shellcheck source=lib/verify.sh
source "$HARNESS_DIR/lib/verify.sh"
# shellcheck source=lib/handoff.sh
source "$HARNESS_DIR/lib/handoff.sh"
# shellcheck source=lib/telemetry.sh
source "$HARNESS_DIR/lib/telemetry.sh"

# ---------------------------------------------------------------------------
# executor_run  config_path  item
#
# contract: Loads config_path, initialises a timestamped run directory, then
#   iterates each configured stage. For each stage:
#     - Evaluates skip_when (skips without LLM call if true).
#     - Assembles the prompt and invokes the backend.
#     - Normalises the result and merges structured output into facts.json.
#     - Evaluates terminal_when (clean deferred exit if true).
#     - Verifies via checks and optional LLM judge; evaluates gate predicate.
#     - Records telemetry for every attempt.
#     - On pass: writes produces handoff and advances.
#     - On fail: applies on_fail (retry/defer/abort); retry runs recover first.
#   Temp files are cleaned up via EXIT trap — callers see only exit codes.
# ---------------------------------------------------------------------------
executor_run() {
  local config_path="$1"
  local item="$2"

  # Temp file registry for EXIT trap cleanup.
  local -a _tmp_files=()
  _executor_cleanup() { rm -f "${_tmp_files[@]:-}" 2>/dev/null || true; }
  trap _executor_cleanup EXIT

  _mktmp() {
    local f
    f="$(mktemp "/tmp/harness-XXXXXX")"
    _tmp_files+=("$f")
    printf '%s' "$f"
  }

  # Step 1: Load config. Fail fast on any error.
  if ! config_load "$config_path"; then
    echo "executor: config_load failed for '$config_path'" >&2
    exit "$EXIT_CONFIG_ERROR"
  fi

  # Step 2: Initialise run directory.
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local run_id="${item}-${ts}"

  # config may set run_dir with {run_id} and {item} tokens.
  local run_dir_template
  run_dir_template="$(config_stage_field -1 run_dir 2>/dev/null)" || true
  if [ -z "$run_dir_template" ]; then
    run_dir_template=".harness/runs/{run_id}"
  fi

  local run_dir="${run_dir_template//\{run_id\}/$run_id}"
  run_dir="${run_dir//\{item\}/$item}"

  # Resolve relative run_dir against cwd (where the user invoked run.sh).
  case "$run_dir" in
    /*) : ;;
    *)  run_dir="$(pwd)/$run_dir" ;;
  esac

  mkdir -p "$run_dir/handoffs"
  mkdir -p "$run_dir/thinking"
  printf '{}' > "$run_dir/facts.json"
  : > "$run_dir/telemetry.jsonl"

  local co_author
  co_author="$(config_stage_field -1 co_author 2>/dev/null)" || true
  co_author="${co_author:-Co-Authored-By: Claude <noreply@anthropic.com>}"

  local global_backend
  global_backend="$(config_stage_field -1 backend 2>/dev/null)" || true
  global_backend="${global_backend:-claude}"

  # Step 3: Stage loop.
  local stage_count
  stage_count="$(config_stage_count)"

  local i
  for ((i = 0; i < stage_count; i++)); do

    # 3a: Read all stage fields.
    local stage_name stage_prompt stage_schema stage_tools stage_consumes
    local stage_produces stage_skip_when stage_terminal_when stage_gate
    local stage_verify stage_verify_checks stage_verify_judge stage_on_fail stage_max_retries
    local stage_recover_prompt stage_recover_tools stage_backend

    stage_name="$(config_stage_field "$i" name)"
    stage_prompt="$(config_stage_field "$i" prompt 2>/dev/null)" || true
    stage_schema="$(config_stage_field "$i" schema 2>/dev/null)" || true
    stage_tools="$(config_stage_field "$i" tools 2>/dev/null)" || true
    # Substitute {item} in tool patterns (e.g. "Bash(gh issue view {item}*)").
    stage_tools="${stage_tools//\{item\}/$item}"
    stage_consumes="$(config_stage_field "$i" consumes 2>/dev/null)" || true
    stage_produces="$(config_stage_field "$i" produces 2>/dev/null)" || true
    stage_skip_when="$(config_stage_field "$i" skip_when 2>/dev/null)" || true
    stage_terminal_when="$(config_stage_field "$i" terminal_when 2>/dev/null)" || true
    stage_gate="$(config_stage_field "$i" gate 2>/dev/null)" || true
    stage_verify="$(config_stage_field "$i" verify 2>/dev/null)" || true
    stage_verify_checks="$(config_stage_field "$i" verify_checks 2>/dev/null)" || true
    stage_verify_judge="$(config_stage_field "$i" verify_judge 2>/dev/null)" || true
    stage_on_fail="$(config_stage_field "$i" on_fail 2>/dev/null)" || true
    stage_on_fail="${stage_on_fail:-abort}"
    stage_max_retries="$(config_stage_field "$i" max_retries 2>/dev/null)" || true
    stage_max_retries="${stage_max_retries:-1}"
    stage_recover_prompt="$(config_stage_field "$i" recover_prompt 2>/dev/null)" || true
    stage_recover_tools="$(config_stage_field "$i" recover_tools 2>/dev/null)" || true
    stage_recover_tools="${stage_recover_tools//\{item\}/$item}"
    stage_backend="$(config_stage_field "$i" backend 2>/dev/null)" || true
    stage_backend="${stage_backend:-$global_backend}"

    echo "harness: stage[$i] $stage_name" >&2

    # Thinking log for this stage (appended across all retry attempts).
    local thinking_file="$run_dir/thinking/${stage_name}.log"

    # 3b: Evaluate skip_when.
    if [ -n "$stage_skip_when" ] && [ "$stage_skip_when" != "null" ]; then
      if result_eval_predicate "$run_dir" "$stage_skip_when"; then
        echo "harness: skipping stage '$stage_name' (skip_when matched)" >&2
        telemetry_record "$run_dir" "$run_id" "$item" "$stage_name" \
          "$stage_backend" "0" "skipped" "{}" "" \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{}"
        continue
      fi
    fi

    # 3c: Retry loop.
    local attempt=1
    local stage_passed=false

    while true; do
      local started_at
      started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      local verify_json="{}"
      local failure_reason=""
      local stage_status="failed"
      local invoke_ok=true
      local usage_json="{}"

      # 3c-ii: Assemble prompt (pure-check stages have no prompt file).
      local assembled_prompt_file=""
      if [ -n "$stage_prompt" ] && [ "$stage_prompt" != "null" ]; then
        assembled_prompt_file="$(_mktmp)"
        if ! prompt_assemble "$stage_prompt" "$item" "$run_dir" "$co_author" \
            > "$assembled_prompt_file"; then
          failure_reason="prompt_assemble failed"
          invoke_ok=false
        fi
      fi

      # 3c-iii: Invoke backend (skip for pure-check stages).
      local envelope_json="{}"
      local result_file=""
      if $invoke_ok && [ -n "$assembled_prompt_file" ]; then
        result_file="$(_mktmp)"
        if ! backend_invoke "$stage_backend" "$assembled_prompt_file" \
            "$stage_schema" "$stage_tools" "$thinking_file" > "$result_file"; then
          failure_reason="backend_invoke failed"
          invoke_ok=false
        else
          envelope_json="$(cat "$result_file")"
          usage_json="$(printf '%s' "$envelope_json" | jq -c '.usage // {}' 2>/dev/null)" || true
          usage_json="${usage_json:-{}}"
        fi
      fi

      # 3c-iv: Normalize and merge facts.
      local structured_json="{}"
      if $invoke_ok && [ -n "$assembled_prompt_file" ]; then
        structured_json="$(result_normalize "$envelope_json")"
        result_merge_facts "$run_dir" "$structured_json" || true
      fi

      # Capture raw text (for handoff prose) from envelope.
      local raw_text=""
      if [ -n "$envelope_json" ] && [ "$envelope_json" != "{}" ]; then
        raw_text="$(result_extract_field "$envelope_json" "result")" || true
      fi

      # 3c-v: Check terminal_when.
      if $invoke_ok && [ -n "$stage_terminal_when" ] && [ "$stage_terminal_when" != "null" ]; then
        if result_eval_predicate "$run_dir" "$stage_terminal_when"; then
          local terminal_status
          terminal_status="$(result_extract_field "$stage_terminal_when" "status")" || true
          terminal_status="${terminal_status:-deferred}"

          echo "harness: terminal_when matched on stage '$stage_name' — status=$terminal_status" >&2

          # Write produces handoff if configured.
          if [ -n "$stage_produces" ] && [ "$stage_produces" != "null" ]; then
            handoff_write "$run_dir" "$stage_produces" "$structured_json" "$raw_text" || true
          fi

          telemetry_record "$run_dir" "$run_id" "$item" "$stage_name" \
            "$stage_backend" "$attempt" "$terminal_status" "{}" "" \
            "$started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$usage_json"

          exit "$EXIT_DEFERRED"
        fi
      fi

      # 3c-vi: Verify (checks + optional judge) then evaluate gate predicate.
      local pass=true
      if $invoke_ok; then
        # Build a stage record dir for verify_stage to read.
        local stage_record_dir
        stage_record_dir="$(_mktmp)"
        rm -f "$stage_record_dir"
        mkdir -p "$stage_record_dir"
        _tmp_files+=("$stage_record_dir")

        # Write each stage field as an individual file (verify_stage's contract).
        printf '%s' "$stage_name"             > "$stage_record_dir/name"
        printf '%s' "${stage_verify:-{}}"     > "$stage_record_dir/verify"
        printf '%s' "$stage_verify_checks"    > "$stage_record_dir/checks"
        printf '%s' "$stage_verify_judge"     > "$stage_record_dir/judge"
        printf '%s' "$stage_schema"           > "$stage_record_dir/schema"
        printf '%s' "$stage_backend"          > "$stage_record_dir/backend"

        verify_json="$(verify_stage "$stage_record_dir" "$run_dir" "$item" "$co_author")" || true

        # Gate predicate: check the stage's own structured output.
        local gate_ok=true
        if [ -n "$stage_gate" ] && [ "$stage_gate" != "null" ]; then
          if ! result_eval_predicate "$run_dir" "$stage_gate"; then
            gate_ok=false
          fi
        fi

        # Compose: pass only if verify passed AND gate passed.
        local verify_passed
        verify_passed="$(result_extract_field "$verify_json" "passed")" || true
        if [ "$verify_passed" != "true" ] || ! $gate_ok; then
          pass=false
          failure_reason="$(result_extract_field "$verify_json" "failure_reason")" || true
          if ! $gate_ok && [ -z "$failure_reason" ]; then
            failure_reason="gate predicate not satisfied"
          fi
        fi
      else
        pass=false
      fi

      # Determine status for telemetry.
      if $pass; then
        stage_status="passed"
      fi

      # 3c-vii: Record telemetry.
      local ended_at
      ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      telemetry_record "$run_dir" "$run_id" "$item" "$stage_name" \
        "$stage_backend" "$attempt" "$stage_status" "$verify_json" \
        "$failure_reason" "$started_at" "$ended_at" "$usage_json"

      # 3c-viii: On pass.
      if $pass; then
        if [ -n "$stage_produces" ] && [ "$stage_produces" != "null" ]; then
          handoff_write "$run_dir" "$stage_produces" "$structured_json" "$raw_text" || true
        fi
        stage_passed=true
        break
      fi

      # 3c-ix: On fail — apply on_fail policy.
      echo "harness: stage '$stage_name' attempt $attempt failed: $failure_reason" >&2

      case "$stage_on_fail" in
        retry)
          if [ "$attempt" -le "$stage_max_retries" ]; then
            attempt=$((attempt + 1))

            # Run recover step if configured (assemble+invoke with recover prompt,
            # merge its output into facts so the retry sees the feedback).
            if [ -n "$stage_recover_prompt" ] && [ "$stage_recover_prompt" != "null" ]; then
              echo "harness: running recover step before retry $attempt" >&2
              local recover_prompt_file recover_result_file recover_envelope
              recover_prompt_file="$(_mktmp)"
              recover_result_file="$(_mktmp)"

              if prompt_assemble "$stage_recover_prompt" "$item" "$run_dir" "$co_author" \
                  > "$recover_prompt_file"; then
                if backend_invoke "$stage_backend" "$recover_prompt_file" \
                    "" "$stage_recover_tools" \
                    "$run_dir/thinking/${stage_name}-recover.log" > "$recover_result_file"; then
                  recover_envelope="$(cat "$recover_result_file")"
                  local recover_structured
                  recover_structured="$(result_normalize "$recover_envelope")"
                  result_merge_facts "$run_dir" "$recover_structured" || true
                else
                  echo "harness: recover backend_invoke failed — retrying without recover output" >&2
                fi
              else
                echo "harness: recover prompt_assemble failed — retrying without recover output" >&2
              fi
            fi

            continue  # retry the stage
          else
            # Max retries exhausted — treat as abort.
            echo "harness: max retries ($stage_max_retries) exhausted for '$stage_name'" >&2
            exit "$EXIT_ABORTED"
          fi
          ;;
        defer)
          echo "harness: deferring on stage '$stage_name' failure" >&2
          exit "$EXIT_DEFERRED"
          ;;
        abort|*)
          echo "harness: aborting on stage '$stage_name' failure" >&2
          exit "$EXIT_ABORTED"
          ;;
      esac
    done  # retry loop

    if ! $stage_passed; then
      # Should not be reachable (every fail path exits above), but be safe.
      echo "harness: stage '$stage_name' did not pass — aborting" >&2
      exit "$EXIT_ABORTED"
    fi
  done  # stage loop

  # Step 4: All stages complete.
  exit "$EXIT_COMPLETED"
}
