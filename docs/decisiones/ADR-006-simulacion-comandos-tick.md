# ADR-006: Simulación con tick fijo y datos empaquetados, comandos, IDs, snapshots delta cuantizados con tope de bytes, vistas por lotes y servidor local, para 6 jugadores × 500 unidades (amplía ADR-001)

- Estado: Aceptada
- Área: arquitectura
- Fecha: 2026-10-17

## Contexto

ADR-001 (aceptado) fija un servidor con autoridad y define que un jugador = servidor local, pero no concreta cómo. Antes de T-004 (núcleo de simulación) y T-005 (red) hay que fijar: frecuencia del tick, formato de los comandos, IDs de entidades, cómo viaja el estado y cómo lo interpola y dibuja el cliente, y cómo corre el servidor en el modo de un jugador.

Restricciones: ADR-002 (mapa continuo, enviar a cada jugador solo lo que ve), ADR-004 (3D, Godot 4.7, GL Compatibility, Jolt), ADR-005 (lógica separada de lo visual), ADR-007 (Resources, EntityView, carpetas core/sim/client). Mapa a escala 1:20, unos 125 km (Q-001). Equipo de dos: preferir lo simple y medible a lo óptimo.

**Escala objetivo, con corrección de Q-005.** Q-005 quedó registrada como "batallas masivas (8+ jugadores o 1000+ unidades por jugador)" y la pizarra no permite cambiar la respuesta. Luis la corrigió después: como máximo 6 jugadores por partida (coherente con Q-002) y unas 500 unidades por jugador. **Esta corrección prevalece sobre la respuesta registrada en Q-005**; las batallas de 8 × 1000 quedan descartadas.

- Caso de referencia R = 6 jugadores × 500 unidades = 3000 entidades simultáneas (más unos 300 edificios).
- Un jugador puede llegar a ver entre 1500 y 2000 entidades en una batalla grande.
- Margen medido: 6 × 750 = 4500 entidades.
- La primera versión de este ADR (4 × 200 con snapshots completos, ~90 KB/s) no alcanza: con 2000 visibles daría ~600 KB/s por jugador. Por eso la cuantización, el delta con ack, el estado en arrays y el dibujo por lotes son obligatorios. Lo pensado para 8 × 1000 (agregación por formaciones en la red, intervalo adaptativo, prioridad por cámara, comandos por grupo) se simplifica o se pospone.

## Decisión

Este ADR **amplía** ADR-001 (no lo reemplaza) y complementa ADR-007 sin cambiarlo.

### 1. Tick fijo y dos ritmos

- La simulación avanza a **20 ticks/s** (`TICK_DT = 0.05 s`), con un acumulador propio en MatchServer (independiente de los FPS y del tick de física). Máximo 3 ticks por frame; si se acumulan más, se descartan y se registra "sim atrasada".
- Magnitudes de diseño en unidades por segundo, multiplicadas por el dt del sistema.
- La simulación NO usa Jolt ni nodos por unidad: es estado de datos puro en un objeto `Simulation` (RefCounted) que avanza sin escena (`Simulation.step()`). No toca el SceneTree, así que podría ir en un hilo.
- **Presupuesto:** con R (3000 entidades), tick completo **p95 ≤ 20 ms** en el PC de referencia (40 % de 50 ms).
- Ritmos:
  - 20 Hz: comandos, movimiento (con evitación local), cooldown y daño de disparos ya decididos, muertes, producción y construcción.
  - 5 Hz escalonado (cada tick procesa 1/4 de las entidades o un equipo): adquisición de objetivos y visibilidad/niebla.
  - IA bot a 2 Hz; victoria a 1 Hz.
  - Rutas: una por grupo de movimiento, cola de máximo 8 búsquedas por tick.
- Orden de cada tick: (a) vaciar la cola de comandos, (b) sistemas que tocan, (c) `tick += 1`, (d) cada 2 ticks, snapshots.
- Pausa y velocidad ×2 solo en un jugador. Azar: RandomNumberGenerator del servidor con semilla de partida (sin determinismo).

### 2. Estado en arrays empaquetados (SoA) y partición espacial

- No hay un objeto por entidad. El estado vive en `EntityStore` (`sim/entity_store.gd`) con arrays paralelos densos, un slot por entidad viva:
  - `PackedInt32Array`: id, def_index, owner, action, move_group, target_id, cell
  - `PackedFloat64Array`: pos_x, pos_z (metros; float64 por precisión en 125 km)
  - `PackedFloat32Array`: heading, vel_x, vel_z, hp, cooldown, progress
  - Se agregan arrays por mecánica. Borrado por swap-remove con `id_to_slot` (ids no reutilizados). Sistemas como funciones sobre rangos de slots (`sim/systems/*.gd`).
- Estadísticas fijas copiadas de GameData a tablas por def_index al iniciar.
- `SpatialGrid` uniforme (`sim/spatial_grid.gd`), celdas de 64 m alineadas con los sectores de T-010, reconstruida una vez por tick con counting sort. La usan combate, evitación, visibilidad e interés. Ninguna búsqueda O(n²).
- Visibilidad: rejilla por equipo de celdas de 32 m, guardada solo en bloques de 64×64 celdas con entidades (`PackedByteArray` por bloque).

### 3. Comandos

- Toda acción es un `Command` (`core/command.gd`): type (MOVE, STOP, ATTACK, ATTACK_MOVE, GATHER, BUILD, TRAIN, CANCEL, SET_RALLY; se agregan por mecánica), seq, entity_ids, target_pos (Vector2 x,z), target_id, def_id (StringName), queued (Shift), formation (enum).
- `entity_ids` ordenado y en deltas varint (~1,5 B por id; 500 unidades ≈ 750 B). Máximo 512 ids por comando; sin comandos por grupo en v1. Los grupos de control los guarda el cliente.
- Grupo de movimiento interno: MOVE/ATTACK_MOVE con 8+ unidades crea en el servidor un grupo con una ruta y una formación (`core/formation_layout.gd`); se disuelve al llegar o al entrar en combate. Solo de la simulación.
- `player_id` no viaja: el servidor lo deduce del peer. Validación O(n); si falla, evento reliable `COMMAND_REJECTED(seq, motivo)`. Límite de 30 comandos/s y 8 KB/s por jugador.
- Se aplica en el siguiente tick. Registro (tick, player_id, comando) para depurar. La IA bot usa la misma cola.
- Códec binario de `core/net/`, no `var_to_bytes`.

### 4. IDs de entidades

- int de 32 bits asignado por el servidor, correlativo desde 1, nunca reutilizado; 0 = ninguna. player_id 1..6 (0 = neutral; el campo admite hasta 15). Las definiciones viajan como def_index de GameData (ADR-007).

### 5. Snapshots: cuantizados, delta contra ack, con tope de bytes

- Interés (ADR-002): las celdas de la SpatialGrid que ve el equipo definen las candidatas.
- Cuantización (`SnapshotCodec` en `core/net/`, escritura por bits):
  - posición absoluta x, z: 20 bits cada una (≈ 0,12 m con 125 km);
  - posición delta: 2 × 8 bits, paso 0,25 m (±32 m); si no alcanza, absoluta;
  - rumbo 8 bits; vida 8 bits (fracción de max_hp); action 4 bits; progress 8 bits si action lo usa;
  - def_index (10 bits) y owner (4 bits) solo al aparecer;
  - id como diferencia varint y máscara de campos de 1 B.
- Delta contra el último snapshot confirmado: ack(tick) por unreliable. Anillo de 32 estados por cliente (≈ 0,8 MB por cliente). Entidad sin cambios = 0 B. Sin ack en 1 s, la base se vacía y el estado completo se reenvía repartido.
- Bajas y salidas de visión en lista explícita `REMOVED(ids, motivo)`, repetida hasta que un ack la cubra.
- **Tope de 4 KB por snapshot.** Si no cabe: REMOVED, datos privados, apariciones y luego el resto por antigüedad, con prioridad doble para entidades en combate. Sin prioridad por cámara.
- **Intervalo fijo de 10 Hz** (cada 2 ticks); sin intervalo adaptativo en v1.
- Eventos cosméticos de mejor esfuerzo, tope de 512 B por snapshot (agrupados por atacante y tick si se pasa).
- Cada entidad se cuantiza una vez por ciclo; los jugadores se reparten entre los 2 ticks del ciclo.
- Canales: comandos por RPC reliable (0); snapshots y acks unreliable_ordered (1), en paquetes ≤ 1200 B decodificables por separado; eventos importantes reliable (2).
- **Agregación por formaciones en la red: pospuesta.** Queda reservado un tipo de registro "grupo" en el códec, para agregarla solo si S2 o S3 muestran antigüedad excesiva o se pasan del tope.

**Presupuesto de ancho de banda** (estimación, se valida en las pruebas de carga):

- Registros: en movimiento ~5 B; con cambio de acción o vida ~6 B; aparición ~12 B; quieto 0 B.
- Batalla mediana (1000 visibles): ≈ 3,4 KB por snapshot, ~34 KB/s.
- Peor caso (2000 visibles, 60 % en movimiento): ~7,4 KB sin tope; con el tope de 4 KB cada entidad se actualiza cada 1,5–2 snapshots (5–7 Hz efectivos), antigüedad ≤ 300 ms cubierta extrapolando.
- Fuera de batalla: 5–15 KB/s.
- Por jugador: **tope 40 KB/s** de bajada (~44 KB/s con ENet, ≈ 350 kbit/s), media ≤ 20 KB/s. Subida del cliente < 2 KB/s.
- Anfitrión con 6 jugadores (5 remotos): pico ≈ 220 KB/s ≈ **1,8 Mbit/s de subida**, media ≈ 0,8 Mbit/s. Servidor dedicado: ≈ 2,1 Mbit/s.

### 6. Interpolación en el cliente

- Estado del cliente en arrays (MatchClient guarda los dos últimos estados por slot y un mapa id → slot).
- Retraso de dibujo fijo de 200 ms. Lerp de posición, lerp_angle de rumbo. Entidades aplazadas por el tope se extrapolan hasta 300 ms y luego se quedan quietas. La altura la pone el cliente.
- Sin predicción: respuesta cosmética inmediata, limpiada cuando last_seq confirma el comando.

### 7. Vistas con miles de unidades

- `EntityView` (ADR-007) para edificios, buques y unidades cercanas, con un pool de máximo 256 vistas.
- El resto por lotes en `client/views/batch/unit_batch_renderer.gd`: un MultiMeshInstance3D por (def_index, facción), color por instancia, buffer escrito una vez por frame. Malla de view_scene_path o placeholder_shape/size; una malla LOD en EntityDef requeriría un ADR que enmiende ADR-007.
- LOD: < 150 m vista individual o malla completa; 150 m–1,5 km malla simplificada; > 1,5 km impostor. Sin Label3D ni barra de vida por unidad salvo seleccionadas o cercanas.
- Selección por proyección a pantalla, sin colisionadores por unidad; Jolt solo para el raycast al suelo.
- **Meta del cliente:** ≥ 60 FPS de media y frame p99 ≤ 22 ms con 2000 unidades visibles; ≥ 45 FPS con 3000, en GL Compatibility.

### 8. Qué vive dónde

- Solo servidor (`sim/`): Simulation, EntityStore, SpatialGrid, grupos de movimiento, sistemas, cola y validación de comandos, rutas, visibilidad, victoria, IA bot, RNG, registro.
- Solo cliente (`client/`): estado interpolado, vistas, renderizador por lotes, terreno, cámara, selección, HUD, entrada → Command, sonido, efectos, niebla.
- Compartido (`core/`): Command, SnapshotCodec, bit_writer/bit_reader, formation_layout, definiciones, constantes. Regla de dependencias de ADR-007 sin cambios.

### 9. Transporte y modos

- Interfaz `Transport` con `LocalTransport` (mismo proceso, códec binario, latencia/pérdida/ancho de banda simulables) y `ENetTransport` (ENetMultiplayerPeer + NetBridge).
- `main/match.tscn` lee MatchConfig y arranca en: UN JUGADOR, ANFITRIÓN, UNIRSE o DEDICADO (`--server`). ANFITRIÓN es el modo multijugador normal; DEDICADO es opcional.
- MatchConfig llega por el único autoload, `Session`. La simulación no usa autoloads.

### 10. Pruebas: unitarias y de carga desde el inicio

- Unitarias headless de la simulación (gdUnit4, T-003). Del códec: ida y vuelta, deltas con acks perdidos, error de cuantización ≤ medio paso.
- Prueba de carga headless (`tests/load/load_test.tscn` + `.gd`): parámetros P jugadores, N unidades, duración y semilla; bots con ATTACK_MOVE cruzados; cliente fantasma por jugador con 2 % de pérdida. Salida JSON con tiempos por tick y por sistema, bytes por snapshot, KB/s por jugador, antigüedad máxima y memoria.
- Escenarios (especificaciones del PC de referencia en `tests/load/README.md`):
  - **S1** 2 × 500: tick p95 ≤ 6 ms.
  - **S2** 6 × 500 (R): tick p95 ≤ 20 ms, p99 ≤ 35 ms; snapshot ≤ 4 KB siempre; media ≤ 25 KB/s por jugador en batalla; antigüedad en combate ≤ 300 ms.
  - **S3** 6 × 750 (margen): tick p95 ≤ 35 ms; tope de 4 KB respetado; antigüedad en combate ≤ 500 ms.
  - Cliente: `tests/load/render_load.tscn` con 2000 y 3000 unidades, umbrales del punto 7.
- S1 y S2 se ejecutan antes de fusionar cambios en `sim/` o `core/net/`, y el resultado se anota en la tarea.

### Diagrama de flujo

```
  CLIENTE (client/)                          SERVIDOR (sim/)
  -----------------------------------        -------------------------------------------
  Ratón/teclado -> selección por proyección
     |
     v
  Command{type, seq, entity_ids<=512 (varint)}
     |  (marcador y sonido locales)
  Transport ---reliable------------------->  cola (player_id <- peer, límite 30/s)
  ack(tick) ---unreliable----------------->       |  20 Hz
                                              EntityStore SoA + SpatialGrid (64 m)
                                              20 Hz: movimiento, daño, producción
                                              5 Hz escalonado: objetivos, visión
                                                  |
                                                  v  cada 2 ticks (10 Hz fijo)
                                              cuantizar 1 vez -> por jugador: interés,
                                              delta vs último ack, tope 4 KB
  buffer SoA <----unreliable (<=1200 B)----- SnapshotCodec
     |
     v
  interpolación (200 ms)
     |
     v
  pool de EntityView (<=256 cercanas) + MultiMesh por (def, facción) + impostores lejanos

  Modo de un jugador: igual, con LocalTransport en el mismo proceso.
```

## Alternativas descartadas

- **MultiplayerSynchronizer/MultiplayerSpawner:** sincronizan nodo por nodo; no sirven con 3000 entidades y filtrado propio. (Sí se usan las RPC de alto nivel.)
- **Lockstep determinista:** descartado por ADR-001; los snapshots alcanzan.
- **Snapshots completos sin delta ni cuantización** (primera versión): ~600 KB/s por jugador.
- **Agregación por formaciones en la red en v1:** exige que formation_layout coincida en ambos lados y manejar entradas y salidas de miembros; a 6 × 500 el tope de 4 KB alcanza. Pospuesta, con registro reservado.
- **Intervalo adaptativo y prioridad por cámara:** complejidad innecesaria a esta escala. Pospuestos.
- **Comandos sobre ids de grupo del servidor:** innecesarios con 500 unidades. Pospuestos.
- **Un RefCounted por entidad (SimEntity):** mucho más caro que PackedArrays en GDScript. Se usa SoA.
- **ECS genérico:** abstracción especulativa.
- **Un nodo EntityView por unidad para todo:** demasiados nodos para GL Compatibility.
- **Todos los sistemas a 20 Hz:** objetivos y visibilidad no caben en 20 ms en GDScript.
- **Simular con nodos y Jolt por unidad.**
- **Predicción con reconciliación en el cliente:** se usa respuesta cosmética.
- **ENet en 127.0.0.1 para un jugador:** se usa LocalTransport.
- **Abierta, no se decide aquí:** mover SnapshotCodec, SpatialGrid o adquisición de objetivos a GDExtension/C++ o a hilos. EntityStore y los sistemas se escriben para poder reemplazarse uno a uno sin cambiar interfaces.

## Consecuencias

- **T-004** implementa Simulation, EntityStore (SoA), SpatialGrid, grupos de movimiento, la cola de Command y la prueba de carga S1/S2. **T-005** implementa Transport (Local y ENet), NetBridge, SnapshotCodec (cuantización, delta contra ack, tope de 4 KB), MatchServer, MatchClient y el arranque en `main/match.tscn`.
- Aparece el autoload `Session` (MatchConfig). Ningún otro autoload sin un ADR.
- Toda mecánica nueva = tipo de Command + arrays en EntityStore + sistema en `sim/systems/` (20 o 5 Hz) + campo cuantizado en el códec si el cliente lo necesita + medición en S2.
- Archivos nuevos dentro de carpetas de ADR-007: `sim/entity_store.gd`, `sim/spatial_grid.gd`, `core/formation_layout.gd`, `core/net/bit_writer.gd` y `bit_reader.gd`, `client/views/batch/`, `tests/load/`. Ninguna carpeta de primer nivel nueva.
- Latencia percibida: ~200 ms + ping, compensada con respuesta cosmética.
- La cuantización depende del tamaño del mapa: T-010 fija los límites y alinea los sectores con la celda de 64 m.
- Visibilidad por equipo y por bloques (T-014); selección sin colisionadores (T-007); una ruta por grupo de movimiento (T-018).
- Repeticiones exactas no garantizadas con el registro de comandos; si se necesitan, se graban snapshots.
- **Riesgo GDScript (moderado):** estimación por tick con R ≈ 17–24 ms frente a la meta de 20 ms (movimiento ≈ 6 ms, objetivos ≈ 4–6 ms, visibilidad ≈ 1–2 ms, snapshots ≈ 5–8 ms, resto ≈ 1–2 ms). Probablemente alcanza con código cuidado (bucles sobre PackedArrays, sin Dictionary ni objetos en los bucles calientes), con poco margen. Si no, el primer candidato para GDExtension/C++ es el SnapshotCodec y luego la adquisición de objetivos; se decidirá con mediciones en un ADR propio.
- **Riesgo de subida del anfitrión (bajo):** pico ~1,8 Mbit/s, media ~0,8 Mbit/s; justo en ADSL o redes móviles. LocalTransport puede limitar el ancho de banda para probar con 1 Mbit/s.
- **Riesgo de CPU compartida:** si el anfitrión no da abasto, la Simulation puede ir en un hilo.
- **Riesgo de GL Compatibility:** validar pronto 60 FPS con 2000 unidades en `render_load.tscn` (T-017) antes de invertir en arte.
- Subir la escala (8 jugadores o 1000+ unidades) requiere un ADR que reemplace a este y reactive lo pospuesto.
