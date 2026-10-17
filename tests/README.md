# Pruebas

- `tests/sim/`: pruebas unitarias de la simulación (gdUnit4 v6.2.2, en `addons/gdUnit4/`).
- `tests/load/`: prueba de carga headless de ADR-006 (no usa gdUnit4). Ver `tests/load/README.md`.

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
addons\gdUnit4\runtest.cmd --headless --ignoreHeadlessMode -a res://tests/sim
```

Si la ruta de Godot tiene paréntesis (p. ej. `Program Files (x86)`), `runtest.cmd` falla al
parsearla; en ese caso se llama directamente lo mismo que hace el script (Git Bash):

```bash
"$GODOT" --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --headless --ignoreHeadlessMode -a res://tests/sim
```

Código de salida: 0 = todo pasa, 100 = fallos. Los reportes (JUnit `results.xml` y HTML) quedan
en `reports/` (ignorada por git). Los errores "remote port number" del inicio son esperados
(`--remote-debug tcp://127.0.0.1:0` evita que el depurador local se quede esperando).

Al salir aparece "5 resources still in use" con los scripts de `core/defs/`: son las referencias
cíclicas entre EntityDef, UnitDef y BuildingDef que pide ADR-007 (UnitDef.can_build, BuildingDef.trains).
No afecta a las pruebas.
