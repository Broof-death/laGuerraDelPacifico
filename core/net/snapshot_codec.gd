class_name SnapshotCodec
extends RefCounted
## Formato binario de los snapshots (ADR-006 punto 5, ADR-009 punto 2). Escritura por bits con
## BitWriter; nunca var_to_bytes. Lo comparten el servidor (SnapshotSender, en sim/) y el cliente
## (SnapshotReceiver).
##
## Cuantización:
##   posición absoluta x, z: 20 bits por eje sobre el mundo de 131 072 m centrado (paso 0,125 m)
##   posición delta respecto de la base confirmada: 2 x 8 bits con signo, paso 0,25 m (±31,75 m);
##     si no alcanza, se envía absoluta
##   rumbo 8 bits (1,4°) · vida 8 bits (fracción de max_hp) · acción 4 bits
##   progreso 8 bits (solo si la acción lo usa) · def_index 10 bits y dueño 4 bits al aparecer
##
## Paquete (<= 1200 B, decodificable por separado):
##   cabecera (19 B): Msg.SNAPSHOT 8 · tick 32 · base_tick 32 (NO_BASE = sin base) · parte 8 ·
##     partes 8 · last_seq 32 (dato privado: último comando del jugador recibido) ·
##     n_removed 16 · n_records 16
##   REMOVED: por baja, id (diferencia varint) + motivo 1 bit
##   registros: id (diferencia varint) + máscara de campos 8 bits + campos de la máscara.
##     Con FLAG_APPEAR el registro es completo: def 10, dueño 4, x 20, z 20, rumbo 8, vida 8,
##     acción 4 [progreso 8].
##   Las diferencias de id empiezan de 0 en cada paquete y en cada sección.
## Un snapshot son todas las partes con el mismo tick; el total no pasa de MAX_SNAPSHOT_BYTES.

const MAX_SNAPSHOT_BYTES: int = 4096
const MAX_PACKET_BYTES: int = Transport.MAX_UNRELIABLE_BYTES
const HEADER_BITS: int = 8 + 32 + 32 + 8 + 8 + 32 + 16 + 16
const HEADER_BYTES: int = HEADER_BITS / 8
## Bit de la cabecera donde empieza el campo "partes" (se rellena al final).
const PART_COUNT_BIT: int = 8 + 32 + 32 + 8
const REMOVED_COUNT_BIT: int = PART_COUNT_BIT + 8 + 32
const RECORD_COUNT_BIT: int = REMOVED_COUNT_BIT + 16
## base_tick cuando el snapshot no es delta (estado completo).
const NO_BASE: int = 0xFFFFFFFF

## Máscara de campos de un registro.
const FLAG_POS_DELTA: int = 0x01
const FLAG_POS_ABS: int = 0x02
const FLAG_HEADING: int = 0x04
const FLAG_HP: int = 0x08
const FLAG_ACTION: int = 0x10
const FLAG_PROGRESS: int = 0x20
## 0x40 y la máscara 0 quedan RESERVADOS para el registro de "grupo" (agregación por formaciones,
## pospuesta en v1). El decodificador los rechaza.
const FLAG_RESERVED: int = 0x40
const FLAG_APPEAR: int = 0x80

## Motivo de una baja en REMOVED.
enum RemoveReason { DIED = 0, OUT_OF_VIEW = 1 }

## Delta de posición: 8 bits con signo en pasos de 0,25 m = 2 pasos absolutos.
const DELTA_BITS: int = 8
const DELTA_LIMIT: int = 127
const DELTA_QUANTA: int = 2

## Disposición de la palabra de estado (int de 64 bits, 60 usados).
const QX_SHIFT: int = 0
const QZ_SHIFT: int = 20
const HEADING_SHIFT: int = 40
const HP_SHIFT: int = 48
const ACTION_SHIFT: int = 56
const Q_MASK: int = (1 << 20) - 1
const POS_MASK: int = (1 << 40) - 1
const BYTE_MASK: int = 0xFF
const ACTION_MASK: int = 0xF

const DEF_BITS: int = 10
const OWNER_BITS: int = 4
const ACTION_BITS: int = 4


## Una parte decodificada (un paquete). Los registros traen la palabra completa ya reconstruida.
class Part:
	var tick: int
	var base_tick: int
	var part: int
	var part_count: int
	var last_seq: int
	var removed_ids := PackedInt32Array()
	var removed_reasons := PackedByteArray()
	var rec_ids := PackedInt32Array()
	var rec_words := PackedInt64Array()
	var rec_prog := PackedByteArray()
	## 1 si el registro es una aparición (trae def y dueño).
	var rec_appear := PackedByteArray()
	var rec_def := PackedInt32Array()
	var rec_owner := PackedInt32Array()


# --- Cuantización ------------------------------------------------------------------------------

static func pack_word(qx: int, qz: int, heading8: int, hp8: int, action: int) -> int:
	return qx | (qz << QZ_SHIFT) | (heading8 << HEADING_SHIFT) | (hp8 << HP_SHIFT) | (action << ACTION_SHIFT)


static func word_qx(w: int) -> int:
	return w & Q_MASK


static func word_qz(w: int) -> int:
	return (w >> QZ_SHIFT) & Q_MASK


static func word_heading8(w: int) -> int:
	return (w >> HEADING_SHIFT) & BYTE_MASK


static func word_hp8(w: int) -> int:
	return (w >> HP_SHIFT) & BYTE_MASK


static func word_action(w: int) -> int:
	return (w >> ACTION_SHIFT) & ACTION_MASK


## Rumbo en radianes -> 8 bits (1,4°).
static func quantize_heading(h: float) -> int:
	return int(roundf(h * (256.0 / TAU))) & BYTE_MASK


## 8 bits -> radianes en [-PI, PI).
static func dequantize_heading(h8: int) -> float:
	return (h8 if h8 < 128 else h8 - 256) * (TAU / 256.0)


## Vida -> 8 bits como fracción de max_hp. Una entidad viva nunca se cuantiza a 0.
static func quantize_hp(hp: float, max_hp: float) -> int:
	if max_hp <= 0.0:
		return 0
	var q: int = clampi(int(roundf(hp / max_hp * 255.0)), 0, 255)
	return 1 if q == 0 and hp > 0.0 else q


static func dequantize_hp(hp8: int) -> float:
	return hp8 / 255.0


static func quantize_progress(p: float) -> int:
	return clampi(int(roundf(p * 255.0)), 0, 255)


## Acciones que usan el campo progress (construcción, entrenamiento...). Hoy ninguna.
static func action_uses_progress(_action: int) -> bool:
	return false


## Bits de la carga de una aparición (sin id ni máscara).
static func appear_payload_bits(action: int) -> int:
	return DEF_BITS + OWNER_BITS + 2 * MapGrid.QUANT_BITS + 8 + 8 + ACTION_BITS \
			+ (8 if action_uses_progress(action) else 0)


## Bits de la carga de una actualización según su máscara (sin id ni máscara).
static func update_payload_bits(mask: int) -> int:
	var b: int = 0
	if mask & FLAG_POS_DELTA:
		b += 2 * DELTA_BITS
	if mask & FLAG_POS_ABS:
		b += 2 * MapGrid.QUANT_BITS
	if mask & FLAG_HEADING:
		b += 8
	if mask & FLAG_HP:
		b += 8
	if mask & FLAG_ACTION:
		b += ACTION_BITS
	if mask & FLAG_PROGRESS:
		b += 8
	return b


# --- Escritura ---------------------------------------------------------------------------------

## Escribe la cabecera de una parte; "partes", n_removed y n_records se rellenan con patch_bits.
static func write_header(w: BitWriter, tick: int, base_tick: int, part: int, last_seq: int) -> void:
	w.write_bits(NetProtocol.Msg.SNAPSHOT, 8)
	w.write_bits(tick, 32)
	w.write_bits(base_tick, 32)
	w.write_bits(part, 8)
	w.write_bits(0, 8)
	w.write_bits(last_seq, 32)
	w.write_bits(0, 16)
	w.write_bits(0, 16)


## Escribe una aparición completa (después del id).
static func write_appear(w: BitWriter, word: int, prog8: int, def_index: int, owner: int) -> void:
	w.write_bits(FLAG_APPEAR, 8)
	w.write_bits(def_index, DEF_BITS)
	w.write_bits(owner, OWNER_BITS)
	w.write_bits(word & Q_MASK, 20)
	w.write_bits((word >> QZ_SHIFT) & Q_MASK, 20)
	w.write_bits((word >> HEADING_SHIFT) & BYTE_MASK, 8)
	w.write_bits((word >> HP_SHIFT) & BYTE_MASK, 8)
	var action: int = (word >> ACTION_SHIFT) & ACTION_MASK
	w.write_bits(action, ACTION_BITS)
	if action_uses_progress(action):
		w.write_bits(prog8, 8)


## Escribe una actualización (después del id). `word` es el resultado que tendrá el cliente;
## `base_word` la base confirmada (para el delta de posición).
static func write_update(w: BitWriter, mask: int, word: int, base_word: int, prog8: int) -> void:
	w.write_bits(mask, 8)
	if mask & FLAG_POS_DELTA:
		w.write_bits(((word & Q_MASK) - (base_word & Q_MASK)) / DELTA_QUANTA, DELTA_BITS)
		w.write_bits((((word >> QZ_SHIFT) & Q_MASK) - ((base_word >> QZ_SHIFT) & Q_MASK)) / DELTA_QUANTA, DELTA_BITS)
	elif mask & FLAG_POS_ABS:
		w.write_bits(word & Q_MASK, 20)
		w.write_bits((word >> QZ_SHIFT) & Q_MASK, 20)
	if mask & FLAG_HEADING:
		w.write_bits((word >> HEADING_SHIFT) & BYTE_MASK, 8)
	if mask & FLAG_HP:
		w.write_bits((word >> HP_SHIFT) & BYTE_MASK, 8)
	if mask & FLAG_ACTION:
		w.write_bits((word >> ACTION_SHIFT) & ACTION_MASK, ACTION_BITS)
	if mask & FLAG_PROGRESS:
		w.write_bits(prog8, 8)


# --- Lectura -----------------------------------------------------------------------------------

## Lee solo la cabecera: [tick, base_tick, parte, partes, last_seq] o vacío.
static func read_header(data: PackedByteArray) -> PackedInt64Array:
	if data.size() < HEADER_BYTES:
		return PackedInt64Array()
	var r := BitReader.new(data)
	if r.read_bits(8) != NetProtocol.Msg.SNAPSHOT:
		return PackedInt64Array()
	var out := PackedInt64Array([r.read_bits(32), r.read_bits(32), r.read_bits(8), r.read_bits(8), r.read_bits(32)])
	return PackedInt64Array() if r.error else out


## Decodifica una parte contra `base` (el estado del snapshot base_tick; vacío si NO_BASE).
## Devuelve null si el paquete está mal formado o si un registro de actualización no tiene base.
static func decode_part(data: PackedByteArray, base: SnapshotState) -> Part:
	if data.size() < HEADER_BYTES or data.size() > MAX_PACKET_BYTES:
		return null
	var r := BitReader.new(data)
	if r.read_bits(8) != NetProtocol.Msg.SNAPSHOT:
		return null
	var p := Part.new()
	p.tick = r.read_bits(32)
	p.base_tick = r.read_bits(32)
	p.part = r.read_bits(8)
	p.part_count = r.read_bits(8)
	p.last_seq = r.read_bits(32)
	var n_removed: int = r.read_bits(16)
	var n_records: int = r.read_bits(16)
	if r.error or p.part_count == 0 or p.part >= p.part_count:
		return null
	# Cada registro ocupa al menos 2 B; cada baja, al menos 1 B.
	if n_removed * 9 + n_records * 16 > r.bits_left():
		return null
	p.removed_ids.resize(n_removed)
	p.removed_reasons.resize(n_removed)
	var last: int = 0
	for i: int in n_removed:
		var d: int = r.read_varint()
		if d <= 0:
			return null
		last += d
		p.removed_ids[i] = last
		p.removed_reasons[i] = r.read_bits(1)
	p.rec_ids.resize(n_records)
	p.rec_words.resize(n_records)
	p.rec_prog.resize(n_records)
	p.rec_appear.resize(n_records)
	p.rec_def.resize(n_records)
	p.rec_owner.resize(n_records)
	last = 0
	var base_ids := base.ids
	var base_words := base.words
	var base_prog := base.prog
	var nb: int = base_ids.size()
	for i: int in n_records:
		var d: int = r.read_varint()
		if d <= 0:
			return null
		last += d
		p.rec_ids[i] = last
		var mask: int = r.read_bits(8)
		if r.error or mask == 0 or (mask & FLAG_RESERVED) != 0:
			return null
		if mask & FLAG_APPEAR:
			if mask != FLAG_APPEAR:
				return null
			p.rec_appear[i] = 1
			p.rec_def[i] = r.read_bits(DEF_BITS)
			p.rec_owner[i] = r.read_bits(OWNER_BITS)
			var qx: int = r.read_bits(20)
			var qz: int = r.read_bits(20)
			var h8: int = r.read_bits(8)
			var hp8: int = r.read_bits(8)
			var action: int = r.read_bits(ACTION_BITS)
			p.rec_words[i] = pack_word(qx, qz, h8, hp8, action)
			p.rec_prog[i] = r.read_bits(8) if action_uses_progress(action) else 0
			continue
		var bi: int = base_ids.bsearch(last)
		if bi >= nb or base_ids[bi] != last:
			return null
		var word: int = base_words[bi]
		var prog8: int = base_prog[bi]
		if mask & FLAG_POS_DELTA:
			if mask & FLAG_POS_ABS:
				return null
			var dx: int = r.read_signed(DELTA_BITS)
			var dz: int = r.read_signed(DELTA_BITS)
			var qx2: int = clampi((word & Q_MASK) + dx * DELTA_QUANTA, 0, Q_MASK)
			var qz2: int = clampi(((word >> QZ_SHIFT) & Q_MASK) + dz * DELTA_QUANTA, 0, Q_MASK)
			word = (word & ~POS_MASK) | qx2 | (qz2 << QZ_SHIFT)
		elif mask & FLAG_POS_ABS:
			var qx3: int = r.read_bits(20)
			var qz3: int = r.read_bits(20)
			word = (word & ~POS_MASK) | qx3 | (qz3 << QZ_SHIFT)
		if mask & FLAG_HEADING:
			word = (word & ~(BYTE_MASK << HEADING_SHIFT)) | (r.read_bits(8) << HEADING_SHIFT)
		if mask & FLAG_HP:
			word = (word & ~(BYTE_MASK << HP_SHIFT)) | (r.read_bits(8) << HP_SHIFT)
		if mask & FLAG_ACTION:
			word = (word & ~(ACTION_MASK << ACTION_SHIFT)) | (r.read_bits(ACTION_BITS) << ACTION_SHIFT)
		if mask & FLAG_PROGRESS:
			prog8 = r.read_bits(8)
		p.rec_words[i] = word
		p.rec_prog[i] = prog8
	if r.error or r.bits_left() >= 8:
		return null
	return p
