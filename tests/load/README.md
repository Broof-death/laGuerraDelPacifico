# Prueba de carga de la simulación (ADR-006 punto 10)

```bash
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S1
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S2
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S3
# Parámetros sueltos (pisan los del escenario):
godot --headless --path . res://tests/load/load_test.tscn -- --players=6 --units=500 --seconds=120 --seed=1 --deaths_per_sec=300
```

- Cada jugador empieza con N unidades en bloque, sobre un círculo de 200 m alrededor del centro del
  mapa. Los bots (2 Hz, por la cola de comandos normal) hacen ATTACK_MOVE de todo su ejército al lado
  opuesto (en partes de 512 ids) y, en cada decisión, un MOVE de 16 unidades. Los ejércitos se cruzan
  en el centro: todas las unidades llegan a tener un enemigo en visión.
- `--deaths_per_sec` simula bajas mientras no exista el combate: borra entidades al azar y las repone
  en la base (invalida objetivos y fuerza a readquirir). Su costo queda fuera del tiempo por tick.
- Los ticks corren tan rápido como se puede (no en tiempo real). Se descartan los primeros 20.
- Salida: una línea `LOAD_RESULT {...}` en la consola y un JSON en `user://load/`. Código de salida
  0 si cumple el umbral del escenario y 1 si no.
- Todavía NO mide (llega con T-005): bytes por snapshot, KB/s por jugador, antigüedad de las
  entidades y el cliente fantasma con 2 % de pérdida.

## Umbrales (ADR-006)

| Escenario | Entidades | Umbral del tick |
|---|---|---|
| S1 2 x 500 | 1000 | p95 <= 6 ms |
| S2 6 x 500 | 3000 | p95 <= 20 ms y p99 <= 35 ms |
| S3 6 x 750 | 4500 | p95 <= 35 ms |

## PC de referencia

Primera medición (T-004, 17-10-2026), en el PC de Luis:

- CPU: AMD Ryzen 9 7900X3D (12 núcleos, 24 hilos), 63 GB de RAM, Windows 11 Pro.
- Godot 4.7.2-stable (Steam), binario del editor (`godot.windows.opt.tools.64.exe`, build de depuración
  de GDScript), `--headless`.

## Resultados

T-004, semilla 1, 120 s simulados (2380 ticks medidos). Tiempos en ms.

| Escenario | tick p50 | tick p95 | tick p99 | tick máx | movimiento p95 | rejilla p95 | adquisición p95 | Cumple |
|---|---|---|---|---|---|---|---|---|
| S1 2 x 500 | 0,61 | 0,99 | 1,13 | 1,57 | 0,28 | 0,18 | 0,58 | Sí (6) |
| S2 6 x 500 | 1,34 | 1,67 | 2,01 | 2,42 | 0,92 | 0,63 | 0,24 | Sí (20 / 35) |
| S3 6 x 750 | 2,00 | 2,46 | 3,03 | 3,96 | 1,39 | 0,92 | 0,31 | Sí (35) |
| S2 + 300 bajas/s | 1,11 | 1,55 | 1,83 | 2,34 | 0,51 | 0,72 | 0,54 | Sí |
| S2 + 1500 bajas/s | 1,39 | 1,95 | 2,36 | 3,50 | 0,44 | 0,65 | 0,88 | Sí |

Qué incluye el tick hoy: comandos, movimiento lineal con grupos de movimiento, reconstrucción de la
SpatialGrid y adquisición de objetivos a 5 Hz escalonada. Todavía faltan evitación local, rutas,
daño, producción, visibilidad (T-014) y los snapshots (T-005), que ADR-006 estima en 5-8 ms.
