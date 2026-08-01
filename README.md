# automatic73-tools

Herramientas de desarrollo hechas en
[automatic73](https://github.com/automatic73), sacadas de problemas reales al
trabajar con varios agentes a la vez.

Hoy son plugins de Claude Code. El repo es también un marketplace, así que se
instalan con un comando.

## Instalación

```bash
/plugin marketplace add automatic73/automatic73-tools
```

Luego instala el que quieras:

```bash
/plugin install parallel-sessions@automatic73
/reload-plugins
```

## Plugins

| Plugin | Qué resuelve |
|---|---|
| [parallel-sessions](plugins/parallel-sessions) | Correr muchas sesiones de agente sin saturar la máquina: comparte `node_modules` entre worktrees, serializa los typechecks y detecta MCP que arrancan de más |

## Desarrollo

Probar un plugin sin instalarlo:

```bash
claude --plugin-dir ./plugins/parallel-sessions
```

Validar antes de publicar:

```bash
claude plugin validate ./plugins/parallel-sessions
```

## Licencia

MIT
