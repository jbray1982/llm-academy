#!/usr/bin/env bash
# lib/backend-claude.sh — M5 impl: Claude CLI backend.
#
# Secret owned (impl half): the exact claude CLI flags and invocation form.
# This is the ONLY file in the harness that names `claude` — every other
# module is backend-agnostic. Swapping to a different CLI is a new
# backend-<name>.sh file; no other file changes.
#
# Envelope contract: emits the raw JSON output produced by
# `claude --output-format json`. result_normalize (M6) knows the envelope
# path (.data.structured_output); this file does not parse it.
#
# tools_csv format: comma-separated tool names exactly as claude accepts them
# (e.g. "Read,Write,Edit,Bash(gh issue view *)"). backend_run passes each
# value as a separate --allowedTools argument because the claude CLI does not
# accept a single comma-joined string.

# ---------------------------------------------------------------------------
# backend_run  prompt_file  schema_file  tools_csv  →  envelope JSON on stdout
#
# contract: Translates the harness's generic invocation args into the claude
#   CLI command and emits the resulting JSON envelope to stdout.
#   - prompt_file: path to the assembled prompt; passed via $(cat ...) to -p.
#   - schema_file: if non-empty, adds --output-format json --json-schema <file>.
#     If empty, adds --output-format json without a schema (unstructured output).
#   - tools_csv: if non-empty, splits on comma and passes each as
#     --allowedTools <tool>. If empty, no --allowedTools flags are added.
#   Returns non-zero exit code on claude invocation failure; the envelope
#   JSON (which may describe the failure) is still emitted if available.
# ---------------------------------------------------------------------------
backend_run() {
  local prompt_file="$1"
  local schema_file="$2"
  local tools_csv="$3"

  # Build the claude command
  local cmd="claude -p \"\$(cat \"$prompt_file\")\" --output-format json"

  # Add schema if provided
  if [ -n "$schema_file" ] && [ "$schema_file" != "null" ]; then
    cmd="$cmd --json-schema \"$schema_file\""
  fi

  # Add tools if provided.
  # tools_csv is a JSON array string from config_stage_field (e.g. ["Read","Bash(gh *)"]).
  # Parse element-by-element with yq so tool names containing commas or parens are safe.
  if [ -n "$tools_csv" ] && [ "$tools_csv" != "null" ] && [ "$tools_csv" != "[]" ]; then
    if [[ "$tools_csv" == \[* ]]; then
      # JSON array — iterate with yq (outputs one bare string per line)
      while IFS= read -r tool; do
        [ -n "$tool" ] || continue
        cmd="$cmd --allowedTools \"$tool\""
      done < <(printf '%s' "$tools_csv" | yq '.[]' -)
    else
      # Fallback: legacy comma-separated string
      local IFS=','
      local -a _tools=($tools_csv)
      local IFS=' '
      for tool in "${_tools[@]}"; do
        tool="${tool#"${tool%%[![:space:]]*}"}"
        tool="${tool%"${tool##*[![:space:]]}"}"
        cmd="$cmd --allowedTools \"$tool\""
      done
    fi
  fi

  # Execute the command and emit raw JSON
  eval "$cmd"
}
