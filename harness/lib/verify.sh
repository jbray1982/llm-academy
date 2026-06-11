#!/usr/bin/env bash
# lib/verify.sh — M7: Stage verification (checks + generic plugin dispatch).
#
# Secret owned: how deterministic checks and plugin verdicts compose into a
# single pass/fail verdict. This is the one module that is irreducibly code
# rather than config — the composition logic cannot be expressed as data.
#
# Verdict JSON schema emitted to stdout:
#   {
#     "passed": true|false,
#     "checks": [{"command": "...", "exit_code": 0}, ...],
#     "plugins": {
#       "<plugin_name>": {"passed": true|false, "verdict": "pass"|"fail", "reason": "..."}
#     },
#     "warnings": [],
#     "failure_reason": "human-readable summary when passed=false"
#   }
#
# Pass rule: ALL checks exit 0 AND every plugin reported passed=true.
# A plugin that fails to return a structured verdict is a verify FAILURE —
# never a silent pass. This prevents a broken plugin from allowing bad code through.
#
# Built-in phase: "checks" is handled directly here and never dispatched to a plugin.
# Plugin phase: every other key in verify: {...} resolves through the plugin manifest
#   (harness manifest first, config-dir manifest overrides). config_load has already
#   validated every key is declared and its script exists/is executable.
#   An unknown key (not in any manifest) fails the stage with reason "plugin not found: <key>".

# ---------------------------------------------------------------------------
# verify_stage  stage_record_dir  run_dir  item  co_author  →  verdict JSON on stdout
#
# contract: Runs the verification policy for one stage attempt.
#   stage_record_dir is a directory containing the stage's config fields as
#   individual text files. Reads stage_record_dir/verify as the full verify:
#   block JSON object. The "checks" key is handled as a built-in (JSON array of
#   shell command strings). Every other key is resolved through the plugin
#   manifest and dispatched to the declared script path, which
#   receives (stage_record_dir, run_dir, item, co_author) and emits
#   {"passed":bool,"verdict":"pass"|"fail","reason":"..."} on stdout.
#   Always emits valid verdict JSON — callers must not parse stderr.
#
#   DESIGN QUESTION: should {item} substitution be applied to check commands
#   (so checks can include issue-number-specific gh commands)? Assumed yes,
#   but prompt_assemble is not called for checks — a simple string substitution
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

  # Initialize verdict tracking
  local checks_passed=true
  local checks_failed_count=0
  local -a checks_array=()
  local -A plugin_verdicts=()
  local -a failed_sources=()

  # -------------------------------------------------------------------------
  # Phase 1: Checks (built-in — never dispatched to a plugin).
  # -------------------------------------------------------------------------
  local checks_json=""
  if [ -f "$stage_record_dir/checks" ]; then
    checks_json="$(cat "$stage_record_dir/checks")"
  fi

  if [ -n "$checks_json" ] && [ "$checks_json" != "null" ]; then
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

        # Substitute {item}. Braces must be escaped — an unescaped closing brace
        # terminates the parameter expansion early (see prompt.sh for the full note).
        cmd="${cmd//\{item\}/$item}"

        # Run the command in subshell
        local exit_code=0
        (eval "$cmd") >/dev/null 2>&1 || exit_code=$?

        # Record result
        local check_obj
        check_obj="$(jq -n --arg cmd "$cmd" --arg code "$exit_code" '{command: $cmd, exit_code: ($code | tonumber)}')"
        checks_array+=("$check_obj")

        if [ "$exit_code" -ne 0 ]; then
          checks_passed=false
          checks_failed_count=$((checks_failed_count + 1))
        fi
      fi
    done
  fi

  if ! $checks_passed; then
    local total_count="${#checks_array[@]}"
    failed_sources+=("checks: $checks_failed_count of $total_count failed")
  fi

  # -------------------------------------------------------------------------
  # Phase 2: Plugin dispatch.
  # For each key in stage_record_dir/verify that is not "checks", locate and
  # invoke the corresponding lib/plugins/<key>.sh.
  # -------------------------------------------------------------------------
  local verify_json=""
  if [ -f "$stage_record_dir/verify" ]; then
    verify_json="$(cat "$stage_record_dir/verify")"
  fi

  if [ -n "$verify_json" ] && [ "$verify_json" != "null" ] && [ "$verify_json" != "{}" ]; then
    # Enumerate all keys in the verify block.
    local plugin_keys
    plugin_keys="$(printf '%s' "$verify_json" | jq -r 'keys[]' 2>/dev/null)" || true

    # Build the manifest registry once per stage (harness first, then
    # config-dir overrides). config_load has already validated every declared
    # key, so a missing resolution in the loop below means the stage was
    # invoked without going through config_load (a programming error) or a
    # manifest entry's script disappeared after preflight. Either way, fail loudly.
    local _h="${_HARNESS_DIR:-$HARNESS_DIR}"
    local _cd="${_CONFIG_DIR:-}"

    # Helper: load one manifest file into a local associative array,
    # returning "name=script_abs" lines on stdout.
    _resolve_manifest_scripts() {
      local mf="$1"
      local mdir
      mdir="$(dirname "$mf")"
      [ -f "$mf" ] || return 0
      local names
      names="$(yq '.plugins | keys | .[]' "$mf" 2>/dev/null)" || return 0
      local n
      while IFS= read -r n; do
        [ -z "$n" ] && continue
        local sr
        sr="$(yq ".plugins[\"${n}\"].script" "$mf" 2>/dev/null)" || continue
        sr="${sr#\"}"
        sr="${sr%\"}"
        [ -z "$sr" ] || [ "$sr" = "null" ] && continue
        if [[ "$sr" = /* ]]; then
          printf '%s=%s\n' "$n" "$sr"
        else
          printf '%s=%s/%s\n' "$n" "$mdir" "$sr"
        fi
      done <<< "$names"
    }

    declare -A _v_manifest=()
    local _entry
    while IFS= read -r _entry; do
      [ -z "$_entry" ] && continue
      _v_manifest["${_entry%%=*}"]="${_entry#*=}"
    done < <(_resolve_manifest_scripts "$_h/lib/plugins/manifest.yaml")
    if [ -n "$_cd" ] && [ -f "$_cd/lib/plugins/manifest.yaml" ]; then
      while IFS= read -r _entry; do
        [ -z "$_entry" ] && continue
        _v_manifest["${_entry%%=*}"]="${_entry#*=}"
      done < <(_resolve_manifest_scripts "$_cd/lib/plugins/manifest.yaml")
    fi

    while IFS= read -r plugin_key; do
      [ -z "$plugin_key" ] && continue
      # "checks" is the built-in — skip it here.
      [ "$plugin_key" = "checks" ] && continue

      # Write the key's JSON value to stage_record_dir/<key> for the plugin.
      local plugin_config
      plugin_config="$(printf '%s' "$verify_json" | jq -c --arg k "$plugin_key" '.[$k]' 2>/dev/null)" || true
      printf '%s' "${plugin_config:-null}" > "$stage_record_dir/$plugin_key"

      # Locate plugin via the manifest registry built above.
      local plugin_path=""
      if [ -n "${_v_manifest[$plugin_key]+set}" ]; then
        plugin_path="${_v_manifest[$plugin_key]}"
      fi

      if [ -z "$plugin_path" ]; then
        # No manifest declaration found — fail the stage with a named reason.
        plugin_verdicts["$plugin_key"]='{"passed":false,"verdict":"fail","reason":"plugin not found: '"$plugin_key"'"}'
        failed_sources+=("$plugin_key: plugin not found")
        continue
      fi

      # Invoke the plugin; capture stdout as verdict JSON.
      local raw_verdict=""
      local plugin_exit=0
      raw_verdict="$("$plugin_path" "$stage_record_dir" "$run_dir" "$item" "$co_author" 2>/dev/null)" \
        || plugin_exit=$?

      # Validate the plugin's output is parseable JSON with a "passed" field.
      local verdict_passed=""
      verdict_passed="$(printf '%s' "$raw_verdict" | jq -r '.passed // empty' 2>/dev/null)" || true

      if [ -z "$verdict_passed" ]; then
        # Plugin exited or returned JSON without a boolean 'passed' field.
        plugin_verdicts["$plugin_key"]='{"passed":false,"verdict":"fail","reason":"plugin did not return a valid verdict"}'
        failed_sources+=("$plugin_key: plugin did not return a valid verdict")
        continue
      fi

      # Store the plugin's own verdict (may be a fail verdict the plugin itself produced).
      plugin_verdicts["$plugin_key"]="$raw_verdict"

      if [ "$verdict_passed" != "true" ]; then
        local plugin_reason=""
        plugin_reason="$(printf '%s' "$raw_verdict" | jq -r '.reason // ""' 2>/dev/null)" || true
        failed_sources+=("$plugin_key: ${plugin_reason:-failed}")
      fi

    done <<< "$plugin_keys"
  fi

  # -------------------------------------------------------------------------
  # Phase 3: Compose final verdict.
  # -------------------------------------------------------------------------
  local all_passed=true
  if ! $checks_passed || [ "${#failed_sources[@]}" -gt 0 ]; then
    all_passed=false
  fi

  local failure_reason=""
  if ! $all_passed; then
    # Join all failure source descriptions with "; ".
    local first_fail=true
    local src
    for src in "${failed_sources[@]}"; do
      if $first_fail; then
        failure_reason="$src"
        first_fail=false
      else
        failure_reason="$failure_reason; $src"
      fi
    done
  fi

  # Build checks JSON array.
  local checks_json_out="["
  local first=true
  local check_obj
  for check_obj in "${checks_array[@]}"; do
    if $first; then
      checks_json_out="$checks_json_out$check_obj"
      first=false
    else
      checks_json_out="$checks_json_out,$check_obj"
    fi
  done
  checks_json_out="$checks_json_out]"

  # Build plugins JSON object from the associative array.
  local plugins_json="{"
  local first_plugin=true
  local pk
  for pk in "${!plugin_verdicts[@]}"; do
    local pv="${plugin_verdicts[$pk]}"
    if $first_plugin; then
      plugins_json="$plugins_json\"$pk\":$pv"
      first_plugin=false
    else
      plugins_json="$plugins_json,\"$pk\":$pv"
    fi
  done
  plugins_json="$plugins_json}"

  # Emit verdict JSON.
  jq -n \
    --argjson passed "$all_passed" \
    --argjson checks "$(printf '%s' "$checks_json_out")" \
    --argjson plugins "$(printf '%s' "$plugins_json")" \
    --arg failure_reason "$failure_reason" \
    '{
      passed: $passed,
      checks: $checks,
      plugins: $plugins,
      warnings: [],
      failure_reason: $failure_reason
    }' | jq -c '.'
}
