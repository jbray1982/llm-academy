#!/usr/bin/env bash
# lib/telemetry.sh — M8: JSONL telemetry record serialization.
#
# Secret owned: the telemetry record schema and how it is serialized to disk.
# Every other module that wants to record a stage attempt calls telemetry_record
# with positional args — it never constructs JSONL itself.
#
# Schema (snake_case, pinned): run_id, item, stage, backend, attempt, status,
# verify, failure_reason, started_at, ended_at.
# Write-only in MVP; no reader is provided here.

# ---------------------------------------------------------------------------
# telemetry_record  run_dir  run_id  item  stage  backend  attempt  status
#                   verify_json  failure_reason  started_at  ended_at  [usage_json]
#
# contract: Appends exactly one JSONL line to $run_dir/telemetry.jsonl.
#   The line is always valid JSON even if individual string fields contain
#   quotes or newlines (jq encodes all string values). Fields match the pinned
#   schema exactly — adding or renaming a field here requires a schema version bump.
#   usage_json is optional; when present it is the .usage object from the
#   claude result event (input_tokens, output_tokens, cache_* counts).
#   Appends atomically enough for single-process pipelines (no file lock in MVP).
#   Never fails silently: if the append fails, prints to stderr and returns 1.
# ---------------------------------------------------------------------------
telemetry_record() {
  local run_dir="$1"
  local run_id="$2"
  local item="$3"
  local stage="$4"
  local backend="$5"
  local attempt="$6"
  local status="$7"
  local verify_json="$8"
  local failure_reason="$9"
  local started_at="${10}"
  local ended_at="${11}"
  # NB: the default must be quoted — in ${12:-{}} bash ends the expansion at
  # the FIRST '}', so a set value gets a literal '}' appended, corrupting JSON.
  local usage_json="${12:-"{}"}"

  # Normalise usage_json: fall back to {} if empty or invalid.
  if [ -z "$usage_json" ] || ! printf '%s' "$usage_json" | jq -e '.' >/dev/null 2>&1; then
    usage_json="{}"
  fi

  local telemetry_file="$run_dir/telemetry.jsonl"

  # Build JSON line using jq (jq encodes all string values correctly)
  local json_line
  json_line="$(jq -nc \
    --arg run_id "$run_id" \
    --arg item "$item" \
    --arg stage "$stage" \
    --arg backend "$backend" \
    --arg attempt "$attempt" \
    --arg status "$status" \
    --arg failure_reason "$failure_reason" \
    --arg started_at "$started_at" \
    --arg ended_at "$ended_at" \
    --argjson verify "$verify_json" \
    --argjson usage "$usage_json" \
    '{
      run_id: $run_id,
      item: $item,
      stage: $stage,
      backend: $backend,
      attempt: ($attempt | tonumber),
      status: $status,
      failure_reason: $failure_reason,
      started_at: $started_at,
      ended_at: $ended_at,
      verify: $verify,
      usage: $usage
    }')"

  # Append to telemetry file
  if printf '%s\n' "$json_line" >> "$telemetry_file" 2>/dev/null; then
    return 0
  else
    echo "telemetry_record: failed to append to $telemetry_file" >&2
    return 1
  fi
}
