#!/usr/bin/env bash
#
# install.sh — install llm-academy skills and agents into a consuming repo.
#
# Skills/agents are symlinked by default so a `git pull` in this llm-academy
# clone propagates upstream fixes automatically. Repo-specific customization
# lives separately in the consuming repo's `.llm-academy/` overlay files (write
# those with the `learn-repo` skill) — you never fork a canonical definition.
#
# Usage:
#   ./install.sh                      # interactive selector
#   ./install.sh feature-flow review  # install specific slugs (+ their deps)
#   ./install.sh --with-deps feature-flow   # auto-include deps (headless)
#
# Options:
#   --source <path>   Path to the llm-academy clone (default: this script's dir,
#                     or $LLM_ACADEMY_HOME).
#   --target <path>   Repo to install into (default: current directory).
#   --copy            Copy files instead of symlinking (no auto-sync; implied
#                     when symlinks are unavailable).
#   --with-deps       Auto-include resolved dependencies without prompting.
#   --scaffold        Create missing convention-file stubs without prompting.
#   --gitignore       Add the installed symlink paths to the target's .gitignore
#                     without prompting (skipped if .claude/ is already ignored).
#   -y, --yes         Assume "yes" to all prompts (implies --with-deps,
#                     --scaffold, --gitignore).
#   -h, --help        Show this help.
#
set -euo pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "error: install.sh needs bash 4+ (uses arrays under 'set -u'). macOS ships 3.2 —" >&2
  echo "       install a newer bash (e.g. 'brew install bash') and run it explicitly:" >&2
  echo "       $(command -v brew >/dev/null && echo '/opt/homebrew/bin/bash' || echo bash) $0 ..." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Defaults / arg parsing
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${LLM_ACADEMY_HOME:-$SCRIPT_DIR}"
TARGET="$(pwd)"
USE_COPY=0
WITH_DEPS=0
SCAFFOLD=0
GITIGNORE=0
ASSUME_YES=0
SELECTED_ARGS=()

usage() { sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --copy) USE_COPY=1; shift ;;
    --with-deps) WITH_DEPS=1; shift ;;
    --scaffold) SCAFFOLD=1; shift ;;
    --gitignore) GITIGNORE=1; shift ;;
    -y|--yes) ASSUME_YES=1; WITH_DEPS=1; SCAFFOLD=1; GITIGNORE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *) SELECTED_ARGS+=("$1"); shift ;;
  esac
done

# Headless when there's no interactive stdin or CI is set.
HEADLESS=0
{ [ ! -t 0 ] || [ -n "${CI:-}" ]; } && HEADLESS=1

SOURCE="$(cd "$SOURCE" && pwd)"
[ -d "$SOURCE/skills" ] || { echo "error: no skills/ under source '$SOURCE' — is this an llm-academy clone? Use --source." >&2; exit 1; }

# ----------------------------------------------------------------------------
# Catalog discovery
# ----------------------------------------------------------------------------
list_skills() { for d in "$SOURCE"/skills/*/SKILL.md; do [ -e "$d" ] && basename "$(dirname "$d")"; done; }
list_agents() { for f in "$SOURCE"/agents/*.md; do [ -e "$f" ] && basename "$f" .md; done; }

skill_file() { echo "$SOURCE/skills/$1/SKILL.md"; }
agent_file() { echo "$SOURCE/agents/$1.md"; }
is_skill() { [ -f "$(skill_file "$1")" ]; }
is_agent() { [ -f "$(agent_file "$1")" ]; }

# Parse an inline-list frontmatter field, e.g. `requires: [a, b]` -> "a b".
parse_list_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    /^---[[:space:]]*$/ { fm++; next }
    fm==1 && $0 ~ ("^" field ":") {
      line=$0
      sub("^" field ":[[:space:]]*\\[", "", line)
      sub("\\].*$", "", line)
      gsub(/,/, " ", line)
      print line
    }
  ' "$file"
}

# ----------------------------------------------------------------------------
# Selection
# ----------------------------------------------------------------------------
declare -a SEL_SKILLS=() SEL_AGENTS=()

add_selection() { # $1 slug
  local slug="$1"
  if is_skill "$slug"; then SEL_SKILLS+=("$slug")
  elif is_agent "$slug"; then SEL_AGENTS+=("$slug")
  else echo "warning: unknown slug '$slug' — not a skill or agent, skipping." >&2; fi
}

interactive_select() {
  local -a catalog=() ; local i=1
  echo "Available skills:" >&2
  while read -r s; do catalog+=("skill:$s"); printf "  %2d) %s\n" "$i" "$s" >&2; i=$((i+1)); done < <(list_skills)
  echo "Available agents (usually pulled in automatically as dependencies):" >&2
  while read -r a; do catalog+=("agent:$a"); printf "  %2d) %s\n" "$i" "$a" >&2; i=$((i+1)); done < <(list_agents)
  echo "" >&2
  printf "Select by number or slug (space/comma separated), or 'all': " >&2
  local reply; read -r reply
  if [ "$reply" = "all" ]; then
    for entry in "${catalog[@]}"; do add_selection "${entry#*:}"; done
    return
  fi
  reply="${reply//,/ }"
  for tok in $reply; do
    if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#catalog[@]}" ]; then
      add_selection "${catalog[$((tok-1))]#*:}"
    else
      add_selection "$tok"
    fi
  done
}

if [ "${#SELECTED_ARGS[@]}" -gt 0 ]; then
  for slug in "${SELECTED_ARGS[@]}"; do add_selection "$slug"; done
elif [ "$HEADLESS" -eq 1 ]; then
  echo "error: no slugs given and running headless (no interactive selector available)." >&2
  exit 2
else
  interactive_select
fi

[ "${#SEL_SKILLS[@]}" -gt 0 ] || [ "${#SEL_AGENTS[@]}" -gt 0 ] || { echo "Nothing selected. Exiting."; exit 0; }

# ----------------------------------------------------------------------------
# Dependency resolution (transitive)
# ----------------------------------------------------------------------------
declare -a RES_SKILLS=("${SEL_SKILLS[@]}") RES_AGENTS=("${SEL_AGENTS[@]}")
contains() { local n="$1"; shift; local e; for e in "$@"; do [ "$e" = "$n" ] && return 0; done; return 1; }

resolve() {
  local changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    local s
    for s in "${RES_SKILLS[@]}"; do
      local dep
      for dep in $(parse_list_field "$(skill_file "$s")" requires); do
        if is_skill "$dep" && ! contains "$dep" "${RES_SKILLS[@]}"; then RES_SKILLS+=("$dep"); changed=1; fi
      done
      for dep in $(parse_list_field "$(skill_file "$s")" requires-agents); do
        if is_agent "$dep" && ! { [ "${#RES_AGENTS[@]}" -gt 0 ] && contains "$dep" "${RES_AGENTS[@]}"; }; then RES_AGENTS+=("$dep"); changed=1; fi
      done
    done
    if [ "${#RES_AGENTS[@]}" -gt 0 ]; then
      local a
      for a in "${RES_AGENTS[@]}"; do
        for dep in $(parse_list_field "$(agent_file "$a")" requires-agents); do
          if is_agent "$dep" && ! contains "$dep" "${RES_AGENTS[@]}"; then RES_AGENTS+=("$dep"); changed=1; fi
        done
      done
    fi
  done
}
resolve

# What did resolution add beyond the explicit selection?
declare -a ADDED=()
for s in "${RES_SKILLS[@]}"; do contains "$s" "${SEL_SKILLS[@]:-}" || ADDED+=("skill:$s"); done
for a in "${RES_AGENTS[@]:-}"; do [ -z "$a" ] && continue; contains "$a" "${SEL_AGENTS[@]:-}" || ADDED+=("agent:$a"); done

if [ "${#ADDED[@]}" -gt 0 ]; then
  echo "Dependencies pulled in by your selection:"
  for e in "${ADDED[@]}"; do echo "  - ${e%%:*} ${e#*:}"; done
  if [ "$WITH_DEPS" -eq 0 ]; then
    if [ "$HEADLESS" -eq 1 ]; then
      echo "error: dependencies required but --with-deps not set (headless). Re-run with --with-deps." >&2
      exit 3
    fi
    printf "Install these too? [Y/n] "; read -r ok
    case "$ok" in [Nn]*) echo "Aborted."; exit 0 ;; esac
  fi
fi

# ----------------------------------------------------------------------------
# Install
# ----------------------------------------------------------------------------
mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/agents"

# Tallies reflect *actual changes*, not the resolved selection: items that are
# already linked or that we leave untouched (pre-existing non-symlink) don't
# count. LINKED_PATHS collects the symlinks we own, for the .gitignore step.
declare -a LINKED_PATHS=()
CHANGED_SKILLS=0 CHANGED_AGENTS=0 ALREADY=0 SKIPPED=0

link_or_copy() { # $1 src  $2 dest  $3 kind (skill|agent)
  local src="$1" dest="$2" kind="$3"
  local rel="${dest#"$TARGET"/}"
  if [ -L "$dest" ]; then
    if [ "$USE_COPY" -eq 0 ] && [ "$(readlink "$dest")" = "$src" ]; then
      echo "  = $dest (already linked)"; LINKED_PATHS+=("$rel"); ALREADY=$((ALREADY+1)); return
    fi
    rm -rf "$dest"
  elif [ -e "$dest" ]; then
    echo "  ! $dest exists and is not an llm-academy symlink — leaving it alone." >&2
    SKIPPED=$((SKIPPED+1)); return
  fi
  if [ "$USE_COPY" -eq 1 ]; then
    cp -R "$src" "$dest"; echo "  + $dest (copied)"
  elif ln -s "$src" "$dest" 2>/dev/null; then
    echo "  + $dest -> $src"; LINKED_PATHS+=("$rel")
  else
    cp -R "$src" "$dest"; echo "  + $dest (copied — symlink unavailable)"
  fi
  if [ "$kind" = skill ]; then CHANGED_SKILLS=$((CHANGED_SKILLS+1)); else CHANGED_AGENTS=$((CHANGED_AGENTS+1)); fi
}

echo "Installing into $TARGET/.claude ..."
for s in "${RES_SKILLS[@]}"; do
  [ -n "$s" ] || continue
  link_or_copy "$SOURCE/skills/$s" "$TARGET/.claude/skills/$s" skill
done
for a in "${RES_AGENTS[@]:-}"; do
  [ -n "$a" ] || continue
  link_or_copy "$SOURCE/agents/$a.md" "$TARGET/.claude/agents/$a.md" agent
done

# ----------------------------------------------------------------------------
# .gitignore — offer to ignore just the symlinked paths (not all of .claude/)
# ----------------------------------------------------------------------------
maybe_gitignore() {
  # Only symlinks need ignoring; --copy installs real files the repo may vendor.
  [ "${#LINKED_PATHS[@]}" -gt 0 ] || return 0
  local gi="$TARGET/.gitignore"

  # If the repo already ignores .claude/ wholesale, per-path lines are noise.
  if [ -f "$gi" ] && grep -qE '^[[:space:]]*\.claude/?\*?[[:space:]]*$' "$gi"; then
    echo "  = $gi already ignores .claude/ — not adding per-symlink entries."
    return 0
  fi

  # Skip paths that are already listed verbatim (keeps re-runs idempotent).
  local -a to_add=() p
  for p in "${LINKED_PATHS[@]}"; do
    if [ -f "$gi" ] && grep -qxF "$p" "$gi"; then continue; fi
    to_add+=("$p")
  done
  [ "${#to_add[@]}" -gt 0 ] || return 0

  local do_it="$GITIGNORE"
  if [ "$do_it" -eq 0 ]; then
    [ "$HEADLESS" -eq 1 ] && return 0  # don't touch .gitignore unprompted in headless
    echo "These ${#to_add[@]} symlink(s) point at your llm-academy clone, so they usually"
    echo "should not be committed (unlike anything else you keep in .claude/)."
    printf "Add them to %s? [Y/n] " "$gi"; read -r r
    case "$r" in [Nn]*) return 0 ;; *) do_it=1 ;; esac
  fi
  [ "$do_it" -eq 1 ] || return 0

  if [ -f "$gi" ] && [ -s "$gi" ]; then
    [ -n "$(tail -c1 "$gi")" ] && echo "" >> "$gi"   # ensure trailing newline
    echo "" >> "$gi"                                  # blank separator
  fi
  {
    echo "# llm-academy symlinks — they point at a local clone, not for version control"
    printf '%s\n' "${to_add[@]}"
  } >> "$gi"
  echo "  + $gi (+${#to_add[@]} llm-academy symlink path(s))"
}

echo "Checking .gitignore ..."
maybe_gitignore

# ----------------------------------------------------------------------------
# Convention-file stubs
# ----------------------------------------------------------------------------
maybe_scaffold() { # $1 filename  $2 heredoc-content-var
  local name="$1" content="$2"
  [ -e "$TARGET/$name" ] && return
  local do_it="$SCAFFOLD"
  if [ "$do_it" -eq 0 ] && [ "$HEADLESS" -eq 0 ]; then
    printf "No %s found — create a stub? [Y/n] " "$name"; read -r r
    case "$r" in [Nn]*) do_it=0 ;; *) do_it=1 ;; esac
  fi
  if [ "$do_it" -eq 1 ]; then
    printf '%s\n' "$content" > "$TARGET/$name"
    echo "  + $name (stub created)"
  fi
}

TODOS_STUB='# Backlog

Work items not yet promoted to GitHub issues — small fixes, deferred refactors,
follow-ups, and ideas that do not justify a full issue.

## P1

## P2

## P3

## Deferred'

FEATURE_LOG_STUB='# Feature Log

Registry of every named feature, mechanic, or cross-cutting system in this
project'\''s design surface. See the `/feature-log` skill for status/conviction
vocabulary and entry format.

Format: `- **[conviction | status]** **Name** — one-line description.`'

echo "Checking convention files ..."
maybe_scaffold "TODOS.md" "$TODOS_STUB"
maybe_scaffold "FEATURE_LOG.md" "$FEATURE_LOG_STUB"

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
echo ""
echo "Done. Installed ${CHANGED_SKILLS} skill(s) and ${CHANGED_AGENTS} agent(s)."
[ "$ALREADY" -gt 0 ] && echo "  (${ALREADY} already up to date.)"
[ "$SKIPPED" -gt 0 ] && echo "  (${SKIPPED} left untouched — pre-existing, not an llm-academy symlink.)"

cat <<EOF

Next: run the \`learn-repo\` skill to write this repo's \`.llm-academy/\` overlays
(a shared repo.md profile plus per-skill guidance). Commit \`.llm-academy/\`.
The symlinked skills/agents point at your local clone, so keep them out of
version control — this script offered to add just those paths to \`.gitignore\`
(rather than ignoring all of \`.claude/\`, which you may want to commit). Re-run
this script anytime to add more, and \`git pull\` in $SOURCE to take updates.
EOF
