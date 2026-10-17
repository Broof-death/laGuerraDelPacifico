# Prueba de carga de la simulación y la red (ADR-006 punto 10)

```bash
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S1
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S2
godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S3
# Parámetros sueltos (pisan los del escenario):
godot --headless --path . res://tests/load/load_test.tscn -- --players=6 --units=500 --seconds=120 --seed=1 --deaths_per_sec=300
# Red: --loss=0.02 (pérdida en snapshots y acks), --ghosts=0 (sin clientes fantasma),
# --radius=200 (radio del círculo inicial, en m)
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
- Desde T-005 la simulación corre dentro de un `MatchServer` con un cliente fantasma por jugador
  (`MatchClient` sin interpolación) por `LocalTransport` con 2 % de pérdida en snapshots y acks. El
  reloj de la red es manual (50 ms por tick). El tiempo del tick incluye el armado de snapshots; la
  decodificación de los fantasmas se mide aparte (`ghost_decode_ms_per_tick`, los 6 juntos).
- Red: bytes por snapshot, paquete más grande, KB/s por jugador (media, media en los segundos de
  batalla, con >= 25 % de entidades con objetivo, y peor segundo), antigüedad máxima de una entidad
  en combate con cambios pendientes (ticks desde que la copia del cliente era exacta) y si el estado
  de cada fantasma coincide bit a bit con el que guardó el servidor.

## Umbrales (ADR-006)

| Escenario | Entidades | Umbral del tick | Red |
|---|---|---|---|
| S1 2 x 500 | 1000 | p95 <= 6 ms | snapshot <= 4 KB, paquete <= 1200 B, <= 40 KB/s |
| S2 6 x 500 | 3000 | p95 <= 20 ms y p99 <= 35 ms | además: media en batalla <= 25 KB/s, antigüedad en combate <= 300 ms |
| S3 6 x 750 | 4500 | p95 <= 35 ms | snapshot <= 4 KB, antigüedad en combate <= 500 ms |

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

### T-005: tick con snapshots y red (17-10-2026)

Mismo PC y binario. Semilla 1, 120 s simulados, 2 % de pérdida, 6 fantasmas (2 en S1).

| Escenario | tick p50 | tick p95 | tick p99 | tick máx | snapshots p95 | bytes/snapshot máx | paquete máx | KB/s batalla (media) | peor segundo | antigüedad combate p50 / p95 / máx | Cumple |
|---|---|---|---|---|---|---|---|---|---|---|---|
| S1 2 x 500 | 2,54 | 3,28 | 3,82 | 4,76 | 2,37 | 4068 | 1200 | 39,7 | 39,7 | 0 / 300 / 800 ms | Sí |
| S2 6 x 500 | 11,06 | 12,90 | 14,17 | 20,96 | 11,38 | 4076 | 1200 | **39,7** | 39,8 | **400 / 600 / 1100 ms** | Tick sí; red NO |
| S3 6 x 750 | 14,89 | 17,59 | 19,49 | 22,49 | 15,36 | 4079 | 1200 | 39,7 | 39,8 | **500 / 700 / 1800 ms** | Tick sí; antigüedad NO |
| S2 + 300 bajas/s | 9,10 | 10,64 | 11,92 | 14,81 | 9,30 | 4096 | 1200 | 39,8 | 40,0 | 200 / 400 / 1100 ms | Tick sí; red NO |
| S2 radio 1500 m (sin batalla en 120 s) | 6,31 | 7,38 | 8,54 | 12,13 | 5,59 | 2056 | 1200 | (sin batalla) 20,0 de media | 23,0 | — | Sí |

- El tope de 4 KB y los paquetes de 1200 B se cumplen siempre; por eso ningún segundo pasa de 40 KB/s.
  Los fantasmas quedaron coherentes con el servidor en todas las corridas, sin reenvíos completos.
- El armado de snapshots cuesta ~3 ms por cliente (mezcla 0,9, selección 0,4, escritura 1,0 y
  estado 0,6 ms con 3000 visibles) más ~1,8 ms por ciclo para cuantizar el mundo. Con 3 clientes por
  tick queda en ~11 ms de los 20 ms, dentro de la estimación de ADR-006 (5-8 ms) por arriba.
- Por qué S2 no cumple la media de 25 KB/s ni los 300 ms: en este escenario los 6 ejércitos están
  siempre a la vista de todos (3000 visibles, ADR-006 supone 1500-2000) y SIEMPRE en movimiento (no
  hay combate que los detenga). Cada registro en movimiento ocupa ~4 B (id 1 B, máscara 1 B, delta
  2 B), así que harían falta ~12 KB por snapshot; con el tope de 4 KB entran ~1000 de ~3000 cambios
  y cada unidad se actualiza cada ~3 snapshots. La media de 25 KB/s exige <= 2,5 KB por snapshot, es
  decir <= ~600 unidades en movimiento a la vista. Queda como pregunta para el arquitecto (ver T-005).
- La decodificación de los 6 fantasmas juntos cuesta ~14 ms por tick (~2,4 ms por cliente y
  snapshot), fuera del tiempo del servidor.
