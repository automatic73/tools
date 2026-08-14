#!/usr/bin/env bash
# Locks: mismatched lockfile → skip link; matching lockfile → create symlink.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
link="$root/wt-link.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Two worktrees of one repo: main has node_modules; secondary will be linked.
mkdir -p "$tmp/main" "$tmp/wt"
git -C "$tmp/main" init -q
git -C "$tmp/main" config user.email "test@example.com"
git -C "$tmp/main" config user.name "test"
git -C "$tmp/main" config commit.gpgsign false
echo '{"packageManager":"pnpm@9.15.3"}' > "$tmp/main/package.json"
echo "lock-a" > "$tmp/main/pnpm-lock.yaml"
mkdir -p "$tmp/main/node_modules/.bin"
echo "ok" > "$tmp/main/node_modules/.bin/marker"
git -C "$tmp/main" add package.json pnpm-lock.yaml
git -C "$tmp/main" -c commit.gpgsign=false commit -qm "init"

git -C "$tmp/main" worktree add -q "$tmp/wt" HEAD
echo "lock-b" > "$tmp/wt/pnpm-lock.yaml"

# Mismatch → skip, leave no symlink
out=$(cd "$tmp/wt" && "$link" 2>&1)
echo "$out" | grep -q "differs from main" \
  || fail "expected lockfile mismatch skip; got: $out"
[ ! -e "$tmp/wt/node_modules" ] || fail "mismatch must not create node_modules"

# Match → link
cp "$tmp/main/pnpm-lock.yaml" "$tmp/wt/pnpm-lock.yaml"
out=$(cd "$tmp/wt" && "$link" 2>&1)
[ -L "$tmp/wt/node_modules" ] || fail "expected symlink after matching lockfile; out=$out"
[ "$(readlink "$tmp/wt/node_modules")" = "$tmp/main/node_modules" ] \
  || fail "symlink target wrong: $(readlink "$tmp/wt/node_modules")"

echo "OK wt-link (2 passed)"
