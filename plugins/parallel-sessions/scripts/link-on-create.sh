#!/usr/bin/env bash
# Links a freshly created worktree's node_modules BEFORE anything tries to
# install it.
#
# PostToolUse on Bash only: the worktrees any other flow creates with
# 'git worktree add', such as superpowers' using-git-worktrees skill, which then
# runs 'npm install' as a setup step. Arriving already linked, that install has
# nothing left to do and never trips guard-install.
#
# The ones Claude Code creates (--worktree, EnterWorktree, agents) go through
# create-worktree.sh instead. They used to come here too, and that was the bug:
# WorktreeCreate expects the hook to create the worktree and print its path,
# and this script printed nothing, so every isolated agent failed to start.
#
# Silent by design: it is a hook, it must not clutter the session or ever fail.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat 2>/dev/null || echo '{}')
command -v jq >/dev/null 2>&1 || exit 0

# Only 'git worktree add' is of interest.
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
printf '%s' "$cmd" | grep -qE 'git[[:space:]]+worktree[[:space:]]+add' || exit 0
# The first non-flag argument after 'add' is the destination path.
path=$(printf '%s' "$cmd" |
  sed -nE 's/.*git[[:space:]]+worktree[[:space:]]+add[[:space:]]+(.*)/\1/p' |
  tr ' ' '\n' | grep -vE '^-' | head -1)

[ -n "$path" ] || exit 0
[ -d "$path" ] || exit 0

bash "$SELF_DIR/wt-link.sh" --quiet "$path" >/dev/null 2>&1 || true
exit 0
