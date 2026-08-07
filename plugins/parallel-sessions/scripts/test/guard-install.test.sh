#!/usr/bin/env bash
# Locks: install into a symlinked node_modules is denied; a real dir is allowed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
guard="$root/guard-install.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v jq >/dev/null || fail "jq required"

# Symlinked node_modules → deny
mkdir -p "$tmp/main/node_modules" "$tmp/wt"
ln -s "$tmp/main/node_modules" "$tmp/wt/node_modules"
payload=$(jq -n --arg cwd "$tmp/wt" '{cwd:$cwd, tool_input:{command:"pnpm install"}}')
out=$(printf '%s' "$payload" | "$guard")
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null \
  || fail "expected deny for symlinked node_modules; got: $out"

# Real node_modules → allow (exit 0, empty stdout)
rm -rf "$tmp/wt/node_modules"
mkdir -p "$tmp/wt/node_modules"
payload=$(jq -n --arg cwd "$tmp/wt" '{cwd:$cwd, tool_input:{command:"pnpm install"}}')
out=$(printf '%s' "$payload" | "$guard")
[ -z "$out" ] || fail "expected empty allow output; got: $out"

# Non-install command → allow even with symlink
rm -rf "$tmp/wt/node_modules"
ln -s "$tmp/main/node_modules" "$tmp/wt/node_modules"
payload=$(jq -n --arg cwd "$tmp/wt" '{cwd:$cwd, tool_input:{command:"pnpm test"}}')
out=$(printf '%s' "$payload" | "$guard")
[ -z "$out" ] || fail "expected allow for non-install; got: $out"

echo "OK guard-install (3 passed)"
