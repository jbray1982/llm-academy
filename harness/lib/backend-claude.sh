#!/usr/bin/env bash
# lib/backend-claude.sh — M5 impl: Claude CLI backend.
#
# Secret owned (impl half): the exact claude CLI flags and invocation form.
# This is the ONLY file in the harness that names `claude` — every other
# module is backend-agnostic. Swapping to a different CLI is a new
# backend-<name>.sh file; no other file changes.
#
# Output: uses --output-format stream-json --verbose. The JSONL event stream is
# processed inline. Every meaningful event (session init, assistant text,
# thinking, tool calls, tool results, final result) is rendered as a labeled
# block on stderr so a watcher can tell at a glance whether the agent is doing
# anything or has stalled. Thinking text is also appended to thinking_file.
# The final result event has the same top-level shape as --output-format json
# (.result, .usage, .session_id, etc.), so M6 result_normalize is unchanged.
#
# Structured output: we deliberately do NOT pass --json-schema. In claude
# 2.1.172 that flag hangs the CLI indefinitely (no events, no output, in both
# json and stream-json formats — reproducible with a minimal schema). Instead
# the prompts instruct the model to emit JSON, and result_normalize parses it
# out of .result. schema_file is accepted for interface compatibility but is
# only used as a hint in logging.
#
# Stdin: redirected from /dev/null. claude in --print mode otherwise waits on
# stdin for stream-json input and can block the whole pipeline.
#
# tools_csv format: comma-separated tool names exactly as claude accepts them
# (e.g. "Read,Write,Edit,Bash(gh issue view *)"). backend_run passes each
# value as a separate --allowedTools argument because the claude CLI does not
# accept a single comma-joined string.

# ---------------------------------------------------------------------------
# _block  color  header  body  → renders a labeled block to stderr
#
# Header is printed in `color`; body lines are dim and word-wrapped. A blank
# body prints just the header line (useful for terse events).
# ---------------------------------------------------------------------------
_block() {
  local color="$1" header="$2" body="$3"
  local width=78
  local inner=$((width - 2))
  local RESET=$'\033[0m' DIM=$'\033[2m'

  printf '%s\n' "${color}┌─ ${header}${RESET}" >&2
  if [ -n "$body" ]; then
    local para
    while IFS= read -r para; do
      if [ -z "$para" ]; then
        printf '%s\n' "${DIM}│${RESET}" >&2
        continue
      fi
      local chunk
      while IFS= read -r chunk; do
        printf '%s\n' "${DIM}│ ${chunk}${RESET}" >&2
      done < <(printf '%s\n' "$para" | fold -s -w "$inner")
    done <<< "$body"
  fi
  printf '%s\n' "${color}└${RESET}" >&2
}

# ---------------------------------------------------------------------------
# _render_event  stage_label  event_json  thinking_file
#
# Translates one stream-json event into zero or more stderr blocks, and appends
# any thinking text to thinking_file. Bodies are passed base64-encoded out of
# jq so embedded newlines/tabs survive the line-based read.
# ---------------------------------------------------------------------------
_render_event() {
  local stage_label="$1" line="$2" thinking_file="$3"

  # Colors keyed by event kind.
  local C_INIT=$'\033[34m' C_TEXT=$'\033[36m' C_THINK=$'\033[2m'
  local C_TOOL=$'\033[33m' C_RESULT_OK=$'\033[32m' C_RESULT_ERR=$'\033[31m'

  local render
  render="$(printf '%s' "$line" | jq -rc '
    def trunc(n): if (. | length) > n then .[0:n] + " …[truncated]" else . end;
    if .type == "system" and .subtype == "init" then
      "init\t" + ("model=" + (.model // "?") + "  session=" + ((.session_id // "?")[0:8])) + "\t" + ("" | @base64)
    elif .type == "assistant" then
      ( .message.content[]? |
        if .type == "thinking" then
          "think\t💭 thinking\t" + ((.thinking // "") | trunc(4000) | @base64)
        elif .type == "text" then
          "text\t💬 says\t" + ((.text // "") | trunc(4000) | @base64)
        elif .type == "tool_use" then
          "tool\t🔧 " + (.name // "tool") + "\t" + (((.input // {}) | tostring) | trunc(800) | @base64)
        else empty end )
    elif .type == "user" then
      ( .message.content[]? | select(.type == "tool_result") |
        "toolresult\t📥 tool result\t" +
        (((.content // "") | if type == "array" then (map(.text // "") | join(" ")) else . end) | trunc(800) | @base64) )
    elif .type == "result" then
      (if (.is_error // false) then "result-err" else "result-ok" end) + "\t-\t" +
      (("out_tokens=" + ((.usage.output_tokens // 0) | tostring) +
        "  cost=$" + ((.total_cost_usd // 0) | tostring)) | @base64)
    else empty end
  ' 2>/dev/null)" || return 0

  [ -z "$render" ] && return 0

  local kind header b64 body color
  while IFS=$'\t' read -r kind header b64; do
    [ -z "$kind" ] && continue
    body="$(printf '%s' "$b64" | base64 -d 2>/dev/null)"
    # Suppress empty thinking/text blocks — they are noise, not activity.
    if [ -z "$body" ] && { [ "$kind" = "think" ] || [ "$kind" = "text" ]; }; then
      continue
    fi
    case "$kind" in
      init)       color="$C_INIT" ;;
      text)       color="$C_TEXT" ;;
      think)
        color="$C_THINK"
        [ -n "$thinking_file" ] && [ -n "$body" ] && printf '%s\n---\n' "$body" >> "$thinking_file"
        ;;
      tool)       color="$C_TOOL" ;;
      toolresult) color="$C_TOOL" ;;
      result-ok)  color="$C_RESULT_OK"; header="✓ done" ;;
      result-err) color="$C_RESULT_ERR"; header="✗ error" ;;
      *)          color=$'\033[0m' ;;
    esac
    _block "$color" "[$stage_label] $header" "$body"
  done <<< "$render"
}

# ---------------------------------------------------------------------------
# backend_run  prompt_file  schema_file  tools_csv  [thinking_file]
#              →  result event JSON on stdout
#
# contract: Translates the harness's generic invocation args into the claude
#   CLI command using --output-format stream-json and processes the event stream.
#   - prompt_file: path to the assembled prompt; passed via $(cat ...) to -p.
#   - schema_file: accepted but NOT passed to claude (see header note); the
#     prompt is responsible for requesting JSON output.
#   - tools_csv: if non-empty, splits and passes each as --allowedTools <tool>.
#   - thinking_file: optional. Thinking blocks are appended here (--- separated).
#     The block label is derived from the file's basename.
#   Renders every event as a labeled block on stderr; emits the final result
#   event JSON to stdout (same shape as --output-format json).
#   Returns non-zero if no result event was received or claude reported an error.
# ---------------------------------------------------------------------------
backend_run() {
  local prompt_file="$1"
  local schema_file="$2"
  local tools_csv="$3"
  local thinking_file="${4:-}"

  local stage_label="stage"
  if [ -n "$thinking_file" ]; then
    stage_label="$(basename "$thinking_file" .log)"
  fi

  # Build the claude command. --verbose is required: with --print,
  # --output-format=stream-json refuses to run without it. stdin from /dev/null
  # so claude does not block waiting for stream-json input.
  local cmd="claude -p \"\$(cat \"$prompt_file\")\" --output-format stream-json --verbose"

  # tools_csv is a JSON array string from config_stage_field (e.g. ["Read","Bash(gh *)"]).
  # Parse element-by-element with yq so tool names containing commas or parens are safe.
  if [ -n "$tools_csv" ] && [ "$tools_csv" != "null" ] && [ "$tools_csv" != "[]" ]; then
    if [[ "$tools_csv" == \[* ]]; then
      while IFS= read -r tool; do
        [ -n "$tool" ] || continue
        cmd="$cmd --allowedTools \"$tool\""
      done < <(printf '%s' "$tools_csv" | yq '.[]' -)
    else
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

  # Process the stream-json event stream. Render every event; keep the result line.
  local result_json=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local event_type
    event_type="$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null)"

    [ "$event_type" = "result" ] && result_json="$line"
    _render_event "$stage_label" "$line" "$thinking_file"
  done < <(eval "$cmd" </dev/null)

  if [ -z "$result_json" ]; then
    echo "backend-claude: no result event received" >&2
    return 1
  fi

  local is_error
  is_error="$(printf '%s' "$result_json" | jq -r '.is_error // false' 2>/dev/null)"
  if [ "$is_error" = "true" ]; then
    echo "backend-claude: claude returned an error result" >&2
    printf '%s' "$result_json"
    return 1
  fi

  printf '%s' "$result_json"
}
