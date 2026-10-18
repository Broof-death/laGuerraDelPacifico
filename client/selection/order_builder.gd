class_name OrderBuilder
extends RefCounted
## Arma los comandos de una orden del jugador (ADR-006 punto 3, T-007). Solo cliente.
## - Los ids se normalizan (ordenados, sin repetir) y se parten en bloques de como máximo
##   MAX_IDS_PER_COMMAND (512). Una orden se reparte en como mucho MAX_COMMANDS_PER_ORDER
##   comandos; los ids que no caben se recortan (con 500 unidades por jugador no pasa).
## - Cada bloque es un comando con el mismo destino, objetivo y `queued`. Los bloques se mueven
##   como grupos de movimiento distintos en el servidor.
## - RateLimiter: el cliente no envía más de RATE_LIMIT_COMMANDS_PER_SEC comandos por segundo
##   (el servidor rechazaría el resto con RATE_LIMITED). Una orden se envía entera o no se envía.

## Tope de comandos por orden (4 x 512 = 2048 ids).
const MAX_COMMANDS_PER_ORDER: int = 4


## Límite de comandos por ventana deslizante de 1 s, del lado del cliente.
class RateLimiter:
	var limit: int = SimConstants.RATE_LIMIT_COMMANDS_PER_SEC
	var window_msec: int = SimConstants.RATE_LIMIT_WINDOW_MSEC
	var _times := PackedInt64Array()

	## Reserva `n` envíos en `now_msec`. false (y no reserva nada) si superaría el límite.
	func try_consume(n: int, now_msec: int) -> bool:
		var keep := PackedInt64Array()
		for t: int in _times:
			if now_msec - t < window_msec:
				keep.append(t)
		_times = keep
		if _times.size() + n > limit:
			return false
		for i: int in n:
			_times.append(now_msec)
		return true


## Comandos para mover (o atacar-mover) a `pos` (x, z).
static func move(ids: PackedInt32Array, pos: Vector2, attack_move: bool, queued: bool) -> Array[Command]:
	var type: Command.Type = Command.Type.ATTACK_MOVE if attack_move else Command.Type.MOVE
	return build(type, ids, pos, SimConstants.NO_ENTITY, queued)


static func attack(ids: PackedInt32Array, target_id: int, queued: bool) -> Array[Command]:
	return build(Command.Type.ATTACK, ids, Vector2.ZERO, target_id, queued)


static func stop(ids: PackedInt32Array) -> Array[Command]:
	return build(Command.Type.STOP, ids, Vector2.ZERO, SimConstants.NO_ENTITY, false)


## Comandos de un tipo cualquiera, en bloques de 512 ids. seq queda en 0: lo pone MatchClient.
static func build(type: Command.Type, ids: PackedInt32Array, pos: Vector2, target_id: int, queued: bool) -> Array[Command]:
	var out: Array[Command] = []
	var norm := Command.normalize_ids(ids)
	var per: int = SimConstants.MAX_IDS_PER_COMMAND
	var total: int = mini(norm.size(), per * MAX_COMMANDS_PER_ORDER)
	for start: int in range(0, total, per):
		var cmd := Command.new()
		cmd.type = type
		cmd.entity_ids = norm.slice(start, mini(start + per, total))
		cmd.target_pos = pos
		cmd.target_id = target_id
		cmd.queued = queued
		out.append(cmd)
	return out


## Cuántos ids de `count` se quedan fuera de una orden por el tope.
static func trimmed_count(count: int) -> int:
	return maxi(0, count - SimConstants.MAX_IDS_PER_COMMAND * MAX_COMMANDS_PER_ORDER)
