#!/bin/sh
# check-changelog-current.sh - keeps CHANGE-PROCESS.md section 1 from being forgotten (ID-649).
#
# Rule: as soon as any source code or markdown that relates to a work item is altered, the item moves to
# CHANGELOG.md's current release block. Source is lib/, test/, tool/, scripts/, android/, ios/, .github/,
# pubspec.yaml and pubspec.lock. Markdown is every .md file except BACKLOG.md, CHANGELOG.md and the plan
# files under .claude/plans/ (a plan creates no item; the item it relates to names it on its `Plan:` line).
#
# Two Claude Code hooks call it (.claude/settings.json):
#   edit   PostToolUse, after an Edit or Write: reads the hook's JSON on stdin and, when the file counts,
#          reminds Claude to move the item now, in the same turn.
#   stop   Stop, at the end of a turn: when counted files differ from the last commit and CHANGELOG.md has
#          not changed since it, blocks the stop and says so. It cannot tell which item a file belongs to,
#          so it is a net under the reminder, not a proof; the commit-time check in section 8 is the third.
#
# Output is the hook's JSON on stdout, or nothing. It always exits 0, so a fault here never stops work.
mode="$1"

# Whether a repo-relative path counts under the rule: exit 0 when it does.
counts() {
  case "$1" in
    BACKLOG.md | CHANGELOG.md | .claude/plans/*) return 1 ;;
    lib/* | test/* | tool/* | scripts/* | android/* | ios/* | .github/* | pubspec.yaml | pubspec.lock) return 0 ;;
    *.md) return 0 ;;
    *) ;;
  esac
  return 1
}

case "$mode" in
  edit)
    command -v jq >/dev/null 2>&1 || exit 0
    file=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null | tr '\\' '/')
    [ -n "$file" ] || exit 0
    root=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/')
    # Windows hands over the drive letter in either case, so compare lower-cased and cut by length.
    lower_file=$(printf '%s' "$file" | tr 'A-Z' 'a-z')
    lower_root=$(printf '%s' "$root" | tr 'A-Z' 'a-z')
    case "$lower_file" in
      "$lower_root"/*) rel=$(printf '%s' "$file" | cut -c$((${#root} + 2))-) ;;
      *) exit 0 ;; # not in this repository
    esac
    counts "$rel" || exit 0
    name=$(basename "$rel" | tr -d '"')
    printf '%s' "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"CHANGE-PROCESS CHECK: you just changed $name. Is the work item it belongs to in CHANGELOG.md's current block (section 1: anything built is listed at once)? If it is still in BACKLOG.md, move it now, in this turn. If it is only partly built, give it a Partly done line ending Remainder: ID-NNN, and a new Current Release item for the rest. If it relates to no item, create one first. Say what you moved in your reply, and add it at the bottom of the block: the items run oldest first, newest last (section 1).\"}}"
    ;;
  stop)
    input=$(cat)
    case "$input" in
      *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;; # already blocked once this turn
      *) ;;
    esac
    root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    cd "$root" || exit 0
    counted=""
    for p in $(git status --porcelain 2>/dev/null | cut -c4- | tr -d '"' | tr ' ' '?'); do
      p=$(printf '%s' "$p" | tr '?' ' ')
      if counts "$p"; then counted="$counted $(basename "$p")"; fi
    done
    [ -n "$counted" ] || exit 0
    git diff --quiet HEAD -- CHANGELOG.md 2>/dev/null || exit 0 # CHANGELOG.md has changed since the commit
    shown=$(printf '%s' "$counted" | cut -c1-200 | tr -d '"\\')
    printf '%s' "{\"decision\":\"block\",\"reason\":\"CHANGE-PROCESS.md section 1: source or markdown has changed since the last commit ($shown) but CHANGELOG.md has not. Anything built is listed at once under the current release block: move each item it relates to out of BACKLOG.md now, or give it a Partly done line and a new Current Release item for the rest, and create an item first if there is none. Then say what you moved.\"}"
    ;;
  *) ;;
esac
exit 0
