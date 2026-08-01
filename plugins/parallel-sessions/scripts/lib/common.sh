#!/usr/bin/env bash
# Shared helpers: package manager detection and memory reporting.
# Sourced by the other scripts, not run directly.

# Package manager for the repo. Prefers package.json's packageManager field
# (authoritative, set by corepack) and falls back to the lockfile present.
# A monorepo can carry several lockfiles at once, hence the fixed order.
detect_pm() {
  local root="${1:-.}"

  if [ -f "$root/package.json" ]; then
    local declared
    declared=$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([a-z]*\)@.*/\1/p' "$root/package.json" | head -1)
    case "$declared" in
      bun|pnpm|yarn|npm) echo "$declared"; return 0 ;;
    esac
  fi

  if   [ -f "$root/bun.lock" ] || [ -f "$root/bun.lockb" ]; then echo bun
  elif [ -f "$root/pnpm-lock.yaml" ];    then echo pnpm
  elif [ -f "$root/yarn.lock" ];         then echo yarn
  elif [ -f "$root/package-lock.json" ]; then echo npm
  else echo ""
  fi
}

# Lockfile matching the detected package manager.
lockfile_for() {
  case "$1" in
    bun)  [ -f "${2:-.}/bun.lock" ] && echo "bun.lock" || echo "bun.lockb" ;;
    pnpm) echo "pnpm-lock.yaml" ;;
    yarn) echo "yarn.lock" ;;
    npm)  echo "package-lock.json" ;;
    *)    echo "" ;;
  esac
}

# How to run a node_modules binary with that package manager.
runner_for() {
  case "$1" in
    bun)  echo "bunx" ;;
    pnpm) echo "pnpm exec" ;;
    yarn) echo "yarn" ;;
    *)    echo "npx" ;;
  esac
}

# The repo's main worktree (the first one git lists).
main_worktree() {
  git worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2
}

# Memory pressure report, portable across macOS and Linux.
#
# Swap is the signal that matters, not "free vs used": macOS reports nearly all
# RAM as used by design (cache, compressor), so "0 MB free" means nothing. A full
# swap does: that is where the machine starts dragging.
mem_report() {
  if [ "$(uname)" = "Darwin" ]; then
    # format: total = 32768.00M  used = 31701.88M  free = 1066.12M
    sysctl -n vm.swapusage | awk '{
      total=$3; used=$6; gsub("M","",total); gsub("M","",used);
      pct = (total > 0) ? used*100/total : 0;
      printf "  swap:  %.0f of %.0f MB used (%.0f%%)%s\n", used, total, pct,
             (pct > 70 ? "   <- saturated" : "")
    }'
    local ram_total
    ram_total=$(( $(sysctl -n hw.memsize) / 1048576 ))
    echo "  installed RAM: ${ram_total} MB"
  else
    free -m 2>/dev/null | awk '
      /^Mem:/  { printf "  RAM:   %d of %d MB used, %d available\n", $3, $2, $7 }
      /^Swap:/ { if ($2 > 0) { pct=$3*100/$2;
                 printf "  swap:  %d of %d MB used (%.0f%%)%s\n", $3, $2, pct,
                        (pct > 70 ? "   <- saturated" : "") } }'
  fi
}
