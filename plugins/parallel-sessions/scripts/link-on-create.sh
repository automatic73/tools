#!/usr/bin/env bash
# Links a freshly created worktree's node_modules BEFORE anything tries to
# install it.
#
# Covers both ways a worktree is born:
#   - WorktreeCreate: the ones Claude Code creates (--worktree, EnterWorktree, agents)
#   - PostToolUse/Bash: the ones any other flow creates with 'git worktree add',
#     such as superpowers' using-git-worktrees skill, which then runs
#     'npm install' as a setup step. Arriving already linked, that install has
#     nothing left to do and never trips guard-install.
#
# Silent by design: it is a hook, it must not clutter the session or ever fail.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat 2>/dev/null || echo '{}')
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null)
path=""

case "$event" in
  WorktreeCreate)
    path=$(printf '%s' "$payload" | jq -r '.worktree_path // .path // ""' 2>/dev/null)
    ;;
  *)
    # PostToolUse on Bash: only 'git worktree add' is of interest.
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
    printf '%s' "$cmd" | grep -qE 'git[[:space:]]+worktree[[:space:]]+add' || exit 0
    # The first non-flag argument after 'add' is the destination path.
    path=$(printf '%s' "$cmd" |
      sed -nE 's/.*git[[:space:]]+worktree[[:space:]]+add[[:space:]]+(.*)/\1/p' |
      tr ' ' '\n' | grep -vE '^-' | head -1)
    ;;
esac

[ -n "$path" ] || exit 0
[ -d "$path" ] || exit 0

bash "$SELF_DIR/wt-link.sh" --quiet "$path" >/dev/null 2>&1 || true
exit 0
