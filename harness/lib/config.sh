#!/usr/bin/env bash
# lib/config.sh — M2: YAML config loading and per-stage field access.
#
# Secret owned: that config is YAML at all, that yq is the parser, and the
# schema of every stage field. All other modules receive field values as plain
# strings via config_stage_field — they never see YAML syntax or the file path.
#
# Preflight contract: config_load validates at load time that the file is
# parseable, every non-pure-check stage has a readable prompt file, and every
# referenced schema file exists. Fail fast with a clear human-readable message.
#
# Path resolution for prompt/schema fields: relative to the config file's
# directory first, then the harness install dir. A consuming repo overrides a
# prompt by placing a same-named file next to its config.
#
# Special index -1: config_stage_field(-1, key) reads top-level config keys
# (backend, co_author, run_dir) rather than a stage.

# Internal: set by config_load, consumed by the other functions.
_CONFIG_PATH=""
_CONFIG_DIR=""
_HARNESS_DIR=""

# ---------------------------------------------------------------------------
# config_load  path
#
# contract: Parses the YAML config at path using yq, validates structure, and
#   stores the path for subsequent config_stage_field calls. Fails fast with
#   a clear error message (not a stack trace) if the file is missing, unparseable,
#   or references a prompt/schema file that does not exist. After a successful
#   call, config_stage_count and config_stage_field are valid.
# ---------------------------------------------------------------------------
config_load() {
  local path="$1"

  # Check yq is installed
  if ! command -v yq >/dev/null 2>&1; then
    echo "error: yq is required. Install: https://github.com/mikefarah/yq" >&2
    return 2
  fi

  # Check jq is installed
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required. Install: https://stedolan.github.io/jq/" >&2
    return 2
  fi

  # Check path exists and is readable
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    echo "error: config file not found or not readable: $path" >&2
    return 2
  fi

  # Check YAML is parseable
  if ! yq eval '.' "$path" >/dev/null 2>&1; then
    echo "error: config file is not valid YAML: $path" >&2
    return 2
  fi

  # Store the resolved absolute path
  _CONFIG_PATH="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  _CONFIG_DIR="$(dirname "$_CONFIG_PATH")"

  # _HARNESS_DIR is the harness install location — always derived from this
  # script's own path, not the config file location. A consuming repo may pass
  # --config from an arbitrary path; basing _HARNESS_DIR on that would break
  # the fallback prompt/schema resolution against the canonical harness install.
  _HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # Validate every stage: iterate 0..(N-1)
  local stage_count
  stage_count="$(yq '.stages | length' "$_CONFIG_PATH" 2>/dev/null)" || true
  if [ -z "$stage_count" ] || [ "$stage_count" = "null" ]; then
    stage_count=0
  fi

  local i
  for ((i = 0; i < stage_count; i++)); do
    # Check if this is a pure-check stage (no prompt field or null)
    local prompt_val
    prompt_val="$(yq ".stages[$i].prompt" "$_CONFIG_PATH" 2>/dev/null)" || true

    # Skip validation if prompt is null or missing (pure-check stage)
    if [ -n "$prompt_val" ] && [ "$prompt_val" != "null" ]; then
      # Strip JSON quotes
      prompt_val="${prompt_val#\"}"
      prompt_val="${prompt_val%\"}"

      # Resolve prompt path
      local resolved_prompt=""
      local prompt_basename
      prompt_basename="$(basename "$prompt_val")"

      if [ -f "$_CONFIG_DIR/$prompt_val" ]; then
        resolved_prompt="$_CONFIG_DIR/$prompt_val"
      elif [ -f "$_HARNESS_DIR/prompts/$prompt_basename" ]; then
        resolved_prompt="$_HARNESS_DIR/prompts/$prompt_basename"
      else
        echo "error: prompt file not found for stage $i: $prompt_val (checked $_CONFIG_DIR and $_HARNESS_DIR/prompts/)" >&2
        return 2
      fi
    fi

    # Check schema
    local schema_val
    schema_val="$(yq ".stages[$i].schema" "$_CONFIG_PATH" 2>/dev/null)" || true

    if [ -n "$schema_val" ] && [ "$schema_val" != "null" ]; then
      # Strip JSON quotes
      schema_val="${schema_val#\"}"
      schema_val="${schema_val%\"}"

      # Resolve schema path
      local resolved_schema=""
      local schema_basename
      schema_basename="$(basename "$schema_val")"

      if [ -f "$_CONFIG_DIR/$schema_val" ]; then
        resolved_schema="$_CONFIG_DIR/$schema_val"
      elif [ -f "$_HARNESS_DIR/schemas/$schema_basename" ]; then
        resolved_schema="$_HARNESS_DIR/schemas/$schema_basename"
      else
        echo "error: schema file not found for stage $i: $schema_val (checked $_CONFIG_DIR and $_HARNESS_DIR/schemas/)" >&2
        return 2
      fi
    fi
  done

  # Preflight plugin keys: for each stage's verify: block, every key other than
  # "checks" must be declared in a manifest and its declared script must exist
  # and be executable. An unknown key or missing script is a config error —
  # fail fast with a message that names the available plugin names.
  #
  # Manifest resolution order (config-dir wins on name conflicts):
  #   1. $_CONFIG_DIR/lib/plugins/manifest.yaml  (consuming repo)
  #   2. $_HARNESS_DIR/lib/plugins/manifest.yaml (harness-shipped)

  # Build a combined plugin registry: name -> absolute script path.
  # Process harness manifest first, then config-dir manifest (config-dir wins).
  declare -A _manifest_scripts=()

  _load_manifest() {
    local manifest_file="$1"
    local manifest_dir
    manifest_dir="$(dirname "$manifest_file")"

    if [ ! -f "$manifest_file" ]; then
      return 0
    fi

    # Read all plugin names from the manifest.
    local names
    names="$(yq '.plugins | keys | .[]' "$manifest_file" 2>/dev/null)" || true

    local pname
    while IFS= read -r pname; do
      [ -z "$pname" ] && continue

      local script_rel
      script_rel="$(yq ".plugins[\"${pname}\"].script" "$manifest_file" 2>/dev/null)" || true
      script_rel="${script_rel#\"}"
      script_rel="${script_rel%\"}"

      if [ -z "$script_rel" ] || [ "$script_rel" = "null" ]; then
        echo "error: manifest '$manifest_file' entry '$pname' has no script field" >&2
        return 2
      fi

      # Resolve script path relative to the manifest's own directory,
      # unless the path is already absolute.
      local script_abs
      if [[ "$script_rel" = /* ]]; then
        script_abs="$script_rel"
      else
        script_abs="$manifest_dir/$script_rel"
      fi

      # Later calls (config-dir) overwrite earlier ones (harness) — config-dir wins.
      _manifest_scripts["$pname"]="$script_abs"
    done <<< "$names"
    return 0
  }

  # Load harness manifest first (lower priority).
  _load_manifest "$_HARNESS_DIR/lib/plugins/manifest.yaml" || return 2

  # Load config-dir manifest second (higher priority — overrides harness entries).
  if [ -n "$_CONFIG_DIR" ] && [ -f "$_CONFIG_DIR/lib/plugins/manifest.yaml" ]; then
    _load_manifest "$_CONFIG_DIR/lib/plugins/manifest.yaml" || return 2
  fi

  # Validate every declared script exists and is executable.
  local declared_name declared_script
  for declared_name in "${!_manifest_scripts[@]}"; do
    declared_script="${_manifest_scripts[$declared_name]}"
    if [ ! -f "$declared_script" ]; then
      echo "error: plugin '$declared_name' declared in manifest but script not found: $declared_script" >&2
      return 2
    fi
    if [ ! -x "$declared_script" ]; then
      echo "error: plugin '$declared_name' declared in manifest but script is not executable: $declared_script" >&2
      return 2
    fi
  done

  # Build a sorted list of available plugin names for error messages.
  local available_plugins
  available_plugins="$(printf '%s\n' "${!_manifest_scripts[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"

  # Validate each stage's verify keys against the registry.
  local j
  for ((j = 0; j < stage_count; j++)); do
    local verify_block
    verify_block="$(yq ".stages[$j].verify" "$_CONFIG_PATH" -o=json 2>/dev/null)" || true
    if [ -z "$verify_block" ] || [ "$verify_block" = "null" ]; then
      continue
    fi

    local plugin_keys_in_verify
    plugin_keys_in_verify="$(printf '%s' "$verify_block" | jq -r 'keys[]' 2>/dev/null)" || true

    local pk
    while IFS= read -r pk; do
      [ -z "$pk" ] && continue
      [ "$pk" = "checks" ] && continue

      if [ -z "${_manifest_scripts[$pk]+set}" ]; then
        echo "error: unknown plugin key '$pk' in stage $j — not declared in any manifest. Available plugins: ${available_plugins:-none}" >&2
        return 2
      fi
    done <<< "$plugin_keys_in_verify"
  done

  return 0
}

# ---------------------------------------------------------------------------
# config_stage_count  →  integer on stdout
#
# contract: Returns the number of stages defined in the loaded config.
#   Always returns a non-negative integer; returns 0 if config has no stages.
#   Callers use this as the upper bound of the stage loop: 0..count-1.
# ---------------------------------------------------------------------------
config_stage_count() {
  local count
  count="$(yq '.stages | length' "$_CONFIG_PATH" 2>/dev/null)" || true
  if [ -z "$count" ] || [ "$count" = "null" ]; then
    count=0
  fi
  printf '%d' "$count"
}

# ---------------------------------------------------------------------------
# config_stage_field  stage_index  key  →  scalar value on stdout
#
# contract: Returns the scalar value of a single field for the stage at the
#   given 0-based index. Special index -1 reads top-level config keys
#   (backend, co_author, run_dir). Returns empty string for absent optional
#   fields — callers must not treat empty as an error.
#   For list-valued fields (tools, consumes, verify_checks, verify_judge),
#   returns a JSON array string so the caller can pass it to yq/jq or to
#   backend_invoke as-is.
#   For object-valued fields (skip_when, terminal_when, gate, verify_judge),
#   returns the raw JSON object string.
# ---------------------------------------------------------------------------
config_stage_field() {
  local stage_index="$1"
  local key="$2"

  # Determine the yq path
  local yq_path=""
  if [ "$stage_index" = "-1" ]; then
    # Global level
    yq_path=".$key"
  else
    # Stage level — handle nested paths
    case "$key" in
      verify)
        yq_path=".stages[$stage_index].verify"
        ;;
      verify_checks)
        yq_path=".stages[$stage_index].verify.checks"
        ;;
      verify_judge)
        yq_path=".stages[$stage_index].verify.judge"
        ;;
      recover_prompt)
        yq_path=".stages[$stage_index].recover.prompt"
        ;;
      recover_tools)
        yq_path=".stages[$stage_index].recover.tools"
        ;;
      *)
        yq_path=".stages[$stage_index].$key"
        ;;
    esac
  fi

  # Determine if this field needs JSON output mode
  local use_json=false
  case "$key" in
    skip_when|terminal_when|gate|verify|verify_judge|tools|consumes|verify_checks|recover_tools)
      use_json=true
      ;;
  esac

  # Get the value
  local val
  if $use_json; then
    val="$(yq "$yq_path" "$_CONFIG_PATH" -o=json 2>/dev/null)" || true
  else
    val="$(yq "$yq_path" "$_CONFIG_PATH" 2>/dev/null)" || true
  fi

  # Normalize "null" to empty string
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    printf ''
    return 0
  fi

  # For scalar fields, strip JSON quotes; for JSON fields, return as-is
  if ! $use_json; then
    # Strip surrounding JSON quotes if present
    val="${val#\"}"
    val="${val%\"}"
  fi

  # Resolve prompt/schema paths if needed
  if [ "$key" = "prompt" ] || [ "$key" = "recover_prompt" ]; then
    if [ -n "$val" ]; then
      local resolved=""
      if [ -f "$_CONFIG_DIR/$val" ]; then
        resolved="$_CONFIG_DIR/$val"
      elif [ -f "$_HARNESS_DIR/prompts/$(basename "$val")" ]; then
        resolved="$_HARNESS_DIR/prompts/$(basename "$val")"
      fi
      if [ -n "$resolved" ]; then
        printf '%s' "$resolved"
      else
        printf '%s' "$val"
      fi
    fi
  elif [ "$key" = "schema" ]; then
    if [ -n "$val" ]; then
      local resolved=""
      if [ -f "$_CONFIG_DIR/$val" ]; then
        resolved="$_CONFIG_DIR/$val"
      elif [ -f "$_HARNESS_DIR/schemas/$(basename "$val")" ]; then
        resolved="$_HARNESS_DIR/schemas/$(basename "$val")"
      fi
      if [ -n "$resolved" ]; then
        printf '%s' "$resolved"
      else
        printf '%s' "$val"
      fi
    fi
  else
    printf '%s' "$val"
  fi
}
