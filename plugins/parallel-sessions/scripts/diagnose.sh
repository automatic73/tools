#!/usr/bin/env bash
# Diagnoses resource pressure when running several agent sessions at once.
# Each section ends with a concrete action when there is one to take.
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"

echo "=== memory ==="
mem_report

echo
echo "=== RAM by category ==="
# Patterns are anchored to the executable rather than the whole command line:
# worktrees often live under .claude/, so a bare /claude/ match would tag every
# process running inside a worktree as an agent.
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
 if (tsn) printf "  tsc:      %7.0f MB (%d processes)%s\n", ts, tsn, (tsn>1 ? "   <- concurrent: use typecheck.sh" : "")
 if (cln) printf "  agents:   %7.0f MB (%d)\n", cl, cln
 if (edn) printf "  editor:   %7.0f MB (%d)\n", ed, edn
 if (mcn) printf "  MCP:      %7.0f MB (%d)\n", mc, mcn
 if (mtn) printf "  bundler:  %7.0f MB (%d)\n", mt, mtn
 if (nxn) printf "  dev srv:  %7.0f MB (%d)\n", nx, nxn
 if (lnn) printf "  lint/test:%7.0f MB (%d)\n", ln, lnn
}'

echo
echo "=== top 5 processes ==="
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

  echo "  $total total | $linked linked | $copies with their own copy"
  [ "$copies" -gt 0 ] && echo "  -> link them:  bash \"$SELF_DIR/wt-link.sh\" --all"
  [ "$merged" -gt 0 ] && echo "  -> $merged already in $default_branch, safe to remove (git worktree remove)"
  [ "$broken" -gt 0 ] && echo "  -> $broken with broken git metadata (inspect by hand before deleting)"
fi

# --- inherited MCP servers ---
echo
echo "=== MCP servers starting in EVERY session ==="
python3 - <<'PY' 2>/dev/null || echo "  (could not read the config)"
import json, pathlib

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
        # An ANCESTOR directory of the cwd passes its MCP servers down to every
        # project underneath it.
        cwd = pathlib.Path.cwd()
        for path, proj in d.get("projects", {}).items():
            try: ancestor = pathlib.Path(path) in cwd.parents
            except Exception: ancestor = False
            if ancestor:
                for n in proj.get("mcpServers", {}):
                    found.setdefault(n, []).append(f"parent directory {path}")
    except Exception: pass

if not found:
    print("  none: good, you are not paying for MCP servers you don't use")
else:
    print(f"  {len(found)} servers, each one a process per session:")
    for n, src in sorted(found.items()):
        print(f"    {n:<20} <- {src[0]}")
    print("  -> move the ones you don't use in THIS project to project scope")
PY
