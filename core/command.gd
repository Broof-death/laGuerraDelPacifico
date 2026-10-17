class_name Command
extends RefCounted
## Orden de un jugador (ADR-006 punto 3). La crea el cliente (o la IA bot) y la valida el servidor.
## player_id NO viaja en el comando: el servidor lo deduce del peer y lo pasa aparte al encolarlo.
## La serialización completa la hace el códec binario de core/net/ (T-005); aquí está la
## codificación de entity_ids (ordenados, en deltas varint) que ese códec reutiliza.

## Tipos de comando. Se agregan al implementar cada mecánica; el orden es parte del protocolo.
enum Type {
	NONE = 0,
	MOVE = 1,
	STOP = 2,
	ATTACK = 3,
	ATTACK_MOVE = 4,
	GATHER = 5,
	BUILD = 6,
	TRAIN = 7,
	CANCEL = 8,
	SET_RALLY = 9,
}

## Motivo de rechazo (evento COMMAND_REJECTED(seq, motivo)). OK = aceptado.
enum Reject {
	OK = 0,
	INVALID_PLAYER = 1,
	UNKNOWN_TYPE = 2,
	UNSUPPORTED_TYPE = 3,
	NO_ENTITIES = 4,
	TOO_MANY_ENTITIES = 5,
	UNSORTED_IDS = 6,
	UNKNOWN_ENTITY = 7,
	NOT_OWNER = 8,
	TARGET_OUT_OF_BOUNDS = 9,
	RATE_LIMITED = 10,
}

var type: Type = Type.NONE
## Número de secuencia del cliente; lo confirma last_seq y lo usa COMMAND_REJECTED.
var seq: int = 0
## Ids de las entidades afectadas, ordenados de menor a mayor y sin repetir (máx. 512).
var entity_ids: PackedInt32Array = PackedInt32Array()
## Destino en el plano (x, z), en metros.
var target_pos: Vector2 = Vector2.ZERO
var target_id: int = SimConstants.NO_ENTITY
var def_id: StringName = &""
## Encolar tras las órdenes actuales (Shift).
var queued: bool = false
## Formación (0 = la por defecto).
var formation: int = 0


static func make_move(p_seq: int, ids: PackedInt32Array, pos: Vector2, attack: bool = false) -> Command:
	var cmd := Command.new()
	cmd.type = Type.ATTACK_MOVE if attack else Type.MOVE
	cmd.seq = p_seq
	cmd.entity_ids = normalize_ids(ids)
	cmd.target_pos = pos
	return cmd


static func make_stop(p_seq: int, ids: PackedInt32Array) -> Command:
	var cmd := Command.new()
	cmd.type = Type.STOP
	cmd.seq = p_seq
	cmd.entity_ids = normalize_ids(ids)
	return cmd


## Devuelve los ids ordenados, sin repetidos y sin el 0 (lo usa el cliente antes de enviar).
static func normalize_ids(ids: PackedInt32Array) -> PackedInt32Array:
	var sorted := ids.duplicate()
	sorted.sort()
	var out := PackedInt32Array()
	var last: int = SimConstants.NO_ENTITY
	for id: int in sorted:
		if id > last:
			out.append(id)
			last = id
	return out


## true si los ids son estrictamente crecientes y mayores que 0 (requisito del protocolo). O(n).
static func ids_are_sorted(ids: PackedInt32Array) -> bool:
	var last: int = SimConstants.NO_ENTITY
	for id: int in ids:
		if id <= last:
			return false
		last = id
	return true


## Codifica ids ordenados como: cantidad (varint), primer id (varint) y diferencias (varint).
## Unos 1,5 B por id con selecciones típicas. Los ids deben venir normalizados.
static func encode_entity_ids(ids: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	_write_varint(out, ids.size())
	var last: int = 0
	for id: int in ids:
		_write_varint(out, id - last)
		last = id
	return out


## Decodifica lo que produjo encode_entity_ids. Devuelve un array vacío si los datos están
## mal formados, si hay más de MAX_IDS_PER_COMMAND ids o si no son estrictamente crecientes.
static func decode_entity_ids(data: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pos: Array[int] = [0]
	var count: int = _read_varint(data, pos)
	if count < 0 or count > SimConstants.MAX_IDS_PER_COMMAND:
		return PackedInt32Array()
	out.resize(count)
	var last: int = 0
	for i: int in count:
		var delta: int = _read_varint(data, pos)
		if delta <= 0:
			return PackedInt32Array()
		last += delta
		if last > SimConstants.MAX_ENTITY_ID:
			return PackedInt32Array()
		out[i] = last
	if pos[0] != data.size():
		return PackedInt32Array()
	return out


static func _write_varint(out: PackedByteArray, value: int) -> void:
	var v: int = value
	while v >= 0x80:
		out.append((v & 0x7F) | 0x80)
		v >>= 7
	out.append(v)


## Lee un varint desde pos[0] (lo avanza). Devuelve -1 si los datos terminan o el valor es enorme.
static func _read_varint(data: PackedByteArray, pos: Array[int]) -> int:
	var result: int = 0
	var shift: int = 0
	while true:
		if pos[0] >= data.size() or shift > 28:
			return -1
		var b: int = data[pos[0]]
		pos[0] += 1
		result |= (b & 0x7F) << shift
		if b < 0x80:
			break
		shift += 7
	return result
