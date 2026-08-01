#!/usr/bin/env bash
# Typecheck serializado entre worktrees y sesiones.
#
# Por que: en un monorepo grande 'tsc --noEmit' pesa 2-3 GB. Con varias sesiones
# de agente typecheckeando a la vez se van 9 GB de golpe y la maquina swapea.
# Este wrapper deja correr un solo tsc a la vez por repo y le pone techo de heap.
#
# Uso: typecheck.sh [args extra para tsc]
# Env: PS_TYPECHECK_HEAP (MB, default 3072), PS_TYPECHECK_WAIT (segundos, default 1200)
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"

# Un lock por repositorio: dos proyectos distintos si pueden typecheckear a la vez.
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
    # Lock huerfano: el proceso que lo tomo ya murio.
    owner=$(cat "$LOCK/pid" 2>/dev/null || echo "")
    if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$LOCK"; continue
    fi
    [ "$waited" = "0" ] && echo "⏳ otro typecheck corriendo (pid $owner), esperando turno..."
    sleep 2; waited=$((waited + 2))
    if [ "$waited" -ge "$WAIT_MAX" ]; then
      echo "❌ timeout tras ${WAIT_MAX}s esperando el lock (pid $owner sigue vivo)" >&2
      exit 1
    fi
  done
}

acquire
# Sin 'exec': reemplazaria el shell y el trap nunca correria, dejando el lock huerfano.
# shellcheck disable=SC2086
$(runner_for "$(detect_pm "${REPO:-.}")") tsc --noEmit "$@"
