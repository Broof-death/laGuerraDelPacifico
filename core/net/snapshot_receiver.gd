class_name SnapshotReceiver
extends RefCounted
## Lado cliente del protocolo de snapshots (ADR-006 punto 5). Decodifica cada parte contra su
## base (que el cliente tiene porque la confirmó) y, cuando llegan todas las partes de un tick,
## reconstruye el estado completo, lo guarda en un anillo de RING_SIZE estados y pide el ack.
## Las partes sueltas se entregan enseguida (se pueden dibujar aunque falte otra parte); un
## snapshot incompleto nunca se confirma ni se usa como base.

const RING_SIZE: int = 32
## Snapshots incompletos que se recuerdan a la vez.
const MAX_PENDING: int = 8

class _Pending:
	var part_count: int
	var base_tick: int
	var received := PackedByteArray()
	var parts: Array[SnapshotCodec.Part] = []


## Tick del último snapshot recibido completo (-1 = ninguno).
var latest_complete_tick: int = -1
## Tick de la última parte recibida.
var latest_tick: int = -1
## Último comando del jugador que el servidor recibió (dato privado de la cabecera).
var last_seq: int = 0
## Tick completado por la última llamada a receive() (-1 si no completó ninguno): hay que
## enviarle un ack al servidor.
var completed_tick: int = -1

var parts_received: int = 0
var parts_rejected: int = 0
var parts_without_base: int = 0
var snapshots_completed: int = 0

## id -> (def_index << 4) | owner, recordado desde la aparición.
var _meta: Dictionary[int, int] = {}
var _ring: Dictionary[int, SnapshotState] = {}
var _ring_ticks := PackedInt32Array()
var _pending: Dictionary[int, _Pending] = {}
var _empty := SnapshotState.new()


## Procesa un paquete SNAPSHOT. Devuelve la parte decodificada (con def y dueño también en los
## registros de actualización; -1 si no se conocen) o null si se descarta.
func receive(data: PackedByteArray) -> SnapshotCodec.Part:
	completed_tick = -1
	var hdr := SnapshotCodec.read_header(data)
	if hdr.is_empty():
		parts_rejected += 1
		return null
	var tick: int = hdr[0]
	var base_tick: int = hdr[1]
	if tick <= latest_complete_tick:
		return null
	var base: SnapshotState = _empty
	if base_tick != SnapshotCodec.NO_BASE:
		if not _ring.has(base_tick):
			parts_without_base += 1
			return null
		base = _ring[base_tick]
	var p := SnapshotCodec.decode_part(data, base)
	if p == null:
		parts_rejected += 1
		return null
	var pend: _Pending = _pending.get(tick)
	if pend == null:
		pend = _Pending.new()
		pend.part_count = p.part_count
		pend.base_tick = base_tick
		pend.received.resize(p.part_count)
		pend.parts.resize(p.part_count)
		_pending[tick] = pend
	if pend.part_count != p.part_count or pend.base_tick != base_tick or pend.received[p.part] != 0:
		return null
	pend.received[p.part] = 1
	pend.parts[p.part] = p
	parts_received += 1
	latest_tick = maxi(latest_tick, tick)
	last_seq = p.last_seq

	# Def y dueño de cada registro.
	for i: int in p.rec_ids.size():
		var id: int = p.rec_ids[i]
		if p.rec_appear[i] != 0:
			_meta[id] = (p.rec_def[i] << 4) | p.rec_owner[i]
		else:
			var m: int = _meta.get(id, -1)
			p.rec_def[i] = (m >> 4) if m >= 0 else -1
			p.rec_owner[i] = (m & 0xF) if m >= 0 else -1
	for i: int in p.removed_ids.size():
		if p.removed_reasons[i] == SnapshotCodec.RemoveReason.DIED:
			_meta.erase(p.removed_ids[i])

	if not pend.received.has(0):
		_complete(tick, pend, base)
	elif _pending.size() > MAX_PENDING:
		var oldest: int = tick
		for t: int in _pending:
			oldest = mini(oldest, t)
		_pending.erase(oldest)
	return p


func get_state(tick: int) -> SnapshotState:
	return _ring.get(tick)


func _complete(tick: int, pend: _Pending, base: SnapshotState) -> void:
	# Registros y bajas de todas las partes, en orden de id (las partes van en orden de id).
	var rec_ids := PackedInt32Array()
	var rec_words := PackedInt64Array()
	var rec_prog := PackedByteArray()
	var removed := PackedInt32Array()
	for p: SnapshotCodec.Part in pend.parts:
		rec_ids.append_array(p.rec_ids)
		rec_words.append_array(p.rec_words)
		rec_prog.append_array(p.rec_prog)
		removed.append_array(p.removed_ids)
	var bid := base.ids
	var bw := base.words
	var bp := base.prog
	var nb: int = bid.size()
	var nr: int = rec_ids.size()
	var nq: int = removed.size()
	var st := SnapshotState.new()
	st.resize(nb + nr, false)
	var sid := st.ids
	var sw := st.words
	var sp := st.prog
	const BIG: int = 0x7FFFFFFF
	var o: int = 0
	var j: int = 0
	var r: int = 0
	var q: int = 0
	while j < nb or r < nr:
		var b: int = bid[j] if j < nb else BIG
		var a: int = rec_ids[r] if r < nr else BIG
		if a <= b:
			sid[o] = a
			sw[o] = rec_words[r]
			sp[o] = rec_prog[r]
			o += 1
			r += 1
			if a == b:
				j += 1
		else:
			while q < nq and removed[q] < b:
				q += 1
			if q >= nq or removed[q] != b:
				sid[o] = b
				sw[o] = bw[j]
				sp[o] = bp[j]
				o += 1
			j += 1
	st.resize(o, false)
	_ring[tick] = st
	_ring_ticks.append(tick)
	while _ring_ticks.size() > RING_SIZE:
		_ring.erase(_ring_ticks[0])
		_ring_ticks.remove_at(0)
	latest_complete_tick = tick
	completed_tick = tick
	snapshots_completed += 1
	for t: int in _pending.keys():
		if t <= tick:
			_pending.erase(t)
