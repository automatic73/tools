#!/usr/bin/env bash
# Enlaza los node_modules del worktree principal en un worktree secundario.
#
# Por que: la mayoria de gestores instalan una copia por worktree. En un monorepo
# eso son 1-2 GB y ~50k archivos por worktree, multiplicado por cuantos tengas
# abiertos. No es tanto el disco (APFS comparte bloques) como la presion sobre
# los file watchers, Spotlight y el indexador del editor.
#
# Solo enlaza si el lockfile coincide con el del principal. Si difiere, la rama
# cambio dependencias y necesita su propio install: avisa y no toca nada.
#
# Uso:
#   wt-link.sh [ruta]        # enlaza ese worktree (default: el actual)
#   wt-link.sh --all         # recorre todos los worktrees del repo
#   wt-link.sh --dry-run     # muestra que haria
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
    -*)        echo "flag desconocido: $arg" >&2; exit 2 ;;
    *)         TARGET="$arg" ;;
  esac
done
QUIET=${QUIET:-0}
say() { [ "$QUIET" = "1" ] || echo "$@"; }

MAIN=$(main_worktree)
[ -n "$MAIN" ] || { echo "no estoy en un repo git" >&2; exit 1; }

PM=$(detect_pm "$MAIN")
LOCK=$(lockfile_for "$PM" "$MAIN")

# node_modules del principal: la raiz y los de cada workspace. Se descubren en
# vez de asumir apps/*|packages/*, que cambia entre proyectos.
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
    say "⏭  $name: el worktree principal no tiene node_modules todavia"
    return 0
  fi

  # Guard: dependencias distintas => install propio.
  if [ -n "$LOCK" ] && [ -f "$wt/$LOCK" ] && ! cmp -s "$MAIN/$LOCK" "$wt/$LOCK"; then
    say "⏭  $name: $LOCK difiere del principal, necesita su propio install"
    return 0
  fi

  while IFS= read -r rel; do
    local src="$MAIN/${rel}node_modules" dst="$wt/${rel}node_modules"
    [ -d "$src" ] || continue
    [ -L "$dst" ] && continue
    [ -d "$(dirname "$dst")" ] || continue

    if [ -d "$dst" ]; then
      [ "$DRY" = "1" ] && { say "   [dry] reemplazaria $dst"; replaced=$((replaced+1)); continue; }
      rm -rf "$dst"; replaced=$((replaced+1))
    fi
    if [ "$DRY" = "1" ]; then say "   [dry] enlazaria $dst -> $src"
    else ln -s "$src" "$dst"; fi
    linked=$((linked+1))
  done < <(main_module_dirs)

  [ "$linked" -gt 0 ] && say "✅ $name: $linked enlaces ($replaced copias reemplazadas)"
  return 0
}

if [ "$ALL" = "1" ]; then
  while read -r wt; do link_one "$wt"; done < <(
    git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2
  )
else
  link_one "$(cd "${TARGET:-$PWD}" && git rev-parse --show-toplevel 2>/dev/null || echo "${TARGET:-$PWD}")"
fi
