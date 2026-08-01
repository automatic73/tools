---
description: Diagnose why the machine bogs down when running several agent sessions at once. Use when the machine is slow, swapping, or freezing, or when the user asks what is eating their RAM.
---

# Diagnose resource pressure

Run the diagnostic and explain the result:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/diagnose.sh"
```

It reports RAM by category, worktree state, and MCP servers that start in every
session. Each section ends with a concrete action when there is one to take.

## Reading the output

**Swap is the signal, not free RAM.** macOS reports nearly all RAM as used by
design (cache and compressor), so "0 MB free" means nothing. Swap above 70% does:
that is where the machine starts dragging.

Usual suspects, heaviest first:

| Signal | What it means | Fix |
|---|---|---|
| Several `tsc` at once | Each costs 2-3 GB in a monorepo. The most common cause | `scripts/typecheck.sh` serializes them |
| Many MCP processes | Servers configured at global scope, or in a **parent directory**, start in every session of every project | Move the ones you don't use here to project scope |
| Worktrees with their own copy | Each is ~50k files that watchers and Spotlight keep tracking | `scripts/wt-link.sh --all` |
| Worktrees already merged | They pile up on their own | `git worktree remove` |

## When proposing actions

Before removing any worktree, check it has no uncommitted work (`git status`)
and no commits missing from the main branch. A worktree whose git metadata is
broken cannot be inspected: do not delete it without telling the user.

MCP config changes only apply to **new sessions**. Servers from already-open
sessions stay alive until those sessions close, so don't expect the count to
drop right away.
