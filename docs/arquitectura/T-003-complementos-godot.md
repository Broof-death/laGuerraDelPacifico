# T-003: evaluación de complementos de Godot

Fecha: 17-10-2026. Agente: arquitecto. Proyecto en Godot 4.7, renderer GL Compatibility, Jolt.
Decisiones de referencia: ADR-006 (simulación de datos puros en PackedArrays, 6 x 500, pruebas headless y de carga) y ADR-007 (carpetas y convenciones).

## Resumen

| Complemento | Versión evaluada (fecha) | Licencia | Godot 4.7 | GL Compatibility | Tipo | Recomendación |
|---|---|---|---|---|---|---|
| gdUnit4 | v6.2.2 (07-10-2026); master = v7.0.0 | MIT | Sí: la tabla oficial indica 4.7 y 4.7.1 para v6.2.x | No aplica (no dibuja) | Addon en GDScript puro | **Adoptar** (v6.2.x fijada) |
| Terrain3D | v1.0.2-stable (19-05-2026); v1.1.0-rc1 (17-10-2026) | MIT | Sí: v1.0.2 declara 4.4 a 4.7; v1.1.0-rc1, 4.5 a 4.8 | Sí: soporte completo desde v1.0 y Godot 4.4 | GDExtension en C++ (binarios por plataforma) | **Posponer** a T-036 (candidato fuerte, solo cliente) |
| LimboAI | v1.8.1 (20-08-2026) | MIT | Sí: v1.8.0 agrega 4.7; v1.8.1 se compiló con 4.7.2 | No aplica | GDExtension en C++ o módulo del motor | **No adoptar** (revisable para la IA bot) |
| Servidor MCP de Godot (p. ej. Coding-Solo/godot-mcp) | sin releases publicados | MIT | Usa la línea de comandos de Godot, independiente de la versión | No aplica | Servidor Node.js 18+ externo al proyecto | **No adoptar en el repo**; opcional en la configuración local de cada persona |

## gdUnit4: adoptar

- **Estado:** mantenido activamente. Releases cada 1 o 2 meses (6.1.0 en enero de 2026 para 4.6; 6.2.0, 6.2.1 y 6.2.2 entre julio y octubre de 2026). Su CI ya prueba con 4.8.dev.
- **Encaje con ADR-006:** la simulación es un `RefCounted` sin escena (`Simulation.step()`), y EntityStore, SpatialGrid, el SnapshotCodec y bit_writer/bit_reader son clases puras. Son el caso ideal para pruebas unitarias. gdUnit4 aporta aserciones, pruebas parametrizadas (útiles para la ida y vuelta del códec con muchas semillas), detección de nodos huérfanos y reportes JUnit (results.xml) y HTML para CI.
- **Headless/CI:** `addons/gdUnit4/runtest.cmd` (Windows) y `runtest.sh` (Linux) con `GODOT_BIN` o `--godot_binary`. Por defecto gdUnit4 **se niega a correr en modo headless** (por las pruebas de entrada y UI), así que hay que pasar `--ignoreHeadlessMode`. Las pruebas de sim/ y core/ no usan entrada, así que no hay problema. Códigos de salida: 0 = OK, 100 = fallos, 101 = advertencias. Existe la GitHub Action `gdunit4-action` para CI.
  Comando previsto: `addons/gdUnit4/runtest.cmd --godot_binary <ruta> --headless --ignoreHeadlessMode -a res://tests/sim -a res://tests/core`. La tarea de instalación debe verificarlo.
- **Pruebas de carga:** NO van en gdUnit4. Siguen como en ADR-006: `tests/load/load_test.tscn` ejecutado con `godot --headless`, con salida en JSON. gdUnit4 mide en ms con un timeout por prueba, no sirve para percentiles.
- **Costo:** bajo. Es GDScript puro (sin binarios), se instala en `addons/gdUnit4/` y se activa en Project Settings > Plugins. Se fija la versión, porque la línea v6 no es compatible hacia atrás y v7.0.0 (master) aún no sale. Hay que excluir `addons/gdUnit4/` y `tests/` de los presets de exportación.
- **Alternativa:** GUT (MIT, también mantenido). Es más simple, pero tiene menos aserciones y peores reportes de CI. Con gdUnit4 ya previsto en ADR-006 y sin una ventaja clara de GUT, no se cambia.

## Terrain3D: posponer a T-036 (candidato fuerte)

- **Estado:** mantenido (1.0.0 en marzo de 2025, 1.0.1 en junio de 2025, 1.0.2 en mayo de 2026 y 1.1.0-rc1 el 17-10-2026). La documentación declara que GL Compatibility tiene soporte completo desde 1.0 y Godot 4.4, y 1.0.2 corrige errores de shader en ese modo. Web/WebGL es experimental (no nos afecta).
- **Qué ofrece:** clipmap geométrico (más detalle cerca de la cámara), regiones no contiguas, `vertex_spacing` para escalar, importación de heightmaps (GEBCO y Copernicus convertidos a EXR o R16), consulta de altura desde código, colisión dinámica alrededor de la cámara y geometría para navmesh. Su máximo es 65,5 km por lado con spacing 1; con spacing >= 2 cubre los 125 km.
- **Encaje con ADR-006/007:** solo puede ser **cliente** (`client/world/`). La simulación no puede depender de un nodo de escena ni de una GDExtension de render: transitabilidad, costa y altura que afecten la lógica salen de datos propios (grillas en PackedArrays que lee sim/, alineadas con la celda de 64 m). Terrain3D y la simulación pueden partir del mismo heightmap fuente, pero por caminos separados. ADR-007 ya lo dice para procedural_floor.gd.
- **Riesgo principal, la memoria:** Terrain3D 1.0 mantiene en RAM y VRAM los mapas de todas las regiones (altura de 4 B, control de 4 B y color de 4 B por vértice, unos 12 B) y no hace streaming de regiones. Estimación para 125 x 125 km:

  | vertex_spacing | vértices por lado | memoria (cuadrado completo) | solo tierra (~50 %) |
  |---|---|---|---|
  | 2 m | 62 500 | ~47 GB | ~23 GB |
  | 4 m | 31 250 | ~11,7 GB | ~5,9 GB |
  | 8 m | 15 625 | ~2,9 GB | ~1,5 GB |
  | 16 m | 7 812 | ~0,73 GB | ~0,37 GB |

  El spacing de 2,0 que se mencionó en T-010/T-036 **no es viable** con el mapa completo. Hay que usar entre 8 y 16 m, quitar el mapa de color o usar regiones solo en tierra y costa (el mar profundo puede ser un plano de agua). Como referencia, los datos de origen a escala 1:20 dan unos 22 m de juego con GEBCO (450 m reales) y 1,5 m con Copernicus (30 m reales), así que entre 8 y 16 m no se pierde detalle en el mar y se pierde poco en tierra para una cámara RTS.
- **Costo:** medio. Son binarios C++ por plataforma (Windows y Linux para el servidor dedicado, aunque el servidor no lo usaría), un editor propio y un pipeline de importación de heightmaps. Si se descarta más adelante, solo se reescribe la capa client/world/.
- **Por qué posponer y no adoptar ya:** la viabilidad depende de T-010 (límites del mapa y sectores) y de la prueba de 60 FPS de T-036. Si se adopta ahora, el proyecto queda atado a un spacing y a un uso de memoria que nadie ha medido. Si se descarta ahora, se pierde la opción más madura (la alternativa es un clipmap o malla por sectores propio, con más trabajo). T-036 debe prototipar Terrain3D v1.0.2 (o 1.1.0 si ya está estable) con un heightmap de 125 km, spacing 8 y 16, en GL Compatibility, y medir FPS, RAM, VRAM y tiempo de carga.

## LimboAI: no adoptar

- **Estado:** mantenido (1.5 en octubre de 2025, 1.6 y 1.7 a inicios de 2026, 1.8.0 en junio de 2026 con soporte para 4.7, y 1.8.1 en agosto de 2026). Se distribuye como GDExtension (AssetLib) o como módulo, que exige compilar el motor. La GDExtension tiene menos funciones que el módulo.
- **Encaje con ADR-006:** malo.
  - **Unidades:** ADR-006 descarta un objeto por entidad. El comportamiento de las 3000 unidades son sistemas que recorren PackedArrays (adquisición de objetivos a 5 Hz, movimiento a 20 Hz). Un árbol de comportamiento por unidad (BTPlayer o BTInstance con un agente Node) reintroduce nodos y objetos por entidad, que es justo lo que ADR-006 prohíbe por costo.
  - **IA bot (2 Hz, una por jugador bot):** son pocas instancias, así que el costo no es problema. Pero LimboAI espera un agente `Node` y un `scene_root`, y la simulación no toca el SceneTree (ADR-006, punto 1) y debe poder correr en un hilo. Además, mete un binario C++ en sim/, lo que complica el servidor dedicado. La IA bot emite Commands a la misma cola, y una máquina de estados o un sistema de utilidad simple en GDScript (sim/ai/) basta para la v1.
- **Costo:** medio (binarios, editor de árboles en .tres que se acoplan a nodos) para un beneficio que el diseño actual no usa.
- **Cuándo revisarlo:** si la IA bot crece a muchos comportamientos jerárquicos y el GDScript a mano se vuelve inmanejable, se reevalúa en un ADR propio, usando solo las clases de BT sin nodos, si la versión de ese momento lo permite. También podría servir para lógica de cliente (tutoriales, cinemáticas) que sí vive en el SceneTree.

## Servidor MCP para Godot: no adoptar en el repo

- **Opciones:** Coding-Solo/godot-mcp (MIT, Node 18+, herramientas `run_project`, `get_debug_output`, `stop_project`, creación de escenas y UIDs; sin releases publicados) y otras con objetivos parecidos (struktured-labs/godot-mcp, que usa GUT; hyunlord/godot-test-mcp). Ninguna es estándar ni tiene una cadencia de releases clara.
- **Encaje:** Claude Code ya puede ejecutar `godot --headless --path <proyecto> ...` por Bash y leer stdout/stderr: pruebas gdUnit4 (`runtest.cmd`), prueba de carga (`tests/load/load_test.tscn`) y chequeo de scripts con `--check-only` o `--import` y `--quit`. Eso cubre "ejecutar y leer errores" sin dependencias nuevas, y es reproducible en CI. Las herramientas del MCP para crear escenas o nodos chocan con la regla de ADR-007 de mover y renombrar desde el editor.
- **Recomendación:** no va en el repo ni en `.mcp.json` compartido. Cada persona puede instalarlo en su configuración local si le sirve para ver la ejecución con ventana. Lo que sí conviene es documentar en `tests/README.md` (tarea de instalación de gdUnit4) los comandos headless para que ambos Claude los usen igual.

## Fuentes

- Terrain3D: https://github.com/TokisanGames/Terrain3D (MIT), releases https://github.com/TokisanGames/Terrain3D/releases, plataformas https://terrain3d.readthedocs.io/en/latest/docs/platforms.html
- gdUnit4: https://github.com/godot-gdunit-labs/gdUnit4 (MIT, tabla de compatibilidad), releases https://github.com/MikeSchulze/gdUnit4/releases, CLI https://godot-gdunit-labs.github.io/gdUnit4/latest/advanced_testing/cmd/, `--ignoreHeadlessMode` en `addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd` (v6.2.2)
- LimboAI: https://github.com/limbonaut/limboai (MIT), releases https://github.com/limbonaut/limboai/releases
- Godot MCP: https://github.com/Coding-Solo/godot-mcp (MIT)
