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

acquire
# No 'exec': it would replace the shell and the trap would never run, leaving a
# stale lock behind.
# shellcheck disable=SC2086
$(runner_for "$(detect_pm "${REPO:-.}")") tsc --noEmit "$@"
