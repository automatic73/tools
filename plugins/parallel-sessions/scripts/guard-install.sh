#!/usr/bin/env bash
# Hook PreToolUse: bloquea instalar dependencias dentro de un worktree cuyo
# node_modules es un symlink al del worktree principal.
#
# Por que: el install escribiria en el node_modules del principal y afectaria a
# todos los worktrees a la vez, en silencio. Este caso aparece solo cuando algo
# se salta el enlace previo (por ejemplo una skill que corre 'npm install' como
# parte de su setup); en el flujo normal el worktree ya viene enlazado.
set -uo pipefail

payload=$(cat)

# Sin jq, degradar a permitir: un hook no debe romper la sesion de nadie.
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // .workspace.current_dir // ""' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"

# Solo comandos de instalacion.
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(bun|npm|pnpm|yarn)[[:space:]]+(install|add|i|ci)([[:space:]]|$)' || exit 0

# Si el comando trae un 'cd', evaluar ese destino.
target=$(printf '%s' "$cmd" | sed -nE 's/.*cd[[:space:]]+([^;&|]+).*/\1/p' | head -1 | xargs 2>/dev/null || true)
if [ -n "$target" ]; then
  case "$target" in
    /*) cwd="$target" ;;
    ~*) cwd="${target/#\~/$HOME}" ;;
    *)  cwd="$cwd/$target" ;;
  esac
fi

# Subir hasta el primer node_modules.
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -e "$dir/node_modules" ]; then
    if [ -L "$dir/node_modules" ]; then
      real=$(readlink "$dir/node_modules")
      jq -n --arg d "$dir" --arg r "$real" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("node_modules en \($d) es un enlace a \($r), compartido con el worktree principal. Instalar aqui escribiria ahi y afectaria a TODOS los worktrees a la vez.\n\nSi esta rama necesita dependencias distintas:  rm \($d)/node_modules  y vuelve a instalar.\nSi no las necesita: instala en el worktree principal y el enlace ya te trae el resultado.")
        }
      }'
      exit 0
    fi
    break
  fi
  dir=$(dirname "$dir")
done

exit 0
