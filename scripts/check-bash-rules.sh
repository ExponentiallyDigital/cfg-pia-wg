#!/bin/sh
# check-bash-rules.sh - makes the working rules of CLAUDE.md impossible to skip (ID-691).
#
# Andrew's review of 2026-11-23 found rules that were in files and still broken: a release plan that left out
# the play block, a push to CI before the full tests had run, Dart and Python in bash heredocs that collapsed
# their escapes, and requests answered by assuming. A rule in a file only works if it is applied every time, so
# the ones a machine can see are checked here, by three Claude Code hooks (.claude/settings.json):
#
#   pre     PreToolUse on Bash. Denies, with the reason, a command that
#             - puts Dart, Python or another language's code in a heredoc (write the file with the Write tool);
#             - is `git commit` while CHANGELOG's top block still reads "in progress", has no ```play fence, or
#               differs from the commit subject (CHANGE-PROCESS.md section 8, steps 1 and 2);
#             - is `git commit`, a branch `git push` or `gh workflow run release.yml` while a file has changed
#               since the last full `flutter test` passed.
#           A commit whose subject starts "throwaway:" is exempt from the section 8 checks, and a push of a
#           tag, or a deletion, from the test check, since neither carries new code.
#   post    PostToolUse on Bash. Records `.claude/full-test-passed` when a full `flutter test` (no test path)
#           prints "All tests passed!", which is what `pre` compares file times with.
#   prompt  UserPromptSubmit. Puts the rules that no machine can see in front of Claude with every request.
#
# Output is the hook's JSON on stdout, or nothing. It always exits 0, so a fault here never stops work:
# without jq, or outside a repository, it checks nothing.
mode="$1"
input=$(cat)

command -v jq > /dev/null 2>&1 || exit 0

deny() {
  reason="$1"
  jq -nc --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

# Whether the full tests have passed since the last change: exit 0 when they have. A change is a file git
# reports as changed (the working tree and the index), or one in a commit not yet pushed to origin/dev,
# outside .claude/.
tests_fresh() {
  marker=".claude/full-test-passed"
  [ -f "$marker" ] || return 1
  {
    git status --porcelain 2> /dev/null | cut -c4- | sed 's/^.* -> //' | tr -d '"'
    git diff --name-only origin/dev..HEAD 2> /dev/null
  } | while IFS= read -r f; do
    case "$f" in
      .claude/* | '') continue ;;
      *) ;;
    esac
    if [ -e "$f" ] && [ "$f" -nt "$marker" ]; then
      echo "$f"
      break
    fi
  done | grep -q . && return 1
  return 0
}

case "$mode" in
  pre)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null)
    [ -n "$cmd" ] || exit 0
    root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
    cd "$root" || exit 0

    # A heredoc that carries code. A plain heredoc, a commit message's, is fine.
    if printf '%s' "$cmd" | grep -Eq '<<-?[[:space:]]*["'"'"'\\]?[A-Za-z_]' &&
      { printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_.-])(python3?|dart|node|ruby|perl|php)([[:space:]]|$)' ||
        printf '%s' "$cmd" | grep -Eq '>[[:space:]]*[^[:space:]<>|;&]*\.(dart|py|js|rb)([[:space:]]|$)'; }; then
      deny "CLAUDE.md: never put Dart or Python code in a bash heredoc, since it collapses backslashes, \\n and apostrophes. Write the file with the Write tool, then run it. (Andrew, 2026-11-23)"
    fi

    # A commit.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit([[:space:]]|$)'; then
      subject=$(printf '%s' "$cmd" | grep -o -m1 -e '-m "[^"]*"' | head -1 | sed 's/^-m "//; s/"$//')
      [ -n "$subject" ] || subject=$(printf '%s' "$cmd" | grep -o -m1 -e "-m '[^']*'" | head -1 | sed "s/^-m '//; s/'\$//")
      [ -n "$subject" ] || subject=$(printf '%s' "$cmd" | sed -n "/<<[-]*[[:space:]]*['\"]*EOF/{n;p;}" | head -1)
      case "$subject" in
        throwaway:*) ;;
        *)
          header=$(sed -n '1,60p' CHANGELOG.md | grep -m1 -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} v[0-9]+\.[0-9]+\.[0-9]+ build [0-9]+ - ')
          if [ -n "$header" ]; then
            case "$header" in
              *' - in progress') deny "CHANGE-PROCESS.md section 8 step 1: the top CHANGELOG block still reads 'in progress'. Replace it with a short summary of what the block contains, and commit with the subject 'vN.N.NN build NNN - <that summary>', word for word." ;;
              *) ;;
            esac
            fence=$(awk -v h="$header" 'BEGIN{f=0} $0==h{f=1; next} f && /^[0-9]{4}-[0-9]{2}-[0-9]{2} v[0-9]/{exit} f && /^```play/{print "yes"; exit}' CHANGELOG.md)
            [ "$fence" = "yes" ] || deny "CHANGE-PROCESS.md section 8 step 2: the top CHANGELOG block has no \`\`\`play fence under its header. Write one: at most 500 characters, a bullet for each thing a user will notice in order of importance, and the Full changelog link last."
            expected=$(printf '%s' "$header" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} //')
            if [ -n "$subject" ] && [ "$subject" != "$expected" ]; then
              deny "CHANGE-PROCESS.md section 8 step 1: the commit subject must be the block header word for word: '$expected'. The subject given was: '$subject'."
            fi
          fi
          tests_fresh || deny "CLAUDE.md: run the full flutter test before committing: a file has changed since the last full run passed, or none has run. (Andrew, 2026-11-23)"
          ;;
      esac
    fi

    # A branch push. A tag, or a deletion, carries no new code.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)' &&
      ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[^;&|]*([[:space:]](--delete|-d)([[:space:]]|$)|[[:space:]]:|[[:space:]]v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$))'; then
      tests_fresh || deny "CLAUDE.md: run the full flutter test before pushing to CI: a file has changed since the last full run passed, or none has run. (Andrew, 2026-11-23)"
    fi

    # A release dry run.
    if printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+workflow[[:space:]]+run[[:space:]]+release\.yml'; then
      tests_fresh || deny "CLAUDE.md: run the full flutter test before starting a dry run, which costs 10 minutes or more: a file has changed since the last full run passed, or none has run. (Andrew, 2026-11-23)"
    fi
    ;;
  post)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null)
    [ -n "$cmd" ] || exit 0
    printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])flutter[[:space:]]+test([[:space:]]+--[A-Za-z-]+(=[^[:space:]]+)?)*[[:space:]]*($|[>|;&])' || exit 0
    out=$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2> /dev/null)
    case "$out" in
      *'Some tests failed'*) exit 0 ;;
      *'All tests passed!'*) ;;
      *) exit 0 ;;
    esac
    root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
    mkdir -p "$root/.claude" && : > "$root/.claude/full-test-passed"
    ;;
  prompt)
    jq -nc '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: "WORKING RULES (CLAUDE.md, 2026-11-23): restate the outcome in one line and ask if the request has two readings, never assume. On any failure state the root cause first and propose the root-cause fix before any workaround. Look in this conversation and the files before asking Andrew anything. Follow every documented rule (CLAUDE.md, CHANGE-PROCESS.md) and finish all the work asked for."}}'
    ;;
  *) ;;
esac
exit 0
