# automatic73-tools

Development tooling built at [automatic73](https://github.com/automatic73), out
of real problems from working with several coding agents at once.

Today it holds:

- Claude Code plugins (published through the marketplace)
- Shared MCP setup bundles (scripts + docs)

## Install

```bash
/plugin marketplace add automatic73/automatic73-tools
```

Then install whichever you want:

```bash
/plugin install parallel-sessions@automatic73
/reload-plugins
```

## Plugins

| Plugin | What it solves |
|---|---|
| [parallel-sessions](plugins/parallel-sessions) | Running many agent sessions without saturating the machine: shares `node_modules` across worktrees, serializes typechecks, and finds MCP servers starting in every session |

## MCP bundles

| Bundle | What it solves |
|---|---|
| [mcp/ga4-ads](mcp/ga4-ads) | One-shot setup for official Google Analytics + Google Ads MCP servers in Cursor/Claude with secrets pulled from Doppler |

Setup:

```bash
bash mcp/ga4-ads/setup.sh
```

Defaults use Doppler project `automatic73-ops` and config `prd`. Override with
`DOPPLER_PROJECT` / `DOPPLER_CONFIG` when needed.

## Development

Test a plugin without installing it:

```bash
claude --plugin-dir ./plugins/parallel-sessions
```

Validate before publishing:

```bash
claude plugin validate ./plugins/parallel-sessions
```

## License

MIT
