# Pruebas

- `tests/sim/`: pruebas unitarias de la simulación, del servidor de partida (MatchServer con
  LocalTransport) y de ENet en 127.0.0.1 (gdUnit4 v6.2.2, en `addons/gdUnit4/`).
- `tests/core/`: pruebas unitarias del código compartido: BitWriter/BitReader, códec de comandos y
  códec de snapshots (ida y vuelta, delta contra ack, acks y paquetes perdidos, tope de 4 KB).
- `tests/client/`: pruebas unitarias de las vistas del cliente sin GPU (T-017): mallas provisionales,
  colores de bando, catálogo visual (def -> malla o escena), niveles de detalle, pool de vistas y
  reparto entre vistas y lotes. Selección y órdenes (T-007): proyección con cámara sintética,
  rectángulo, clic, Shift, grupos de control, armado de comandos en bloques de 512 y el costo del
  rectángulo con 2000 unidades (`test_selection.gd`, imprime `SELECTION_PERF`); y el
  `SelectionController` con MatchServer y MatchClient reales por LocalTransport
  (`test_selection_controller.gd`).
- `tests/sandbox/selection_capture.tscn` (con ventana): abre la partida local, simula un arrastre
  y una orden con eventos de entrada reales y guarda una captura
  (`-- --out=ruta.png --zoom=0.36 --focus=60,0 --yaw=0`).
- `tests/load/`: prueba de carga headless de ADR-006 (no usa gdUnit4) y prueba de render del cliente
  (`render_load.tscn`, con ventana). Ver `tests/load/README.md`.
- `tests/net/`: comprobación de red con dos procesos de Godot (ver abajo).

## Primera vez (o tras clonar)

El proyecto necesita la carpeta `.godot/` (caché de importación y de clases globales):

```bash
godot --headless --path . --import
```

## Pruebas unitarias (headless)

gdUnit4 se niega a correr en headless si no se pasa `--ignoreHeadlessMode` (las pruebas de sim/
no usan entrada ni UI, así que no hay problema).

Windows (cmd; con `GODOT_BIN` apuntando al ejecutable de Godot 4.7):

```bat
addons\gdUnit4\runtest.cmd --headless --ignoreHeadlessMode -a res://tests/sim -a res://tests/core -a res://tests/client
```

Si la ruta de Godot tiene paréntesis (p. ej. `Program Files (x86)`), `runtest.cmd` falla al
parsearla; en ese caso se llama directamente lo mismo que hace el script (Git Bash):

```bash
"$GODOT" --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --headless --ignoreHeadlessMode -a res://tests/sim -a res://tests/core -a res://tests/client
```

Código de salida: 0 = todo pasa, 100 = fallos. Los reportes (JUnit `results.xml` y HTML) quedan
en `reports/` (ignorada por git). Los errores "remote port number" del inicio son esperados
(`--remote-debug tcp://127.0.0.1:0` evita que el depurador local se quede esperando).

Al salir aparece "5 resources still in use" con los scripts de `core/defs/`: son las referencias
cíclicas entre EntityDef, UnitDef y BuildingDef que pide ADR-007 (UnitDef.can_build, BuildingDef.trains).
No afecta a las pruebas.

## Dos instancias por ENet (T-005)

Con el anfitrión (o un servidor dedicado) en un proceso y el cliente de comprobación en otro:

```bash
# Proceso 1: anfitrión (jugador 1 local) que se cierra solo a los 30 s.
"$GODOT" --headless --path . res://main/match.tscn -- --mode=host --port=24790 --quit_after=30
# (o servidor dedicado: -- --server --port=24790 --quit_after=30)

# Proceso 2: se une, mueve sus unidades e intenta mover las de otro jugador.
"$GODOT" --headless --path . res://tests/net/enet_client_check.tscn -- --address=127.0.0.1 --port=24790
```

El proceso 2 imprime `CHECK OK: ...` y sale con 0 si: recibió WELCOME y snapshots, sus unidades
avanzaron al menos 10 m y el comando sobre una unidad ajena volvió como `COMMAND_REJECTED`
(`NOT_OWNER`) sin que esa unidad se moviera. Sin `--headless`, `main/match.tscn` muestra un texto
de estado; con un cliente dibuja las unidades (T-017).
