#!/usr/bin/env bash
# WorktreeCreate hook: creates the worktree Claude Code asked for, links its
# node_modules, and hands the path back.
#
# Why this exists as a separate script: WorktreeCreate is not a notification.
# When a hook is registered for it, Claude Code stops creating the worktree
# itself and expects the hook to do it and to print the path. The first
# version of this plugin treated the event as "a worktree was born" and
# printed nothing, so every agent that asked for worktree isolation, and every
# EnterWorktree, failed with "hook succeeded but returned no worktree path".
# Measured on 2026-09-27: a five-agent workflow died in 365 ms without
# starting one agent.
#
# Contract (code.claude.com/docs/en/hooks, WorktreeCreate):
#   stdin:  { session_id, cwd, hook_event_name, worktree_name, base_branch }
#   stdout: { "hookSpecificOutput": { "hookEventName": "WorktreeCreate",
#                                     "worktreePath": "<path>" } }
#   exit:   non-zero aborts the creation, whatever stdout says.
#
# So this is the one script in the plugin that MAY fail loudly: a worktree that
# could not be created must abort, not be reported as created.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat 2>/dev/null || echo '{}')
if ! command -v jq >/dev/null 2>&1; then
  echo "parallel-sessions: jq is required to create worktrees" >&2
  exit 1
fi

name=$(printf '%s' "$payload" | jq -r '.worktree_name // ""')
base=$(printf '%s' "$payload" | jq -r '.base_branch // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')
[ -n "$cwd" ] || cwd="$PWD"

# Directory names only: a name with a slash would land outside .claude/worktrees.
name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')
[ -n "$name" ] || name="wt-$(printf '%s' "$payload" | jq -r '.session_id // "session"' | cut -c1-8)"

# The main worktree, not the one the session runs in: a worktree created inside
# another worktree's .claude/ would vanish with it.
main=$(git -C "$cwd" worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2)
if [ -z "$main" ]; then
  echo "parallel-sessions: $cwd is not inside a git repository" >&2
  exit 1
fi

path="$main/.claude/worktrees/$name"
branch="$name"
n=2
while [ -e "$path" ] || git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; do
  path="$main/.claude/worktrees/$name-$n"
  branch="$name-$n"
  n=$((n + 1))
done
mkdir -p "$(dirname "$path")"

# The branch starts where Claude Code said, or at the session's HEAD when it
# said nothing, which is what the default creation does.
start="${base:-HEAD}"
[ "$start" = "HEAD" ] && start=$(git -C "$cwd" rev-parse HEAD)
# git's checkout progress goes to stderr and would land in the session as
# noise; it is kept and shown only when the add fails, which is when it helps.
if ! err=$(git -C "$main" worktree add -b "$branch" "$path" "$start" 2>&1); then
  printf '%s\n' "$err" >&2
  echo "parallel-sessions: git worktree add failed for $path" >&2
  exit 1
fi

# Linking is best effort, as everywhere else in the plugin: a worktree without
# the link still works, it just costs an install.
bash "$SELF_DIR/wt-link.sh" --quiet "$path" >/dev/null 2>&1 || true

jq -n --arg p "$path" '{hookSpecificOutput: {hookEventName: "WorktreeCreate", worktreePath: $p}}'
