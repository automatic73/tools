#!/usr/bin/env bash
# Utilidades compartidas: deteccion de gestor de paquetes y del worktree principal.
# Se hace source desde los demas scripts, no se ejecuta directo.

# Gestor de paquetes del repo. Prioriza el campo packageManager de package.json
# (autoritativo, lo pone corepack) y cae al lockfile presente.
# Un monorepo puede tener varios lockfiles conviviendo, de ahi el orden fijo.
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
  elif [ -f "$root/pnpm-lock.yaml" ]; then echo pnpm
  elif [ -f "$root/yarn.lock" ];      then echo yarn
  elif [ -f "$root/package-lock.json" ]; then echo npm
  else echo ""
  fi
}

# Lockfile que corresponde al gestor detectado.
lockfile_for() {
  case "$1" in
    bun)  [ -f "${2:-.}/bun.lock" ] && echo "bun.lock" || echo "bun.lockb" ;;
    pnpm) echo "pnpm-lock.yaml" ;;
    yarn) echo "yarn.lock" ;;
    npm)  echo "package-lock.json" ;;
    *)    echo "" ;;
  esac
}

# Como ejecutar un binario de node_modules con ese gestor.
runner_for() {
  case "$1" in
    bun)  echo "bunx" ;;
    pnpm) echo "pnpm exec" ;;
    yarn) echo "yarn" ;;
    *)    echo "npx" ;;
  esac
}

# Worktree principal del repo (el primero que lista git).
main_worktree() {
  git worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2
}

# Reporte de presion de memoria, portable macOS + Linux.
#
# La señal que importa es el SWAP, no "free vs used": macOS reporta casi toda la
# RAM como usada por diseño (cache, compressor), asi que un "0 MB libres" no
# significa nada. Un swap lleno si: ahi es donde se siente la maquina arrastrando.
mem_report() {
  if [ "$(uname)" = "Darwin" ]; then
    # formato: total = 32768.00M  used = 31701.88M  free = 1066.12M
    sysctl -n vm.swapusage | awk '{
      total=$3; used=$6; gsub("M","",total); gsub("M","",used);
      pct = (total > 0) ? used*100/total : 0;
      printf "  swap:  %.0f de %.0f MB usados (%.0f%%)%s\n", used, total, pct,
             (pct > 70 ? "   <- saturado" : "")
    }'
    local ram_total
    ram_total=$(( $(sysctl -n hw.memsize) / 1048576 ))
    echo "  RAM instalada: ${ram_total} MB"
  else
    free -m 2>/dev/null | awk '
      /^Mem:/  { printf "  RAM:   %d de %d MB usados, %d disponibles\n", $3, $2, $7 }
      /^Swap:/ { if ($2 > 0) { pct=$3*100/$2;
                 printf "  swap:  %d de %d MB usados (%.0f%%)%s\n", $3, $2, pct,
                        (pct > 70 ? "   <- saturado" : "") } }'
  fi
}
