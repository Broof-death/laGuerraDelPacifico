# ADR-007: Datos de juego como Resources (UnitDef, BuildingDef, FactionDef, ResourceDef), separación lógica/visual y estructura de carpetas

- Estado: Aceptada (enmendada el 2026-10-17 para alinearla con ADR-006)
- Área: arquitectura
- Fecha: 2026-10-17

## Contexto

ADR-003 exige que las facciones (Chile, Perú y Bolivia) sean datos y no código. ADR-005 exige que cada unidad o edificio tenga una escena visual intercambiable, separada de su lógica. ADR-006 (amplía ADR-001) separa `sim/` (servidor), `client/` y `core/` (compartido), envía las definiciones como índice de catálogo y los comandos con def_id.

Hoy el repo tiene todo en la raíz: `menu.tscn` + `menu.gd` (class Menu, escena principal, botón Comenzar → `res://node_3d.tscn`), `node_3d.tscn` (raíz "Node3D" con `procedural_floor.gd`), `procedural_floor.gd` (class ProceduralFloor: suelo infinito por chunks que sigue a la cámara, con colisión y `_decorate_chunk` con semilla `hash(key)`), `openxr_action_map.tres` y `[xr] shaders/enabled=true` de la plantilla. El código existente usa identificadores en inglés y comentarios en español.

## Decisión

### 1. Recursos

Scripts en `core/defs/`, con `class_name` y `extends Resource`. Las definiciones son de **solo lectura** durante la partida: el estado cambiante (vida, posición, bonificaciones aplicadas) vive en el `EntityStore` de la simulación (`sim/entity_store.gd`, PackedArrays paralelos, un slot por entidad; ADR-006). Nunca se modifica un .tres en tiempo de ejecución. No hay un objeto por entidad.

- **EntityDef** (base de UnitDef y BuildingDef):
  - `id: StringName` (igual al nombre del archivo, único en todo el juego)
  - `display_name: String`, `description: String` (multilínea)
  - `max_hp: int`, `armor: int`, `vision_range: float` (m)
  - `cost: Dictionary[ResourceDef, int]`, `build_time: float` (s)
  - `weapons: Array[WeaponDef]`
  - Solo visual (el servidor no lo usa): `view_scene_path: String` (`@export_file("*.tscn")`; vacío = provisional), `placeholder_shape: enum {BOX, CYLINDER, CAPSULE, HULL}`, `placeholder_size: Vector3`, `placeholder_label: String` (p. ej. "INF", "BLIND."), `icon: Texture2D`
- **UnitDef** extends EntityDef: `domain: enum {LAND, SEA}`, `category: enum {WORKER, INFANTRY, CAVALRY, ARTILLERY, SHIP}`, `speed` (m/s), `turn_rate` (grados/s), `radius` (m), `pop_cost: int`, `can_gather: Array[ResourceDef]`, `can_build: Array[BuildingDef]`.
- **BuildingDef** extends EntityDef: `footprint: Vector2i` (celdas), `placement: enum {LAND, COAST}`, `trains: Array[UnitDef]`, `pop_provided: int`, `drop_off: Array[ResourceDef]`.
- **WeaponDef** (subrecurso, puede ir incrustado): `id`, `damage: int`, `range: float`, `min_range: float`, `cooldown: float` (s), `target_domains` (array de domain). Un buque puede tener varias armas.
- **ResourceDef** (recurso económico): `id`, `display_name`, `icon: Texture2D`, `ui_color: Color`. Cuáles son (víveres, salitre, municiones, carbón...) lo decide el game-designer; aquí solo se fija la forma.
- **FactionDef**: `id`, `display_name`, `color: Color` (para lo provisional, ADR-005), `flag: Texture2D`, `units: Array[UnitDef]`, `buildings: Array[BuildingDef]`, `start_resources: Dictionary[ResourceDef, int]`, `start_units: Array[UnitDef]`, `start_building: BuildingDef`. Las bonificaciones de facción se agregarán como campos cuando el GDD las defina.
- **GameData** (catálogo único, `data/game_data.tres`): `factions`, `units`, `buildings`, `resources` (Arrays tipados). Es el **único** punto de entrada a los datos. Al cargarse construye los índices id → def y def → índice (en el orden de los arrays, igual en servidor y cliente: ADR-006 manda def_index en los snapshots y copia las estadísticas fijas a tablas por def_index) y valida: ids únicos, todo lo que referencia una facción está en el catálogo, costos no negativos. Si la validación falla, la partida no arranca y se muestra un error claro.

Agregar una unidad = crear un .tres en `data/units/`, registrarlo en `game_data.tres` y en la FactionDef que lo use. Sin código.

### 2. Separación lógica / visual (ADR-005)

- La simulación lee solo los campos de lógica. `view_scene_path` es una ruta (no PackedScene) para que cargar GameData no arrastre modelos y texturas: el servidor dedicado no los carga y el cliente los carga bajo demanda (con caché).
- `client/views/entity_view.gd` (`class EntityView extends Node3D`) es la base de toda vista individual. Contrato: `setup(def: EntityDef, faction: FactionDef)`, `apply_state(action: int, hp_ratio: float, progress: float)`. La posición y el rumbo los pone MatchClient al interpolar. Una vista nunca emite comandos ni toca la simulación. Según ADR-006, las vistas individuales se usan para edificios, buques y unidades cercanas (pool limitado); el resto se dibuja por lotes en `client/views/batch/` con la misma malla.
- `client/views/placeholder_view.tscn` construye la forma provisional (forma y tamaño, color de facción, Label3D con `placeholder_label`). Se usa cuando `view_scene_path` está vacío o no carga.
- Arte final = escena nueva que hereda EntityView + rellenar `view_scene_path`. No se tocan datos de lógica ni `sim/`.

### 3. Estructura de carpetas

```
res://
  project.godot, icon.svg
  core/                 código compartido servidor/cliente, sin nodos visuales
    defs/               entity_def.gd, unit_def.gd, building_def.gd, weapon_def.gd,
                        resource_def.gd, faction_def.gd, game_data.gd
    net/                transport.gd, local_transport.gd, enet_transport.gd, net_bridge.gd,
                        snapshot_codec.gd, bit_writer.gd, bit_reader.gd
    command.gd, formation_layout.gd, match_config.gd
  sim/                  solo servidor (ADR-006): simulation.gd, entity_store.gd (SoA),
                        spatial_grid.gd, match_server.gd, systems/, ai/
  client/               solo presentación
    match_client.gd
    camera/             rts_camera.tscn/.gd (T-006)
    world/              procedural_floor.gd, terreno visible, agua
    views/              entity_view.gd, placeholder_view.tscn/.gd, units/, buildings/
      batch/            unit_batch_renderer.gd (MultiMesh por tipo y facción, impostores)
    ui/menu/            menu.tscn, menu.gd
    ui/hud/
  main/                 match.tscn/.gd (arma servidor/cliente según MatchConfig),
                        session.gd (autoload Session)
  data/                 contenido de diseño (.tres), sin scripts
    game_data.tres
    factions/           chile.tres, peru.tres, bolivia.tres
    units/<faccion>/    p. ej. units/chile/infanteria_linea_chile.tres; units/comun/
    buildings/<faccion>/
    resources/          viveres.tres...
  assets/               models/, textures/, audio/, fonts/, ui/
  tests/                framework según T-003; sim/ (headless), load/ (carga, ADR-006),
                        sandbox/ (pruebas manuales)
  docs/, tools/         fuera del juego (con .gdignore)
```

**Regla de dependencias:** `sim/` y `core/` no importan nada de `client/` ni de `main/`. `client/` puede leer `core/` pero no `sim/` (habla con el servidor solo mediante Transport).

### 4. Convenciones de nombres

- Archivos y carpetas en snake_case, sin tildes ni ñ (ñ → n). Escena y script principal con el mismo nombre en la misma carpeta.
- Código en inglés: `class_name` y nodos en PascalCase; funciones, variables y señales en snake_case (señales en pasado: `entity_died`, `command_rejected`); constantes y enums en UPPER_SNAKE_CASE; privados con prefijo `_`. Tipado estático siempre que se pueda.
- Comentarios, documentación (`##`), textos de interfaz y contenido en español.
- Ids de datos: snake_case en español, igual al nombre del archivo, únicos; con sufijo de facción si es propia (`infanteria_linea_chile`, `blindado_huascar`).
- Mover o renombrar archivos **siempre** desde el panel FileSystem del editor, para que se actualicen referencias y `.uid`.

### 5. Integración de lo existente (tarea aparte de dev-godot, en el editor)

- `menu.tscn` / `menu.gd` → `client/ui/menu/`. Sigue siendo `run/main_scene`. `start_scene` pasará a `res://main/match.tscn` cuando exista. El menú agrega los modos de ADR-006 (Un jugador, Anfitrión, Unirse) y llena `Session.config`.
- `procedural_floor.gd` → `client/world/procedural_floor.gd`. Solo cliente: su colisión sirve para raycasts de selección y órdenes, nunca para la lógica. `_decorate_chunk` solo genera decoración cosmética; el terreno que afecte al juego vendrá de datos que lee la simulación.
- `node_3d.tscn` → `tests/sandbox/floor_sandbox.tscn`, con la raíz renombrada "ProceduralFloor". `main/match.tscn` la reemplaza como destino de Comenzar.
- Limpieza: borrar `openxr_action_map.tres` y desactivar `[xr] shaders/enabled` (el juego no usa XR).

## Alternativas descartadas

- **Facciones o unidades como scripts o subclases** (`ChileInfantry.gd`): contradice ADR-003 y obliga a programar para balancear.
- **JSON/CSV:** sin edición en el Inspector, sin referencias tipadas y con parser propio. Si el balance se hace en planilla, se puede agregar una importación a .tres.
- **Descubrir los .tres recorriendo carpetas:** el orden de los índices sería implícito (ADR-006 lo necesita estable) y complica las exportaciones. Se usa catálogo explícito.
- **view_scene como PackedScene exportada:** cargar GameData arrastraría todo el arte, también en el servidor dedicado. Se usa una ruta.
- **Organizar por tipo de archivo** (scenes/, scripts/, resources/): separa escena y script y no expresa el límite servidor/cliente. Se organiza por responsabilidad.
- **Una sola clase para unidades y edificios:** los edificios no se mueven y las unidades no entrenan. La base EntityDef evita duplicar campos.

## Consecuencias

- T-004 crea `core/defs/` y un GameData mínimo de prueba (1 facción, 1 unidad, 1 recurso). El contenido histórico real lo cargan game-designer e historiador como .tres, sin código.
- Hace falta una tarea de dev-godot para reubicar menu/procedural_floor/node_3d y quitar XR (pendiente de crear por el orquestador).
- Cambiar el orden de los arrays de GameData rompe la compatibilidad en red entre versiones distintas. Servidor y cliente deben tener la misma versión (hash de GameData al conectarse, en T-005).
- Con los Dictionary tipados (Godot 4.4+) los costos se editan cómodamente en el Inspector; el proyecto está en 4.7.
- Bonificaciones de facción, recursos económicos concretos y stats quedan pendientes del GDD. Este ADR solo fija la forma.
- Todo el equipo y ambos Claude siguen estas carpetas y nombres. Una carpeta de primer nivel nueva requiere un ADR.

**Enmienda (2026-10-17):** alineada con ADR-006 (escala 6 × 500). El estado cambiante vive en `EntityStore` (no en `SimEntity`) y el árbol de carpetas incluye `entity_store.gd`, `spatial_grid.gd`, `client/views/batch/`, `bit_writer.gd`/`bit_reader.gd`, `formation_layout.gd` y `tests/load/`. No cambia los recursos, la separación lógica/visual ni las convenciones.
