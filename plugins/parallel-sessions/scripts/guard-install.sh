#!/usr/bin/env bash
# PreToolUse hook: blocks dependency installs inside a worktree whose
# node_modules is a symlink to the main worktree's.
#
# Why: the install would write into the main worktree's node_modules and hit
# every worktree at once, silently. This only comes up when something skips the
# earlier linking step (for example a skill that runs 'npm install' as part of
# its setup); in the normal flow the worktree arrives already linked.
set -uo pipefail

payload=$(cat)

# Without jq, degrade to allowing: a hook must never break someone's session.
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // .workspace.current_dir // ""' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"

# Install commands only.
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(bun|npm|pnpm|yarn)[[:space:]]+(install|add|i|ci)([[:space:]]|$)' || exit 0

# If the command carries a 'cd', evaluate that destination instead.
target=$(printf '%s' "$cmd" | sed -nE 's/.*cd[[:space:]]+([^;&|]+).*/\1/p' | head -1 | xargs 2>/dev/null || true)
if [ -n "$target" ]; then
  case "$target" in
    /*) cwd="$target" ;;
    ~*) cwd="${target/#\~/$HOME}" ;;
    *)  cwd="$cwd/$target" ;;
  esac
fi

# Walk up to the first node_modules.
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -e "$dir/node_modules" ]; then
    if [ -L "$dir/node_modules" ]; then
      real=$(readlink "$dir/node_modules")
      jq -n --arg d "$dir" --arg r "$real" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("node_modules in \($d) is a symlink to \($r), shared with the main worktree. Installing here would write there and affect EVERY worktree at once.\n\nIf this branch needs different dependencies:  rm \($d)/node_modules  then install.\nIf it does not: install in the main worktree, and the link already gives you the result.")
        }
      }'
      exit 0
    fi
    break
  fi
  dir=$(dirname "$dir")
done

exit 0
