---
description: Diagnostica por que se satura la maquina al correr varias sesiones de agente en paralelo. Usar cuando el equipo va lento, swapea, se congela, o el usuario pregunta que esta consumiendo la RAM.
---

# Diagnosticar saturacion

Corre el diagnostico y explica el resultado:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/diagnose.sh"
```

Reporta RAM por categoria, worktrees, y MCP que arrancan en cada sesion. Cada
seccion trae la accion sugerida cuando hay algo que hacer.

## Como leer la salida

**El swap es la señal, no la RAM libre.** macOS reporta casi toda la RAM como
usada por diseño (cache y compressor), asi que "0 MB libres" no significa nada.
Un swap arriba de 70% si: ahi es donde se siente la maquina arrastrando.

Sospechosos en orden de peso tipico:

| Señal | Que significa | Que hacer |
|---|---|---|
| Varios `tsc` a la vez | Cada uno pesa 2-3 GB en un monorepo. Es la causa mas comun | `scripts/typecheck.sh` los serializa |
| Muchos procesos MCP | Los MCP configurados en scope global, o en un **directorio padre**, arrancan en toda sesion de todo proyecto | Bajar a scope de proyecto los que no uses aqui |
| Worktrees con copia propia | Cada uno son ~50k archivos que watchers y Spotlight vigilan | `scripts/wt-link.sh --all` |
| Worktrees ya mergeados | Se acumulan solos | `git worktree remove` |

## Al proponer acciones

Antes de borrar cualquier worktree, revisa que no tenga trabajo sin commitear
(`git status`) ni commits que no esten en la rama principal. Un worktree cuyo
git esta roto no se puede inspeccionar: no lo borres sin avisar al usuario.

Los cambios de configuracion de MCP solo aplican a **sesiones nuevas**. Los
procesos de las sesiones ya abiertas siguen vivos hasta que se cierren, asi que
no esperes que el numero baje de inmediato.
