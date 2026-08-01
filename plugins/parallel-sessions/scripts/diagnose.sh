#!/usr/bin/env bash
# Diagnostico de saturacion cuando corres varias sesiones de agente a la vez.
# Cada seccion termina con la accion concreta, si hay algo que hacer.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"

echo "=== memoria ==="
mem_report

echo
echo "=== RAM por categoria ==="
# Los patrones van anclados al ejecutable, no al command line completo: los
# worktrees suelen vivir bajo .claude/, asi que un /claude/ suelto marcaria como
# "agente" cualquier proceso que corra dentro de un worktree.
ps -Ao rss,command 2>/dev/null | awk '
{ rss=$1/1024; cmd=$0; exe=$2;
  if      (cmd ~ /\/bin\/tsc([ ]|$)/ || cmd ~ /(^| )tsc --/ || cmd ~ /exec tsc([ ]|$)/) { ts+=rss; tsn++ }
  else if (exe ~ /(^|\/)claude$/ || cmd ~ /claude-code\//)   { cl+=rss; cln++ }
  else if (cmd ~ /Cursor Helper|Cursor\.app|Code Helper|windsurf/) { ed+=rss; edn++ }
  else if (cmd ~ /mcp-server|-mcp([ ]|$)|\/mcp\/|_npx\//)    { mc+=rss; mcn++ }
  else if (cmd ~ /\/metro|expo start/)                       { mt+=rss; mtn++ }
  else if (cmd ~ /next-server|\/vite([ ]|$)|\/webpack/)      { nx+=rss; nxn++ }
  else if (cmd ~ /\/eslint([ ]|$)|\/jest([ ]|$)|\/vitest([ ]|$)/) { ln+=rss; lnn++ }
}
END {
 if (tsn) printf "  tsc:      %7.0f MB (%d procesos)%s\n", ts, tsn, (tsn>1 ? "   <- concurrentes: usa typecheck.sh" : "")
 if (cln) printf "  agentes:  %7.0f MB (%d)\n", cl, cln
 if (edn) printf "  editor:   %7.0f MB (%d)\n", ed, edn
 if (mcn) printf "  MCP:      %7.0f MB (%d)\n", mc, mcn
 if (mtn) printf "  bundler:  %7.0f MB (%d)\n", mt, mtn
 if (nxn) printf "  dev srv:  %7.0f MB (%d)\n", nx, nxn
 if (lnn) printf "  lint/test:%7.0f MB (%d)\n", ln, lnn
}'

echo
echo "=== top 5 procesos ==="
ps -Ao rss,pid,command -r 2>/dev/null | sed -n '2,6p' |
  awk '{rss=$1/1024; pid=$2; $1="";$2=""; printf "  %6.0f MB  %-7s %.62s\n", rss, pid, $0}'

# --- worktrees ---
if git rev-parse --git-dir >/dev/null 2>&1; then
  MAIN=$(main_worktree)
  echo
  echo "=== worktrees ==="
  total=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
  linked=0; copies=0; merged=0; broken=0
  default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/main")

  while read -r wt; do
    [ "$wt" = "$MAIN" ] && continue
    if [ -L "$wt/node_modules" ]; then linked=$((linked+1))
    elif [ -d "$wt/node_modules" ]; then copies=$((copies+1)); fi
    if sha=$(git -C "$wt" rev-parse HEAD 2>/dev/null); then
      git merge-base --is-ancestor "$sha" "$default_branch" 2>/dev/null && merged=$((merged+1))
    else
      broken=$((broken+1))
    fi
  done < <(git worktree list --porcelain 2>/dev/null | grep "^worktree" | cut -d' ' -f2)

  echo "  $total en total | $linked enlazados | $copies con copia propia"
  [ "$copies" -gt 0 ] && echo "  -> enlazar:  bash \"$SELF_DIR/wt-link.sh\" --all"
  [ "$merged" -gt 0 ] && echo "  -> $merged ya estan en $default_branch, se pueden borrar (git worktree remove)"
  [ "$broken" -gt 0 ] && echo "  -> $broken con git roto (revisalos a mano antes de borrar)"
fi

# --- MCP heredados ---
echo
echo "=== MCP que arrancan en CADA sesion ==="
python3 - <<'PY' 2>/dev/null || echo "  (no se pudo leer la config)"
import json, os, pathlib

home = pathlib.Path.home()
found = {}

p = home / ".claude/mcp.json"
if p.exists():
    try:
        for n in json.loads(p.read_text()).get("mcpServers", {}):
            found.setdefault(n, []).append("~/.claude/mcp.json")
    except Exception: pass

p2 = home / ".claude.json"
if p2.exists():
    try:
        d = json.loads(p2.read_text())
        for n in d.get("mcpServers", {}):
            found.setdefault(n, []).append("~/.claude.json (global)")
        # Un directorio ANCESTRO del cwd hereda sus MCP a todo proyecto que cuelgue de el.
        cwd = pathlib.Path.cwd()
        for path, proj in d.get("projects", {}).items():
            try: ancestor = pathlib.Path(path) in cwd.parents
            except Exception: ancestor = False
            if ancestor:
                for n in proj.get("mcpServers", {}):
                    found.setdefault(n, []).append(f"directorio padre {path}")
    except Exception: pass

if not found:
    print("  ninguno: bien, no pagas MCP que no usas")
else:
    print(f"  {len(found)} servidores, cada uno un proceso por sesion:")
    for n, src in sorted(found.items()):
        print(f"    {n:<20} <- {src[0]}")
    print("  -> los que no uses en ESTE proyecto, muevelos a scope de proyecto")
PY
