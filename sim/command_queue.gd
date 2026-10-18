class_name CommandQueue
extends RefCounted
## Cola de comandos del servidor (ADR-006 punto 3).
## - submit(): valida (O(n) en entity_ids) y aplica el límite de 30 comandos/s por jugador.
##   La ventana del límite es de 1 s de tiempo REAL (now_msec), no de ticks: en pausa (solo en el
##   modo de un jugador) se siguen aceptando órdenes al mismo ritmo y quedan en la cola hasta el
##   primer tick después de reanudar. Como la ventana se renueva, la cola en pausa crece como mucho
##   30 comandos por segundo de pausa; MAX_PENDING la acota (el resto se rechaza con RATE_LIMITED).
##   El player_id lo pone el servidor (lo deduce del peer), nunca viene en el comando.
## - Los comandos aceptados esperan al tick siguiente: Simulation.step() los vacía con take_pending().
## - Registro (tick, player_id, comando) de todo lo aplicado, para depurar.
## La IA bot usa la misma cola, sin atajos.

## Entrada del registro de comandos aplicados.
class LogEntry:
	var tick: int
	var player_id: int
	var command: Command

	func _init(p_tick: int, p_player_id: int, p_command: Command) -> void:
		tick = p_tick
		player_id = p_player_id
		command = p_command


## Tipos que la simulación sabe aplicar hoy. Se agregan al implementar cada mecánica.
## ATTACK es provisional (T-007): sin combate, mueve hacia la posición del objetivo.
const SUPPORTED_TYPES: Array[Command.Type] = [Command.Type.MOVE, Command.Type.ATTACK_MOVE, Command.Type.STOP, Command.Type.ATTACK]

## Máximo de comandos esperando el próximo tick (sumando todos los jugadores).
const MAX_PENDING: int = 4096
## Máximo de entradas del registro de depuración (las más viejas se descartan). 0 = sin límite.
## Con 6 jugadores al tope de 30 comandos/s son ~3 min de registro.
var max_log_entries: int = 32768
## Rechazos desde el último drain_rejections(): [player_id, seq, motivo] por entrada.
## MatchServer (T-005) los convierte en eventos reliable COMMAND_REJECTED.
var rejections: Array[PackedInt32Array] = []

var _pending_players: PackedInt32Array = PackedInt32Array()
var _pending_commands: Array[Command] = []
var _log: Array[LogEntry] = []
var _rate_window_start: PackedInt32Array = PackedInt32Array()
var _rate_count: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_rate_window_start.resize(SimConstants.MAX_PLAYER_ID + 1)
	_rate_window_start.fill(-SimConstants.RATE_LIMIT_WINDOW_MSEC)
	_rate_count.resize(SimConstants.MAX_PLAYER_ID + 1)


## Valida y encola. Devuelve Command.Reject.OK si se aceptó; si no, el motivo (y lo anota en
## `rejections`). `now_msec` es el reloj del límite de comandos (ver arriba). El comando se aplica
## en el próximo tick que se ejecute.
func submit(player_id: int, cmd: Command, store: EntityStore, bounds: Rect2, now_msec: int) -> Command.Reject:
	var reason: Command.Reject = _validate(player_id, cmd, store, bounds)
	if reason == Command.Reject.OK:
		reason = _consume_rate(player_id, now_msec)
	if reason == Command.Reject.OK and _pending_commands.size() >= MAX_PENDING:
		reason = Command.Reject.RATE_LIMITED
	if reason != Command.Reject.OK:
		var seq: int = cmd.seq if cmd != null else 0
		rejections.append(PackedInt32Array([player_id, seq, reason]))
		return reason
	_pending_players.append(player_id)
	_pending_commands.append(cmd)
	return Command.Reject.OK


func pending_count() -> int:
	return _pending_commands.size()


## Entrega los comandos pendientes en orden de llegada y vacía la cola.
## Devuelve [players: PackedInt32Array, commands: Array[Command]].
func take_pending() -> Array:
	var out: Array = [_pending_players, _pending_commands]
	_pending_players = PackedInt32Array()
	_pending_commands = []
	return out


func record(tick: int, player_id: int, cmd: Command) -> void:
	_log.append(LogEntry.new(tick, player_id, cmd))
	# Se recorta por tandas (un 25 % de margen) para no copiar el array en cada comando.
	if max_log_entries > 0 and _log.size() > max_log_entries + max_log_entries / 4:
		_log = _log.slice(_log.size() - max_log_entries)


## Registro de lo aplicado, del más viejo al más nuevo (como mucho max_log_entries entradas).
func get_log() -> Array[LogEntry]:
	if max_log_entries > 0 and _log.size() > max_log_entries:
		return _log.slice(_log.size() - max_log_entries)
	return _log


func drain_rejections() -> Array[PackedInt32Array]:
	var out := rejections
	rejections = []
	return out


func _validate(player_id: int, cmd: Command, store: EntityStore, bounds: Rect2) -> Command.Reject:
	if player_id < 1 or player_id > SimConstants.MAX_PLAYER_ID:
		return Command.Reject.INVALID_PLAYER
	if cmd == null or cmd.type < Command.Type.NONE or cmd.type > Command.Type.SET_RALLY or cmd.type == Command.Type.NONE:
		return Command.Reject.UNKNOWN_TYPE
	if not SUPPORTED_TYPES.has(cmd.type):
		return Command.Reject.UNSUPPORTED_TYPE
	var ids := cmd.entity_ids
	if ids.is_empty():
		return Command.Reject.NO_ENTITIES
	if ids.size() > SimConstants.MAX_IDS_PER_COMMAND:
		return Command.Reject.TOO_MANY_ENTITIES
	var last: int = SimConstants.NO_ENTITY
	var owners := store.owner
	for entity_id: int in ids:
		if entity_id <= last:
			return Command.Reject.UNSORTED_IDS
		last = entity_id
		var s: int = store.slot_of(entity_id)
		if s < 0:
			return Command.Reject.UNKNOWN_ENTITY
		if owners[s] != player_id:
			return Command.Reject.NOT_OWNER
	if cmd.type == Command.Type.MOVE or cmd.type == Command.Type.ATTACK_MOVE:
		var p: Vector2 = cmd.target_pos
		if not p.is_finite() or p.x < bounds.position.x or p.y < bounds.position.y \
				or p.x > bounds.end.x or p.y > bounds.end.y:
			return Command.Reject.TARGET_OUT_OF_BOUNDS
	if cmd.type == Command.Type.ATTACK and store.slot_of(cmd.target_id) < 0:
		return Command.Reject.UNKNOWN_ENTITY
	return Command.Reject.OK


## Ventana fija de un segundo (RATE_LIMIT_WINDOW_MSEC) por jugador.
func _consume_rate(player_id: int, now_msec: int) -> Command.Reject:
	if now_msec - _rate_window_start[player_id] >= SimConstants.RATE_LIMIT_WINDOW_MSEC:
		_rate_window_start[player_id] = now_msec
		_rate_count[player_id] = 0
	if _rate_count[player_id] >= SimConstants.RATE_LIMIT_COMMANDS_PER_SEC:
		return Command.Reject.RATE_LIMITED
	_rate_count[player_id] += 1
	return Command.Reject.OK
