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
  en combate desactualizada en el cliente, error del dead reckoning de cada fantasma frente a la
  posición real, y si el estado de cada fantasma coincide bit a bit con el que guardó el servidor.

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

### T-005, primera versión (sin dead reckoning): no cumplía la red en S2

Con delta de posición contra la base y sin velocidad, S2 daba tick p95 12,9 ms, snapshots siempre
llenos (4076 B), 39,7 KB/s de media en batalla y antigüedad en combate p50 400 / máx. 1100 ms:
los 3000 visibles se mueven sin parar y cada uno costaba ~4 B en CADA snapshot. Luis eligió
dead reckoning (Q-016).

### T-005 con dead reckoning (17-10-2026)

Mismo PC y binario. Semilla 1, 120 s simulados, 2 % de pérdida, 6 fantasmas (2 en S1). Umbral
del dead reckoning: 0,5 m. Las estadísticas por snapshot empiezan a los 3 s (después de la
sincronización inicial); los KB/s por segundo cuentan todo.

| Escenario | tick p50 | tick p95 | tick p99 | tick máx | snapshots p95 | bytes/snapshot p50 / p95 / máx | KB/s media en batalla | peor segundo | antigüedad combate p99 / máx | error DR p99 / máx | Cumple |
|---|---|---|---|---|---|---|---|---|---|---|---|
| S1 2 x 500 | 1,74 | 2,40 | 2,75 | 3,56 | 1,54 | 66 / 328 / 715 | 1,0 | 13,5 | 200 / 300 ms | 70 / 71 cm | Sí |
| S2 6 x 500 | 8,29 | 9,85 | 10,94 | 12,96 | 8,42 | 172 / 916 / 1961 | **3,3** | 39,5 (sincronización inicial) | **200 / 300 ms** | 90 / 120 cm | **Sí** |
| S3 6 x 750 | 13,47 | 19,12 | 20,21 | 21,75 | 16,71 | 263 / 1075 / 2029 | 4,4 | 39,7 (sincronización inicial) | 200 / 400 ms | 87 / 130 cm | Sí (500 ms) |
| S2 + 300 bajas/s | 9,90 | 13,43 | 14,17 | 16,67 | 11,79 | 575 / 1329 / 3332 | 7,6 | 39,5 | 200 / 500 ms | 92 / 123 cm | Red sí; antigüedad 500 ms (sin umbral propio) |
| S2 radio 1500 m (sin batalla en 120 s) | 5,32 | 8,61 | 8,91 | 10,55 | 6,20 | 42 / 141 / 1030 | (sin batalla) 0,6 de media | 6,8 | — | 57 / 57 cm | Sí |

- Antigüedad en combate: ticks desde que la copia del cliente estaba al día (error previsto dentro
  de 0,5 m y vida/acción iguales), medida en el servidor contra el último snapshot confirmado; es
  pesimista, porque con un ack perdido el cliente ya puede tener el dato. Los máximos de 400-500 ms
  coinciden con 3 snapshots seguidos sin confirmar por la pérdida simulada del 2 %.
- Error DR: una vez por segundo, para cada fantasma, la posición que predice su último estado
  completo frente a la posición real en el tick ACTUAL del servidor (incluye los 1-2 ticks que el
  cliente todavía no recibió). Fuera de 0,5 m + medio paso: 0,02 % de las comprobaciones.
- Los fantasmas quedaron idénticos bit a bit al estado que guardó el servidor, sin reenvíos completos.
- El peor segundo (~40 KB/s) es la sincronización inicial (todas las apariciones con el tope de 4 KB).
- Sincronización inicial (`initial_sync_ms`, desde el saludo hasta que todos los fantasmas conocen
  todo lo que ven): S2 1450 ms (umbral propio de T-005: 2000 ms), S3 2050 ms (umbral 2500 ms). La
  cota física con el tope de 4 KB es ~0,9 s para 3000 visibles y ~1,4 s para 4500 (~12,4 B por
  aparición), así que 1 s no es alcanzable sin subir el tope o achicar la aparición.
- Armado de snapshots: con dead reckoning la mezcla sigue recorriendo los 3000 visibles por cliente,
  pero se escriben muchos menos registros: ~8 ms por tick en S2 (antes ~11).

# Prueba de carga del render del cliente (T-017, ADR-006 punto 7, ADR-010 punto 5)

Necesita ventana (no `--headless`). Apaga la sincronización vertical y abre la ventana a 1920x1080.

```bash
godot --path . res://tests/load/render_load.tscn -- --units=2000
godot --path . res://tests/load/render_load.tscn -- --units=3000 --seconds=10
godot --path . res://tests/load/render_load.tscn -- --units=4000
# Partida local real (MatchServer + MatchClient + bots) en el mismo proceso:
godot --path . res://tests/load/render_load.tscn -- --units=2000 --mode=full --seconds=15
# Otros: --zoom=0.5 (zoom de la cámara RTS), --window=1920x1080
```

- `synthetic` (por defecto): un `SyntheticClientState` con las entidades de 6 jugadores (infantería,
  caballería, artillería, 1 edificio y 2 buques por jugador) en 18 regimientos que avanzan y
  retroceden. Mide solo el cliente: `UnitBatchRenderer` (recorte, LOD, pool de 256 vistas y
  MultiMesh) sobre el escenario provisional `client/world/battlefield.tscn`.
- `full`: la simulación y la red local de verdad; el cliente es el jugador 1 y ve lo que su visión
  permite.
- La cámara queda a zoom medio (0,5: 150 m del foco) sobre el centro y gira 8°/s. Se descartan los
  primeros 2 s.
- Salida: una línea `RENDER_RESULT {...}` y un JSON en `user://load/render_<unidades>_<modo>.json`:
  FPS medio, frame p50/p95/p99/máx, draw calls, primitivas, objetos, VRAM, tiempo del renderizador
  por lotes y del servidor (en `full`), visibles de media y reparto por nivel de detalle.
- Umbrales: <= 2000 unidades, >= 60 FPS de media y p99 <= 22 ms; <= 3000, >= 45 FPS; más de 3000
  sin umbral. Código de salida 0 si cumple.

## Resultados (17-10-2026, PC de Luis: Ryzen 9 7900X3D, RTX 3090, 1920x1080, Godot 4.7.2 GL Compatibility, build de depuración del editor)

| Unidades | Modo | Visibles (media) | FPS medio | Frame p50 / p99 / máx (ms) | Draw calls | Primitivas | Renderizador (ms, media / p99) |
|---|---|---|---|---|---|---|---|
| 2000 | synthetic | 1764 | 241 | 4,0 / 6,2 / 14,5 | 857 | 0,55 M | 2,1 / 3,0 |
| 3000 | synthetic | 2617 | 183 | 5,3 / 7,8 / 14,1 | 857 | 0,89 M | 3,0 / 4,1 |
| 4000 | synthetic | 3443 | 149 | 6,6 / 9,0 / 14,4 | 853 | 1,21 M | 3,9 / 5,0 |
| 2000 | full | 1456 | 279 | 3,3 / 7,5 / 37,5 | 585 | 0,32 M | 1,8 / 2,5 (servidor 0,6) |

Las 256 vistas individuales (cuerpo y sombra) son la mayor parte de las draw calls; los lotes son
22 MultiMesh. VRAM ~25 MB. En una corrida anterior con 4000 hubo un tirón aislado de 533 ms
(probablemente la compilación de un shader al aparecer un lote nuevo); no se repitió.
