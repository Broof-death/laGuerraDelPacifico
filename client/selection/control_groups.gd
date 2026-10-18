class_name ControlGroups
extends RefCounted
## Grupos de control (Ctrl + 1..9) guardados en el cliente como listas de ids (ADR-006 punto 3:
## sin ids de grupo en el servidor). Solo cliente.
## - assign(n, ids): guarda una copia ordenada de los ids (vacío = borra el grupo).
## - members(n, state): los ids del grupo que siguen en el estado del cliente; quita los que ya
##   no están (muertos).
## - register_recall(n, now_msec): true si es el segundo toque seguido del mismo número dentro de
##   DOUBLE_TAP_MSEC (doble toque = centrar la cámara en el grupo).

const FIRST: int = 1
const LAST: int = 9
const DOUBLE_TAP_MSEC: int = 350

var _groups: Array[PackedInt32Array] = []
var _last_recall_group: int = -1
var _last_recall_msec: int = -1000000


func _init() -> void:
	_groups.resize(LAST + 1)
	for i: int in LAST + 1:
		_groups[i] = PackedInt32Array()


static func is_valid(n: int) -> bool:
	return n >= FIRST and n <= LAST


func assign(n: int, ids: PackedInt32Array) -> void:
	if not is_valid(n):
		return
	_groups[n] = Command.normalize_ids(ids)
	_last_recall_group = -1


func get_ids(n: int) -> PackedInt32Array:
	return _groups[n] if is_valid(n) else PackedInt32Array()


## Ids del grupo que siguen vivos según `state` (y limpia los demás del grupo).
func members(n: int, state: ClientState) -> PackedInt32Array:
	if not is_valid(n):
		return PackedInt32Array()
	var out := PackedInt32Array()
	for id: int in _groups[n]:
		if state.slot_of(id) >= 0:
			out.append(id)
	if out.size() != _groups[n].size():
		_groups[n] = out
	return out


## Registra un toque del número `n`. Devuelve true si es un doble toque.
func register_recall(n: int, now_msec: int) -> bool:
	var double: bool = n == _last_recall_group and now_msec - _last_recall_msec <= DOUBLE_TAP_MSEC
	_last_recall_group = -1 if double else n
	_last_recall_msec = now_msec
	return double


## Centro (x, z) de las posiciones dibujadas de `ids` en `state`, o null si ninguno está.
static func centroid(ids: PackedInt32Array, state: ClientState) -> Variant:
	var sum := Vector2.ZERO
	var n: int = 0
	for id: int in ids:
		var s: int = state.slot_of(id)
		if s < 0:
			continue
		sum += Vector2(state.render_x[s], state.render_z[s])
		n += 1
	return sum / n if n > 0 else null
