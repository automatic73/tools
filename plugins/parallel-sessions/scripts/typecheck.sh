#!/usr/bin/env bash
# Typecheck serialized across worktrees and sessions.
#
# Why: in a large monorepo 'tsc --noEmit' costs 2-3 GB. With several agent
# sessions typechecking at once that is 9 GB at a stroke, and the machine starts
# swapping. This wrapper lets one tsc run at a time per repo and caps its heap.
#
# Usage: typecheck.sh [extra tsc args]
# Env:   PS_TYPECHECK_HEAP (MB, default 3072), PS_TYPECHECK_WAIT (seconds, default 1200)
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"

# One lock per repository: two unrelated projects may still typecheck at once.
REPO=$(main_worktree)
KEY=$(printf '%s' "${REPO:-$PWD}" | cksum | cut -d' ' -f1)
LOCK="${TMPDIR:-/tmp}/parallel-sessions-typecheck-${KEY}.lock"

WAIT_MAX=${PS_TYPECHECK_WAIT:-1200}
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=${PS_TYPECHECK_HEAP:-3072}"

acquire() {
  local waited=0 owner
  while true; do
    if mkdir "$LOCK" 2>/dev/null; then
      echo $$ > "$LOCK/pid"
      trap 'rm -rf "$LOCK"' EXIT INT TERM
      return 0
    fi
    # Stale lock: whoever took it is gone.
    owner=$(cat "$LOCK/pid" 2>/dev/null || echo "")
    if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$LOCK"; continue
    fi
    [ "$waited" = "0" ] && echo "waiting: another typecheck is running (pid $owner)..."
    sleep 2; waited=$((waited + 2))
    if [ "$waited" -ge "$WAIT_MAX" ]; then
      echo "timed out after ${WAIT_MAX}s waiting for the lock (pid $owner still alive)" >&2
      exit 1
    fi
  done
}

# Warn when workspace packages will resolve against a different branch.
#
# With a linked node_modules, internal workspace packages (@scope/*) resolve
# against the MAIN worktree's packages/ directory, not this worktree's. If the
# main worktree sits on another branch, tsc reads that branch's package.json
# exports and reports phantom errors in files you never touched.
#
# Only warns: the setup is still worth it, but a heads-up beats an hour chasing
# a bug that isn't yours.
warn_branch_skew() {
  local here main_branch here_branch
  here=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ "$here" = "$REPO" ] && return 0
  [ -d "$here/node_modules" ] && [ ! -L "$here/node_modules" ] && return 0

  # Only matters when the repo actually has workspace packages.
  ls -d "$REPO"/packages/*/ >/dev/null 2>&1 || return 0

  main_branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
  here_branch=$(git -C "$here" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$main_branch" ] && [ -n "$here_branch" ] || return 0

  if [ "$main_branch" != "$here_branch" ]; then
    echo "note: the main worktree is on '$main_branch', this one is on '$here_branch'."
    echo "      Workspace packages resolve against the main worktree, so unrelated"
    echo "      'Cannot find module' errors may come from that branch, not your changes."
  fi
}

warn_branch_skew
acquire
# No 'exec': it would replace the shell and the trap would never run, leaving a
# stale lock behind.
# shellcheck disable=SC2086
$(runner_for "$(detect_pm "${REPO:-.}")") tsc --noEmit "$@"
