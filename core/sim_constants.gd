class_name SimConstants
extends RefCounted
## Constantes compartidas entre servidor y cliente (ADR-006).
## No se instancia: se usa como espacio de nombres (SimConstants.TICK_RATE).

## Ticks de simulación por segundo (ritmo rápido: comandos, movimiento, daño).
const TICK_RATE: int = 20
## Duración de un tick en segundos.
const TICK_DT: float = 1.0 / TICK_RATE
## Máximo de ticks que se ejecutan en un mismo frame; el resto se descarta ("sim atrasada").
const MAX_TICKS_PER_FRAME: int = 3
## El ritmo lento (adquisición de objetivos, visibilidad) corre a TICK_RATE / SLOW_PHASES = 5 Hz,
## escalonado: cada tick procesa 1/SLOW_PHASES de las entidades.
const SLOW_PHASES: int = 4
## Snapshots cada este número de ticks (10 Hz). Los usa MatchServer (T-005).
const SNAPSHOT_EVERY_TICKS: int = 2

## Lado de la celda de la SpatialGrid en metros (alineada con los sectores de T-010).
const GRID_CELL_SIZE: float = 64.0
## Lado del mapa en metros mientras T-010 no fije los límites reales (escala 1:20, ~125 km).
const DEFAULT_MAP_SIZE: float = 125000.0

## Ids de entidad: 0 = ninguna; el servidor los asigna correlativos desde 1 y no los reutiliza.
const NO_ENTITY: int = 0
const MAX_ENTITY_ID: int = 0x7FFFFFFF
## player_id: 0 = neutral; jugadores 1..MAX_PLAYERS; el campo admite hasta MAX_PLAYER_ID.
const NEUTRAL_PLAYER: int = 0
const MAX_PLAYERS: int = 6
const MAX_PLAYER_ID: int = 15
## def_index viaja en 10 bits en los snapshots.
const MAX_DEF_INDEX: int = 1023

## Comandos (ADR-006 punto 3).
const MAX_IDS_PER_COMMAND: int = 512
## Un MOVE/ATTACK_MOVE con al menos este número de unidades crea un grupo de movimiento interno.
const MOVE_GROUP_MIN_UNITS: int = 8
## Límite de comandos por jugador y segundo (RATE_LIMIT).
const RATE_LIMIT_COMMANDS_PER_SEC: int = 30
## Límite de bytes de comandos por jugador y segundo (lo aplica el transporte en T-005).
const RATE_LIMIT_BYTES_PER_SEC: int = 8192

## Acción actual de una entidad (EntityStore.action, 4 bits en los snapshots).
enum Action {
	IDLE = 0,
	MOVE = 1,
}
