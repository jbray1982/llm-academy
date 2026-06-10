#!/usr/bin/env bash
# lib/result.sh — M6: Result vocabulary, exit-code contract, facts store, predicate evaluation.
#
# Secret owned: the status enum, exit codes, the backend envelope shape, and
# all predicate evaluation (skip_when / terminal_when / gate). Every other module
# that needs to branch on a status or read the envelope delegates here.
#
# No globals cross module lines. All state lives in $run_dir/facts.json.

# Exit-code contract — the only place in the harness that defines these values.
# Callers branch on executor_run's exit code using these symbols.
EXIT_COMPLETED=0    # all stages ran (some possibly skipped)
EXIT_DEFERRED=75    # EX_TEMPFAIL: clean stop, retry later (triage not-ready, decision-required, guard defer)
EXIT_ABORTED=1      # stage aborted or max retries exhausted
EXIT_CONFIG_ERROR=2 # config/usage error; fail-fast at load time

# ---------------------------------------------------------------------------
# result_merge_facts  run_dir  structured_json
#
# contract: Merges every top-level field of structured_json into
#   $run_dir/facts.json using last-writer-wins semantics. The facts store is
#   the single shared read surface for all skip_when / terminal_when / gate
#   predicates; centralising the write here ensures atomic, consistent state.
#   Empty or missing structured_json is a no-op — callers need not guard.
# ---------------------------------------------------------------------------
result_merge_facts() {
  local run_dir="$1"
  local structured_json="${2:-}"
  local facts_file="$run_dir/facts.json"

  # Empty input is explicitly handled — no-op, not an error.
  if [ -z "$structured_json" ] || [ "$structured_json" = "null" ] || [ "$structured_json" = "{}" ]; then
    return 0
  fi

  # Ensure facts file exists and is valid JSON.
  if [ ! -f "$facts_file" ] || [ ! -s "$facts_file" ]; then
    printf '{}' > "$facts_file"
  fi

  # Merge atomically: read existing, merge, write to tmp, mv into place.
  local tmp_file
  tmp_file="$(mktemp "${facts_file}.XXXXXX")"

  # yq merge: load facts, overlay structured_json on top (last-writer-wins per field).
  # Use yq's ireduce to merge two JSON objects.
  local existing
  existing="$(cat "$facts_file")"

  # Use yq to merge: echo the incoming json and merge into existing facts.
  # yq eval-all 'select(fi==0) * select(fi==1)' merges two YAML/JSON docs.
  printf '%s\n%s\n' "$existing" "$structured_json" \
    | yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' - -o=json \
    > "$tmp_file" 2>/dev/null

  if [ $? -ne 0 ]; then
    rm -f "$tmp_file"
    echo "result_merge_facts: yq merge failed — facts.json unchanged" >&2
    return 1
  fi

  mv "$tmp_file" "$facts_file"
}

# ---------------------------------------------------------------------------
# result_get_fact  run_dir  field_name  →  value on stdout
#
# contract: Reads a single top-level field from $run_dir/facts.json.
#   Returns empty string if the field is absent or facts.json doesn't exist.
#   Never fails — callers can always test the output string without error
#   handling.
# ---------------------------------------------------------------------------
result_get_fact() {
  local run_dir="$1"
  local field_name="$2"
  local facts_file="$run_dir/facts.json"

  if [ ! -f "$facts_file" ]; then
    return 0
  fi

  local val
  val="$(yq ".$field_name" "$facts_file" -o=json 2>/dev/null)" || true

  # yq returns "null" for absent fields; normalise to empty string.
  if [ "$val" = "null" ] || [ -z "$val" ]; then
    return 0
  fi

  # Strip surrounding JSON string quotes if present (for plain scalar values).
  val="${val#\"}"
  val="${val%\"}"
  printf '%s' "$val"
}

# ---------------------------------------------------------------------------
# result_eval_predicate  run_dir  predicate_json  →  0 (true) or 1 (false)
#
# contract: Evaluates one predicate against the facts store and returns a
#   bash exit code. Supported predicate shapes:
#     {"field":"f","equals":"v"}              — fact f == v
#     {"field":"f","negate":true,"equals":"v"} — fact f != v
#     {"field":"f","in":["a","b"]}            — fact f is in the set
#     {"command":"shell cmd"}                 — zero exit = predicate true
#   Field comparisons read from facts.json via result_get_fact; the "null"
#   string matches a missing/null fact. Command predicates run in a subshell
#   with no side effects visible to the caller.
#   Returns 0 = predicate is true, 1 = predicate is false.
# ---------------------------------------------------------------------------
result_eval_predicate() {
  local run_dir="$1"
  local predicate_json="$2"

  if [ -z "$predicate_json" ] || [ "$predicate_json" = "null" ]; then
    return 1  # absent predicate = false (don't skip, don't terminate)
  fi

  # Detect predicate type.
  local pred_type
  pred_type="$(printf '%s' "$predicate_json" | yq '.command // ""' -o=json 2>/dev/null | tr -d '"')" || true

  if [ -n "$pred_type" ]; then
    # Command predicate: run it; zero exit = true.
    (eval "$pred_type") >/dev/null 2>&1
    return $?
  fi

  # Field predicate.
  local field_name
  field_name="$(printf '%s' "$predicate_json" | yq '.field' -o=json 2>/dev/null | tr -d '"')" || true

  local actual_val
  actual_val="$(result_get_fact "$run_dir" "$field_name")"
  # Normalise absent fact to the string "null" for comparison.
  [ -z "$actual_val" ] && actual_val="null"

  local negate
  negate="$(printf '%s' "$predicate_json" | yq '.negate // false' 2>/dev/null)" || true

  # Check for "in" array predicate.
  local in_array
  in_array="$(printf '%s' "$predicate_json" | yq '.in // ""' -o=json 2>/dev/null)" || true

  if [ -n "$in_array" ] && [ "$in_array" != '""' ] && [ "$in_array" != "null" ]; then
    # Check if actual_val is in the JSON array.
    local match
    match="$(printf '%s' "$in_array" | yq ".[] | select(. == \"$actual_val\")" 2>/dev/null)" || true
    if [ -n "$match" ]; then
      [ "$negate" = "true" ] && return 1 || return 0
    else
      [ "$negate" = "true" ] && return 0 || return 1
    fi
  fi

  # Equals predicate.

  local matches=1  # default: no match
  if [ "$actual_val" = "$equals_val" ]; then
    matches=0
  fi

  if [ "$negate" = "true" ]; then
    # Negate: match becomes no-match and vice versa.
    if [ "$matches" -eq 0 ]; then
      return 1
    else
      return 0
    fi
  fi

  return "$matches"
}

# ---------------------------------------------------------------------------
# result_normalize  envelope_json  →  structured_output JSON on stdout
#
# contract: Extracts .data.structured_output from the claude envelope JSON.
#   Returns "{}" if the field is absent or null. This is the ONLY place in
#   the harness that knows the envelope path, so a future backend change
#   (different envelope shape) is a one-line edit here.
# ---------------------------------------------------------------------------
result_normalize() {
  local envelope_json="$1"

  if [ -z "$envelope_json" ]; then
    printf '{}'
    return 0
  fi

  local structured
  structured="$(printf '%s' "$envelope_json" \
    | yq '.data.structured_output // {}' -o=json 2>/dev/null)" || true

  if [ -z "$structured" ] || [ "$structured" = "null" ]; then
    printf '{}'
    return 0
  fi

  printf '%s' "$structured"
}

# ---------------------------------------------------------------------------
# result_extract_field  json  field_path  →  value on stdout
#
# contract: Generic field extractor for any JSON blob and dot-notation path.
#   Used by verify.sh to read the judge verdict field and by the executor to
#   read terminal_when status overrides. Returns empty string if absent.
#   Never fails — callers can test the output string directly.
# ---------------------------------------------------------------------------
result_extract_field() {
  local json="$1"
  local field_path="$2"

  if [ -z "$json" ] || [ -z "$field_path" ]; then
    return 0
  fi

  local val
  val="$(printf '%s' "$json" | yq ".$field_path" -o=json 2>/dev/null)" || true

  if [ "$val" = "null" ] || [ -z "$val" ]; then
    return 0
  fi

  # Strip surrounding quotes for plain scalars.
  val="${val#\"}"
  val="${val%\"}"
  printf '%s' "$val"
}
