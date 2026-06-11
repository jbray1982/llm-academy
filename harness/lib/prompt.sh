#!/usr/bin/env bash
# lib/prompt.sh — M3: Prompt template assembly.
#
# Secret owned: the template grammar — what tokens are substituted and how.
# No other module touches prompt file contents; they pass the assembled text
# to backend_invoke through a temp file.
#
# Template grammar (all substitutions performed in one pass):
#   {item}              → the work item identifier (issue number, slug, etc.)
#   {run_dir}           → the absolute path of the current run directory
#   {co_author}         → the co-author line from config (for commit prompts)
#   {{handoff:NAME}}    → contents of $run_dir/handoffs/NAME.md
#                         (populated via handoff_read; empty string if absent)
#
# Prompt files are plain markdown — no other escaping or interpretation.

# ---------------------------------------------------------------------------
# prompt_assemble  prompt_file  item  run_dir  co_author  →  assembled text on stdout
#
# contract: Reads prompt_file, performs the token substitutions above, and
#   emits the result to stdout. The caller is responsible for writing stdout
#   to a temp file before passing it to backend_invoke.
#   Fails (return 1) if prompt_file does not exist or is unreadable.
#   {{handoff:NAME}} tokens that reference a missing handoff expand to the
#   empty string — this is intentional so the first stage in a pipeline
#   (which has no prior handoffs) runs without error.
# ---------------------------------------------------------------------------
prompt_assemble() {
  local prompt_file="$1"
  local item="$2"
  local run_dir="$3"
  local co_author="$4"

  # Check if prompt_file exists
  if [ ! -f "$prompt_file" ] || [ ! -r "$prompt_file" ]; then
    return 1
  fi

  # Read the file
  local content
  content="$(cat "$prompt_file")"

  # Apply substitutions: {item}, {run_dir}, {co_author}.
  # Braces MUST be escaped: in ${var//{token}/repl}, an unescaped closing brace
  # terminates the parameter expansion early, deleting the literal "{token" and
  # appending "/repl}" as text. Escaping keeps {token} as the literal pattern.
  content="${content//\{item\}/$item}"
  content="${content//\{run_dir\}/$run_dir}"
  content="${content//\{co_author\}/$co_author}"

  # Apply {{handoff:NAME}} substitutions
  # Find all {{handoff:*}} tokens and replace them
  while [[ $content =~ \{\{handoff:([^}]+)\}\} ]]; do
    local handoff_name="${BASH_REMATCH[1]}"
    local handoff_content
    handoff_content="$(handoff_read "$run_dir" "$handoff_name")" || true
    # Replace the first occurrence
    content="${content//\{\{handoff:$handoff_name\}\}/$handoff_content}"
  done

  printf '%s' "$content"
}
