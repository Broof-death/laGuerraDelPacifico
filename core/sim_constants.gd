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
## Lado del mapa en metros (ADR-009: 131 072 m centrados en el origen; ver MapGrid).
const DEFAULT_MAP_SIZE: float = MapGrid.MAP_SIZE

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
## Régimen de marcha (T-018, Q-010, ADR-012): una orden MOVE (no ATTACK_MOVE ni ATTACK) cuyo
## destino está al menos a esta distancia (m) del centro de las unidades admite la marcha.
const MARCH_MIN_ORDER_DIST: float = 200.0
## Un enemigo a menos de esta distancia (m) de una unidad de la orden pone la ruta en alerta:
## velocidad táctica durante MARCH_ALERT_TICKS (se renueva mientras siga cerca).
const MARCH_ENEMY_RADIUS: float = 150.0
const MARCH_ALERT_TICKS: int = 20
## Órdenes encoladas con Shift: máximo por unidad (las que pasen se descartan).
const MAX_QUEUED_ORDERS: int = 16
## Una orden encolada arranca cuando todas sus unidades la tienen como siguiente y están libres,
## o cuando pasaron estos ticks desde que la primera quedó libre (reagrupar en el punto de paso).
const QUEUE_REGROUP_TICKS: int = 40
## Límite de comandos por jugador y segundo (RATE_LIMIT).
const RATE_LIMIT_COMMANDS_PER_SEC: int = 30
## Límite de bytes de comandos por jugador y segundo (lo aplica MatchServer al recibir).
const RATE_LIMIT_BYTES_PER_SEC: int = 8192
## Ventana de los límites de comandos, en milisegundos de tiempo real (sigue corriendo en pausa).
const RATE_LIMIT_WINDOW_MSEC: int = 1000

## Acción actual de una entidad (EntityStore.action, 4 bits en los snapshots).
enum Action {
	IDLE = 0,
	MOVE = 1,
}
