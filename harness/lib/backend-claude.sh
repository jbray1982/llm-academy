#!/usr/bin/env bash
# lib/backend-claude.sh — M5 impl: Claude CLI backend.
#
# Secret owned (impl half): the exact claude CLI flags and invocation form.
# This is the ONLY file in the harness that names `claude` — every other
# module is backend-agnostic. Swapping to a different CLI is a new
# backend-<name>.sh file; no other file changes.
#
# Output: uses --output-format stream-json. The JSONL event stream is
# processed inline: thinking blocks are written to thinking_file and rendered
# as dim boxes on stderr; the final result event is emitted to stdout.
# The result event has the same top-level shape as --output-format json
# (.result, .usage, .session_id, etc.), so M6 result_normalize is unchanged.
#
# tools_csv format: comma-separated tool names exactly as claude accepts them
# (e.g. "Read,Write,Edit,Bash(gh issue view *)"). backend_run passes each
# value as a separate --allowedTools argument because the claude CLI does not
# accept a single comma-joined string.

# ---------------------------------------------------------------------------
# _thinking_box  label  text  → renders a dim bordered box to stderr
# ---------------------------------------------------------------------------
_thinking_box() {
  local label="${1:-stage}"
  local text="$2"
  local width=72
  local inner=$((width - 4))
  local DIM='\033[2m' RESET='\033[0m'

  # Repeat char $1 times, char $2.
  _rep() {
    local i result=""
    for ((i = 0; i < $1; i++)); do result="${result}$2"; done
    printf '%s' "$result"
  }

  local header="[ thinking: ${label} ]"
  local fill=$((width - ${#header} - 3))
  [ "$fill" -lt 1 ] && fill=1

  printf "${DIM}╭─%s%s╮${RESET}\n" "$header" "$(_rep "$fill" '─')" >&2
  while IFS= read -r chunk; do
    local pad=$((inner - ${#chunk}))
    [ "$pad" -lt 0 ] && pad=0 && chunk="${chunk:0:$inner}"
    printf "${DIM}│ %s%s │${RESET}\n" "$chunk" "$(_rep "$pad" ' ')" >&2
  done < <(printf '%s' "$text" | fold -s -w "$inner")
  printf "${DIM}╰%s╯${RESET}\n" "$(_rep $((width - 2)) '─')" >&2
}

# ---------------------------------------------------------------------------
# backend_run  prompt_file  schema_file  tools_csv  [thinking_file]
#              →  result event JSON on stdout
#
# contract: Translates the harness's generic invocation args into the claude
#   CLI command using --output-format stream-json and processes the event stream.
#   - prompt_file: path to the assembled prompt; passed via $(cat ...) to -p.
#   - schema_file: if non-empty, adds --json-schema <file>.
#   - tools_csv: if non-empty, splits and passes each as --allowedTools <tool>.
#   - thinking_file: optional. Thinking blocks are appended here (with --- separators
#     between blocks). The box label is derived from the file's basename.
#   Emits the final result event JSON to stdout (same shape as --output-format json).
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
  # --output-format=stream-json refuses to run without it.
  local cmd="claude -p \"\$(cat \"$prompt_file\")\" --output-format stream-json --verbose"

  if [ -n "$schema_file" ] && [ "$schema_file" != "null" ]; then
    cmd="$cmd --json-schema \"$schema_file\""
  fi

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

  # Process the stream-json event stream.
  local result_json=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local event_type
    event_type="$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null)"

    case "$event_type" in
      assistant)
        # Extract all thinking blocks from this turn and join them.
        local thinking
        thinking="$(printf '%s' "$line" | jq -r '
          [.message.content[]? | select(.type == "thinking") | .thinking] | join("\n\n")
        ' 2>/dev/null)"
        if [ -n "$thinking" ]; then
          if [ -n "$thinking_file" ]; then
            printf '%s\n---\n' "$thinking" >> "$thinking_file"
          fi
          _thinking_box "$stage_label" "$thinking"
        fi
        ;;
      result)
        result_json="$line"
        ;;
    esac
  done < <(eval "$cmd")

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
