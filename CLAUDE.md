# La Guerra del Pacífico

Videojuego en **Godot 4 (GDScript)** sobre la Guerra del Pacífico (1879–1884). Lo hace un equipo de dos personas, cada una con su propio Claude Code. La coordinación pasa por la **pizarra**, un tablero compartido en Firebase al que se accede con las herramientas MCP `pizarra` y con la interfaz web (`tools/pizarra/`).

## Protocolo de trabajo con la pizarra

1. **Al empezar cada conversación**, revisa el resumen de la pizarra que entrega el hook de inicio (o llama a `pizarra_resumen`). Cuéntale brevemente a la persona lo relevante: sus bloqueos pendientes, novedades del equipo y los próximos pasos de la última sesión.
2. **Cuando la persona pida implementar algo nuevo**, usa el agente `orquestador` para crear la propuesta y las tareas antes de escribir código.
3. **Bloqueos humanos:** si una tarea necesita una decisión de una persona, se registra con `crear_pregunta` y la tarea queda `bloqueada`. **No avances una tarea bloqueada.**
   - Si el bloqueo es para la persona con la que hablas, pregúntale en el chat (con opciones si las hay) y registra su respuesta con `responder_pregunta`.
   - Si es para la otra persona, déjalo registrado y sigue con otras tareas.
4. **Ejecuta cada tarea con su agente** (`arquitecto`, `game-designer`, `historiador`, `dev-godot`, `qa`) y mantén los estados al día: `en_progreso` al empezar, `en_revision` al terminar, `hecha` solo cuando QA la aprueba.
5. **Decisiones** de arquitectura, diseño o historia: se registran con `registrar_decision`. Las personas las aceptan desde la pizarra o en el chat.
6. **Antes de terminar la conversación**, usa el agente `cronista` para cerrar la sesión. Así la próxima conversación, tuya o de tu compañero, sabe qué se hizo.
7. Las respuestas de la pizarra incluyen las **novedades** del equipo. Si cambian lo que estás haciendo, avísale a la persona.

En todas las herramientas de la pizarra, indica en `actor` el agente que realiza la acción. Si la acción la pidió directamente la persona, omítelo.

## Git (GitFlow)

- `main`: versiones estables. `develop`: integración.
- Trabajo nuevo en `feature/<id-tarea>-<descripcion>` desde `develop` (ej.: `feature/T-012-combate-naval`).
- Commits con el ID de la tarea: `feat(T-012): movimiento de buques`.
- No fusionar en `develop` ni en `main` sin que la persona lo pida.

## Estructura

- `project.godot` y el juego en la raíz del repo.
- `docs/diseno/`: diseño del juego (GDD). `docs/historia/`: fichas históricas con fuentes. `docs/decisiones/`: ADR aceptados exportados.
- `tools/pizarra/`: pizarra (interfaz web, servidor MCP, reglas de Firestore). Tiene `.gdignore`, así que Godot la ignora. Ver su `README.md`.
- `.claude/agents/`: definición de los agentes, compartida por el equipo.
