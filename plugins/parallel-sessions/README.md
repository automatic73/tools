# parallel-sessions

Run many agent sessions at once without your machine grinding to a halt.

When several agents work in parallel, what saturates a laptop usually isn't the
editor or the agents themselves: it's the processes they spawn. This plugin
targets the three costs that weigh the most and that nobody sees coming.

## The problem, with numbers

Measured on a real monorepo (32 GB of RAM, 11 open sessions, swap at 98%):

| Source | Cost |
|---|---|
| `tsc --noEmit` | **2-3 GB per run.** Three sessions typechecking at once is ~9 GB at a stroke |
| `node_modules` per worktree | ~50k files each, times however many worktrees you keep, all tracked by file watchers and Spotlight |
| Inherited MCP servers | Servers configured at global scope, or in a **parent directory**, start in every session of every project. In that case: 14 servers per session, in a project that configured none of them |

## What it does

**Shares `node_modules` across worktrees.** When a worktree is created, it links
the main worktree's `node_modules` instead of installing another copy. Only when
the lockfile matches: if the branch changed dependencies, it leaves that worktree
with its own install and tells you.

**Serializes typechecks.** One `tsc` at a time per repo, with a heap ceiling. The
rest wait their turn instead of fighting over RAM.

**Blocks installs that would break the link.** Running `bun install` inside a
linked worktree would write into the main worktree's `node_modules` and hit every
worktree at once, silently. The hook stops it and explains what to do.

**Diagnoses.** `/parallel-sessions:diagnose` tells you what is consuming what,
and the concrete action for each.

## Install

```bash
/plugin marketplace add automatic73/automatic73-tools
/plugin install parallel-sessions@automatic73
/reload-plugins
```

## Usage

The hooks work on their own. The only thing that changes in your day:

```bash
# typecheck: use this instead of npx tsc --noEmit
bash "${CLAUDE_PLUGIN_ROOT}/scripts/typecheck.sh"

# diagnose when the machine feels slow
/parallel-sessions:diagnose

# link worktrees that existed before you installed the plugin
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wt-link.sh" --all
```

So sessions use the serialized typecheck without being reminded, put it in your
`CLAUDE.md`:

```markdown
Typecheck: use `bash scripts/typecheck.sh`, NEVER `npx tsc --noEmit` directly.
```

## Also worth enabling: native symlinks

Claude Code knows how to symlink directories when creating worktrees. In your
`settings.json`:

```json
{
  "worktree": {
    "symlinkDirectories": ["node_modules"]
  }
}
```

That covers worktrees Claude Code creates. The plugin additionally covers ones
born from any `git worktree add`, and keeps a later install from breaking the
link.

## Interoperability

Works alongside [superpowers](https://github.com/obra/superpowers), which solves
a different problem: its `using-git-worktrees` skill **creates** the worktree
(picks the directory, verifies gitignore, runs a test baseline). This plugin
handles what that worktree **costs** while it exists.

One detail about that combination: the skill's setup step runs `npm install` in
every new worktree. This plugin links `node_modules` before that happens, so the
install finds nothing to do and the two don't conflict.

## Known trade-off in workspace monorepos

Sharing `node_modules` has one real consequence worth knowing before you enable
it: internal workspace packages (`@scope/*`) resolve against the **main
worktree's** `packages/` directory, not your worktree's.

So if the main worktree sits on a different branch, `tsc` reads that branch's
`package.json` exports, and you get errors like `Cannot find module
'@scope/shared/utils/thing'` in files you never touched. Worse, the same command
can pass and then fail minutes later without you changing a line, because
somebody moved the main worktree to another branch in between.

`typecheck.sh` warns when it detects that mismatch, so you don't spend an hour
chasing a bug that isn't yours:

```
note: the main worktree is on 'feature/x', this one is on 'feature/y'.
      Workspace packages resolve against the main worktree, so unrelated
      'Cannot find module' errors may come from that branch, not your changes.
```

When it matters, the escape hatch is a real install for that worktree: remove
the symlink (`rm node_modules`) and install normally. You give up the sharing for
that worktree and keep it everywhere else.

This does not affect repos without workspace packages.

## Compatibility

- **Package managers**: bun, pnpm, yarn and npm. Detected from the
  `packageManager` field in `package.json`, falling back to the lockfile present.
- **Systems**: macOS and Linux.
- **Requires**: `git`, `bash`, `jq`. Without `jq` the hooks disable themselves
  rather than breaking your session.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PS_TYPECHECK_HEAP` | `3072` | `tsc` heap ceiling, in MB |
| `PS_TYPECHECK_WAIT` | `1200` | Max seconds waiting for a turn |

## License

MIT
