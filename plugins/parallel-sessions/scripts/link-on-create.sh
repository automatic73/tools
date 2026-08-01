#!/usr/bin/env bash
# Enlaza el node_modules de un worktree recien creado, ANTES de que algo intente
# instalarlo.
#
# Cubre las dos formas en que nace un worktree:
#   - WorktreeCreate: los que crea Claude Code (--worktree, EnterWorktree, agentes)
#   - PostToolUse/Bash: los que crea cualquier otro flujo con 'git worktree add',
#     por ejemplo la skill using-git-worktrees de superpowers, que despues corre
#     'npm install' como paso de setup. Al llegar enlazado, ese install ya no
#     tiene nada que hacer y no choca con guard-install.
#
# Silencioso por diseño: es un hook, no debe ensuciar la sesion ni fallar nunca.
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
    # PostToolUse sobre Bash: solo nos interesa 'git worktree add'.
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
    printf '%s' "$cmd" | grep -qE 'git[[:space:]]+worktree[[:space:]]+add' || exit 0
    # Primer argumento no-flag despues de 'add' es la ruta destino.
    path=$(printf '%s' "$cmd" |
      sed -nE 's/.*git[[:space:]]+worktree[[:space:]]+add[[:space:]]+(.*)/\1/p' |
      tr ' ' '\n' | grep -vE '^-' | head -1)
    ;;
esac

[ -n "$path" ] || exit 0
[ -d "$path" ] || exit 0

bash "$SELF_DIR/wt-link.sh" --quiet "$path" >/dev/null 2>&1 || true
exit 0
