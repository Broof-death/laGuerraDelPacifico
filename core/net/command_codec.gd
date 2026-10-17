class_name CommandCodec
extends RefCounted
## Códec binario completo de Command (ADR-006 punto 3), con BitWriter/BitReader.
## Formato (después del byte NetProtocol.Msg.COMMAND):
##   type 8 bits · seq varint · flags 8 bits
##   entity_ids: cantidad varint + primer id y diferencias en varint (ordenados, ~1,5 B por id)
##   [target_pos: x, z de 20 bits cuantizados como en los snapshots (paso 0,125 m, ADR-009)]
##   [target_id varint] [def_id: largo 8 bits + UTF-8] [formation 8 bits]
## Los campos entre corchetes solo van si su flag está activo. player_id nunca viaja.

const FLAG_QUEUED: int = 1
const FLAG_TARGET_POS: int = 2
const FLAG_TARGET_ID: int = 4
const FLAG_DEF_ID: int = 8
const FLAG_FORMATION: int = 16
## Largo máximo de def_id en bytes.
const MAX_DEF_ID_BYTES: int = 64
## Ningún comando válido ocupa más (512 ids ocupan como mucho ~2,5 KB en el peor caso de ids
## muy separados; lo normal es < 1 KB). MatchServer rechaza paquetes más grandes sin decodificarlos.
const MAX_COMMAND_BYTES: int = 3072


## Codifica un comando como paquete COMMAND. Devuelve un array vacío si el comando no se puede
## enviar (ids desordenados o de más, destino no finito, def_id demasiado largo).
static func encode(cmd: Command) -> PackedByteArray:
	if cmd == null or not Command.ids_are_sorted(cmd.entity_ids) \
			or cmd.entity_ids.size() > SimConstants.MAX_IDS_PER_COMMAND:
		return PackedByteArray()
	var def_bytes: PackedByteArray = String(cmd.def_id).to_utf8_buffer()
	if def_bytes.size() > MAX_DEF_ID_BYTES:
		return PackedByteArray()
	# (0, 0) es el centro del mapa y es un destino válido: el destino viaja según el tipo.
	var has_pos: bool = uses_target_pos(cmd.type)
	if has_pos and not cmd.target_pos.is_finite():
		return PackedByteArray()
	var flags: int = 0
	if cmd.queued:
		flags |= FLAG_QUEUED
	if has_pos:
		flags |= FLAG_TARGET_POS
	if cmd.target_id != SimConstants.NO_ENTITY:
		flags |= FLAG_TARGET_ID
	if not def_bytes.is_empty():
		flags |= FLAG_DEF_ID
	if cmd.formation != 0:
		flags |= FLAG_FORMATION

	var w := BitWriter.new()
	w.write_bits(NetProtocol.Msg.COMMAND, 8)
	w.write_bits(cmd.type, 8)
	w.write_varint(cmd.seq)
	w.write_bits(flags, 8)
	w.write_varint(cmd.entity_ids.size())
	var last: int = 0
	for id: int in cmd.entity_ids:
		w.write_varint(id - last)
		last = id
	if has_pos:
		w.write_bits(MapGrid.quantize(cmd.target_pos.x), MapGrid.QUANT_BITS)
		w.write_bits(MapGrid.quantize(cmd.target_pos.y), MapGrid.QUANT_BITS)
	if flags & FLAG_TARGET_ID:
		w.write_varint(cmd.target_id)
	if flags & FLAG_DEF_ID:
		w.write_bits(def_bytes.size(), 8)
		for b: int in def_bytes:
			w.write_bits(b, 8)
	if flags & FLAG_FORMATION:
		w.write_bits(cmd.formation, 8)
	return w.get_bytes()


## Tipos cuyo destino (target_pos) viaja siempre.
static func uses_target_pos(type: int) -> bool:
	return type == Command.Type.MOVE or type == Command.Type.ATTACK_MOVE or type == Command.Type.GATHER 			or type == Command.Type.BUILD or type == Command.Type.SET_RALLY


## Decodifica un paquete COMMAND. Devuelve null si está mal formado (tipo fuera de rango, ids
## desordenados, repetidos o más de 512, datos truncados o sobrantes, demasiado grande).
static func decode(data: PackedByteArray) -> Command:
	if data.size() < 4 or data.size() > MAX_COMMAND_BYTES:
		return null
	var r := BitReader.new(data)
	if r.read_bits(8) != NetProtocol.Msg.COMMAND:
		return null
	var cmd := Command.new()
	var type: int = r.read_bits(8)
	if type <= Command.Type.NONE or type > Command.Type.SET_RALLY:
		return null
	cmd.type = type as Command.Type
	cmd.seq = r.read_varint()
	var flags: int = r.read_bits(8)
	if flags & ~(FLAG_QUEUED | FLAG_TARGET_POS | FLAG_TARGET_ID | FLAG_DEF_ID | FLAG_FORMATION):
		return null
	cmd.queued = (flags & FLAG_QUEUED) != 0
	var count: int = r.read_varint()
	if r.error or count > SimConstants.MAX_IDS_PER_COMMAND:
		return null
	var ids := PackedInt32Array()
	ids.resize(count)
	var last: int = 0
	for i: int in count:
		var delta: int = r.read_varint()
		if r.error or delta <= 0:
			return null
		last += delta
		if last > SimConstants.MAX_ENTITY_ID:
			return null
		ids[i] = last
	cmd.entity_ids = ids
	if flags & FLAG_TARGET_POS:
		var qx: int = r.read_bits(MapGrid.QUANT_BITS)
		var qz: int = r.read_bits(MapGrid.QUANT_BITS)
		cmd.target_pos = Vector2(MapGrid.dequantize(qx), MapGrid.dequantize(qz))
	if flags & FLAG_TARGET_ID:
		cmd.target_id = r.read_varint()
		if cmd.target_id > SimConstants.MAX_ENTITY_ID:
			return null
	if flags & FLAG_DEF_ID:
		var n: int = r.read_bits(8)
		if n > MAX_DEF_ID_BYTES:
			return null
		var bytes := PackedByteArray()
		bytes.resize(n)
		for i: int in n:
			bytes[i] = r.read_bits(8)
		cmd.def_id = StringName(bytes.get_string_from_utf8())
	if flags & FLAG_FORMATION:
		cmd.formation = r.read_bits(8)
	# Solo puede sobrar el relleno del último byte.
	if r.error or r.bits_left() >= 8:
		return null
	return cmd
