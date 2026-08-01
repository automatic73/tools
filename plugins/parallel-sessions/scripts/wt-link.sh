#!/usr/bin/env bash
# Links the main worktree's node_modules into a secondary worktree.
#
# Why: most package managers install a separate copy per worktree. In a monorepo
# that is 1-2 GB and ~50k files each, times however many worktrees you keep open.
# Disk is not really the issue (APFS shares blocks anyway); the pressure on file
# watchers, Spotlight and your editor's indexer is.
#
# Only links when the lockfile matches the main worktree. If it differs, the
# branch changed dependencies and needs its own install: it says so and does
# nothing.
#
# Usage:
#   wt-link.sh [path]        # link that worktree (default: the current one)
#   wt-link.sh --all         # walk every worktree in the repo
#   wt-link.sh --dry-run     # show what it would do
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"

DRY=0; ALL=0; TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --all)     ALL=1 ;;
    --quiet)   QUIET=1 ;;
    -*)        echo "unknown flag: $arg" >&2; exit 2 ;;
    *)         TARGET="$arg" ;;
  esac
done
QUIET=${QUIET:-0}
say() { [ "$QUIET" = "1" ] || echo "$@"; }

MAIN=$(main_worktree)
[ -n "$MAIN" ] || { echo "not inside a git repository" >&2; exit 1; }

PM=$(detect_pm "$MAIN")
LOCK=$(lockfile_for "$PM" "$MAIN")

# The main worktree's node_modules: the root one plus each workspace's. These are
# discovered rather than assumed to be apps/*|packages/*, which varies by project.
main_module_dirs() {
  [ -d "$MAIN/node_modules" ] && echo ""
  find "$MAIN" -maxdepth 3 -type d -name node_modules -not -path "*/node_modules/*" 2>/dev/null |
    while read -r p; do
      rel="${p#"$MAIN"/}"; rel="${rel%node_modules}"
      [ -n "$rel" ] && echo "$rel"
    done
}

link_one() {
  local wt="$1" name linked=0 replaced=0
  name=$(basename "$wt")
  [ "$wt" = "$MAIN" ] && return 0

  if [ ! -d "$MAIN/node_modules" ]; then
    say "skip  $name: the main worktree has no node_modules yet"
    return 0
  fi

  # Guard: different dependencies => needs its own install.
  if [ -n "$LOCK" ] && [ -f "$wt/$LOCK" ] && ! cmp -s "$MAIN/$LOCK" "$wt/$LOCK"; then
    say "skip  $name: $LOCK differs from main, needs its own install"
    return 0
  fi

  while IFS= read -r rel; do
    local src="$MAIN/${rel}node_modules" dst="$wt/${rel}node_modules"
    [ -d "$src" ] || continue
    [ -L "$dst" ] && continue
    [ -d "$(dirname "$dst")" ] || continue

    if [ -d "$dst" ]; then
      [ "$DRY" = "1" ] && { say "   [dry] would replace $dst"; replaced=$((replaced+1)); continue; }
      rm -rf "$dst"; replaced=$((replaced+1))
    fi
    if [ "$DRY" = "1" ]; then say "   [dry] would link $dst -> $src"
    else ln -s "$src" "$dst"; fi
    linked=$((linked+1))
  done < <(main_module_dirs)

  [ "$linked" -gt 0 ] && say "ok    $name: $linked links ($replaced copies replaced)"
  return 0
}

if [ "$ALL" = "1" ]; then
  while read -r wt; do link_one "$wt"; done < <(
    git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2
  )
else
  link_one "$(cd "${TARGET:-$PWD}" && git rev-parse --show-toplevel 2>/dev/null || echo "${TARGET:-$PWD}")"
fi
