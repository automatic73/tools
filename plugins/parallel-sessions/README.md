# parallel-sessions

Corre muchas sesiones de agente a la vez sin que la máquina se arrastre.

Con varios agentes trabajando en paralelo, lo que satura una laptop no suele ser
el editor ni los agentes: son los procesos que disparan. Este plugin ataca los
tres costos que más pesan y que nadie ve venir.

## El problema, con números

Medido en un monorepo real (32 GB de RAM, 11 sesiones abiertas, swap al 98%):

| Fuente | Costo |
|---|---|
| `tsc --noEmit` | **2-3 GB por corrida.** Tres sesiones typecheckeando a la vez son ~9 GB de golpe |
| `node_modules` por worktree | ~50k archivos cada uno, multiplicado por cuantos worktrees tengas, todos vigilados por watchers y Spotlight |
| MCP heredados | Los configurados en scope global o en un **directorio padre** arrancan en toda sesión de todo proyecto. En ese caso eran 14 servidores por sesión, de un proyecto que no configuraba ninguno |

## Qué hace

**Comparte `node_modules` entre worktrees.** Cuando creas un worktree, enlaza el
`node_modules` del principal en vez de instalar otra copia. Solo si el lockfile
coincide: si la rama cambió dependencias, la deja con su propio install y te lo
dice.

**Serializa los typechecks.** Un solo `tsc` a la vez por repo, con techo de heap.
Los demás esperan turno en vez de pelear por la RAM.

**Bloquea installs que romperían el enlace.** Correr `bun install` dentro de un
worktree enlazado escribiría en el `node_modules` del principal y afectaría a
todos a la vez, en silencio. El hook lo detiene y explica qué hacer.

**Diagnostica.** `/parallel-sessions:diagnose` dice qué está consumiendo qué, y
la acción concreta para cada cosa.

## Instalación

```bash
/plugin marketplace add automatic73/automatic73-tools
/plugin install parallel-sessions@automatic73
/reload-plugins
```

## Uso

Los hooks trabajan solos. Lo único que cambia en tu día:

```bash
# typecheck: usa esto en vez de npx tsc --noEmit
bash "${CLAUDE_PLUGIN_ROOT}/scripts/typecheck.sh"

# diagnóstico cuando sientas la máquina lenta
/parallel-sessions:diagnose

# enlazar worktrees que ya existían antes de instalar el plugin
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wt-link.sh" --all
```

Para que las sesiones usen el typecheck serializado sin que se lo recuerdes,
ponlo en tu `CLAUDE.md`:

```markdown
Typecheck: usa `bash scripts/typecheck.sh`, NUNCA `npx tsc --noEmit` directo.
```

## Conviene además activar el enlace nativo

Claude Code sabe enlazar directorios al crear worktrees. En tu `settings.json`:

```json
{
  "worktree": {
    "symlinkDirectories": ["node_modules"]
  }
}
```

Eso cubre los worktrees que crea Claude Code. El plugin cubre además los que
nacen de un `git worktree add` cualquiera, y evita que un install posterior
rompa el enlace.

## Interoperabilidad

Funciona junto a
[superpowers](https://github.com/obra/superpowers), que resuelve un problema
distinto: su skill `using-git-worktrees` **crea** el worktree (elige carpeta,
verifica gitignore, corre el baseline de tests). Este plugin se encarga de lo que
ese worktree **cuesta** mientras existe.

Un detalle de esa combinación: el paso de setup de esa skill corre
`npm install` en cada worktree nuevo. Este plugin enlaza el `node_modules` antes
de que eso ocurra, así que el install no encuentra trabajo que hacer y no hay
conflicto.

## Compatibilidad

- **Gestores**: bun, pnpm, yarn y npm. Se detecta por el campo `packageManager`
  de `package.json`, y si no está, por el lockfile presente.
- **Sistemas**: macOS y Linux.
- **Dependencias**: `git`, `bash`, `jq`. Sin `jq` los hooks se desactivan solos
  en vez de romper la sesión.

## Configuración

| Variable | Default | Para qué |
|---|---|---|
| `PS_TYPECHECK_HEAP` | `3072` | Techo de heap de `tsc`, en MB |
| `PS_TYPECHECK_WAIT` | `1200` | Segundos máximos esperando el turno |

## Licencia

MIT
