class_name SnapshotSender
extends RefCounted
## Armado de snapshots para UN cliente (ADR-006 punto 5): delta contra el último snapshot que el
## cliente confirmó con ack, lista REMOVED explícita, tope de 4 KB con prioridad y paquetes de
## <= 1200 B decodificables por separado.
##
## Cómo funciona el delta: el servidor guarda un anillo de los últimos RING_SIZE estados enviados
## (SnapshotState). El estado de un snapshot S = el estado de su base B (el último confirmado)
## con los registros de S encima. Lo que no cupo por el tope sigue con el valor de B, así que el
## cliente reconstruye exactamente el mismo estado y puede usarlo como base cuando el servidor lo
## reciba confirmado. Con pérdida, el servidor sigue usando la última base confirmada y repite lo
## que haga falta (también las bajas de REMOVED, que se repiten hasta que un ack las cubra).
## Si la base no avanza en ACK_TIMEOUT_TICKS (1 s), se descarta y el estado se reenvía completo,
## repartido en varios snapshots por el tope.
##
## Prioridad dentro del tope: REMOVED, datos privados (cabecera), apariciones y después el resto
## por antigüedad (ticks desde que la copia del cliente era exacta), con el doble para las
## entidades en combate. Los empates rotan entre snapshots para repartir lo aplazado.

const RING_SIZE: int = 32
const ACK_TIMEOUT_TICKS: int = SimConstants.TICK_RATE
const _AGE_CAP: int = (1 << 21) - 1
const _PRIO_APPEAR: int = (1 << 22) + 1
const _K_UPDATE: int = 0
const _K_APPEAR: int = 1
const _K_REMOVED: int = 2
const _MAX_PACKET_BITS: int = SnapshotCodec.MAX_PACKET_BYTES * 8
## Partes que se reservan en el presupuesto (cabeceras) al elegir qué entra.
const _BUDGET_PARTS: int = (SnapshotCodec.MAX_SNAPSHOT_BYTES + SnapshotCodec.MAX_PACKET_BYTES - 1) / SnapshotCodec.MAX_PACKET_BYTES

var player_id: int
## Tick del último snapshot confirmado que se usa como base (-1 = sin base: estado completo).
var base_tick: int = -1

# --- Estadísticas del último build() ---
var last_bytes: int = 0
var last_packets: int = 0
var last_records: int = 0
var last_removed: int = 0
## Cambios que no cupieron en el tope y quedaron para el siguiente snapshot.
var last_deferred: int = 0
## Máxima antigüedad (ticks) entre las entidades en combate con cambios pendientes.
var last_max_combat_age: int = 0
var full_resets: int = 0
## Registros elegidos que el tope exacto tuvo que recortar en el último build().
var last_cap_cuts: int = 0
var total_bytes: int = 0
var snapshots_sent: int = 0

## Margen del presupuesto (bytes) para lo que la estimación no ve (ids que ocupan 2 B, primer id
## de cada paquete, final de paquete). Es adaptativo: crece si el tope exacto tuvo que recortar y
## baja de a poco si no; así el recorte (que va en orden de id, no de prioridad) casi nunca ocurre
## y no deja siempre afuera a los mismos ids altos.
var _slack_bytes: int = 64
const _SLACK_MIN: int = 32
const _SLACK_MAX: int = 768
var _last_ack_at: int = 0
var _ring: Dictionary[int, SnapshotState] = {}
var _ring_ticks := PackedInt32Array()
var _rot: int = 0
var _empty := SnapshotState.new()

# Registros del snapshot en armado (arrays reutilizados).
var _r_kind := PackedByteArray()
var _r_wi := PackedInt32Array()
var _r_bi := PackedInt32Array()
var _r_mask := PackedInt32Array()
var _r_word := PackedInt64Array()
var _r_bits := PackedInt32Array()
var _r_prio := PackedInt32Array()
var _r_chosen := PackedByteArray()
var _sort_keys := PackedInt64Array()


func _init(p_player_id: int, current_tick: int = 0) -> void:
	player_id = p_player_id
	_last_ack_at = current_tick


## El cliente confirmó que recibió completo el snapshot `tick`.
func on_ack(tick: int, server_tick: int) -> void:
	if tick <= base_tick or not _ring.has(tick):
		return
	base_tick = tick
	_last_ack_at = server_tick
	# Los estados anteriores a la base ya no hacen falta.
	while _ring_ticks.size() > 0 and _ring_ticks[0] < tick:
		_ring.erase(_ring_ticks[0])
		_ring_ticks.remove_at(0)


func has_state(tick: int) -> bool:
	return _ring.has(tick)


func get_state(tick: int) -> SnapshotState:
	return _ring.get(tick)


## Arma el snapshot de `world` para este cliente. Devuelve los paquetes a enviar (1 o más).
func build(world: SnapshotWorld, last_seq: int) -> Array[PackedByteArray]:
	var now: int = world.tick
	if base_tick >= 0 and now - _last_ack_at > ACK_TIMEOUT_TICKS:
		base_tick = -1
		full_resets += 1
	var base: SnapshotState = _ring[base_tick] if base_tick >= 0 else _empty
	var nr: int = _merge(world, base, now)
	_select(nr)
	var packets: Array[PackedByteArray] = _encode(world, base, nr, now, last_seq)
	_store_state(world, base, nr, now)
	snapshots_sent += 1
	return packets


## Recorre en orden de id el mundo y la base, y anota los registros: apariciones, cambios y bajas.
## Devuelve la cantidad de registros.
func _merge(world: SnapshotWorld, base: SnapshotState, now: int) -> int:
	var nw: int = world.count
	var nb: int = base.ids.size()
	var cap: int = nw + nb
	if _r_kind.size() < cap:
		_r_kind.resize(cap)
		_r_wi.resize(cap)
		_r_bi.resize(cap)
		_r_mask.resize(cap)
		_r_word.resize(cap)
		_r_bits.resize(cap)
		_r_prio.resize(cap)
		_r_chosen.resize(cap)
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
	var rmask := _r_mask
	var rword := _r_word
	var rbits := _r_bits
	var rprio := _r_prio
	var wid := world.ids
	var ww := world.words
	var wprog := world.prog
	var wvis := world.vis
	var wown := world.owner
	var wcombat := world.combat
	var bid := base.ids
	var bw := base.words
	var bprog := base.prog
	var bfresh := base.fresh
	var pid: int = player_id
	var pbit: int = 1 << pid
	var max_age: int = 0
	const BIG: int = 0x7FFFFFFF
	const QM: int = SnapshotCodec.Q_MASK
	const LIM: int = SnapshotCodec.DELTA_LIMIT
	const POSM: int = SnapshotCodec.POS_MASK
	const APPEAR_BITS: int = 8 + 10 + 4 + 40 + 8 + 8 + 4
	var nr: int = 0
	var i: int = 0
	var j: int = 0
	while i < nw or j < nb:
		var a: int = wid[i] if i < nw else BIG
		var b: int = bid[j] if j < nb else BIG
		if a < b:
			if (wvis[i] & pbit) != 0 or wown[i] == pid:
				var aw: int = ww[i]
				rk[nr] = _K_APPEAR
				rwi[nr] = i
				rbi[nr] = -1
				rmask[nr] = SnapshotCodec.FLAG_APPEAR
				rword[nr] = aw
				rbits[nr] = SnapshotCodec.appear_payload_bits((aw >> 56) & 0xF) + 8
				rprio[nr] = _PRIO_APPEAR
				nr += 1
			i += 1
		elif b < a:
			rk[nr] = _K_REMOVED
			rwi[nr] = -1
			rbi[nr] = j
			rmask[nr] = SnapshotCodec.RemoveReason.DIED
			nr += 1
			j += 1
		else:
			if (wvis[i] & pbit) == 0 and wown[i] != pid:
				rk[nr] = _K_REMOVED
				rwi[nr] = i
				rbi[nr] = j
				rmask[nr] = SnapshotCodec.RemoveReason.OUT_OF_VIEW
				nr += 1
			else:
				var nwd: int = ww[i]
				var owd: int = bw[j]
				var diff: int = nwd ^ owd
				if diff != 0 or (wprog[i] != bprog[j] and SnapshotCodec.action_uses_progress((nwd >> 56) & 0xF)):
					var mask: int = 0
					var bits: int = 8
					var res: int = owd
					if (diff & POSM) != 0:
						var oqx: int = owd & QM
						var oqz: int = (owd >> 20) & QM
						var dx: int = (nwd & QM) - oqx
						var dz: int = ((nwd >> 20) & QM) - oqz
						# Redondeo a pasos de 0,25 m (alejándose de cero en los medios).
						var ddx: int = (dx + (1 if dx > 0 else (-1 if dx < 0 else 0))) / 2
						var ddz: int = (dz + (1 if dz > 0 else (-1 if dz < 0 else 0))) / 2
						if ddx >= -LIM and ddx <= LIM and ddz >= -LIM and ddz <= LIM:
							if ddx != 0 or ddz != 0:
								var rqx: int = clampi(oqx + ddx * 2, 0, QM)
								var rqz: int = clampi(oqz + ddz * 2, 0, QM)
								mask |= SnapshotCodec.FLAG_POS_DELTA
								bits += 16
								res = (res & ~POSM) | rqx | (rqz << 20)
						else:
							mask |= SnapshotCodec.FLAG_POS_ABS
							bits += 40
							res = (res & ~POSM) | (nwd & POSM)
					if (diff & (0xFF << 40)) != 0:
						mask |= SnapshotCodec.FLAG_HEADING
						bits += 8
						res = (res & ~(0xFF << 40)) | (nwd & (0xFF << 40))
					if (diff & (0xFF << 48)) != 0:
						mask |= SnapshotCodec.FLAG_HP
						bits += 8
						res = (res & ~(0xFF << 48)) | (nwd & (0xFF << 48))
					if (diff & (0xF << 56)) != 0:
						mask |= SnapshotCodec.FLAG_ACTION
						bits += 4
						res = (res & ~(0xF << 56)) | (nwd & (0xF << 56))
					if wprog[i] != bprog[j] and SnapshotCodec.action_uses_progress((nwd >> 56) & 0xF):
						mask |= SnapshotCodec.FLAG_PROGRESS
						bits += 8
					if mask != 0:
						var age: int = mini(now - bfresh[j], _AGE_CAP)
						if wcombat[i] != 0:
							max_age = maxi(max_age, age)
							age *= 2
						rk[nr] = _K_UPDATE
						rwi[nr] = i
						rbi[nr] = j
						rmask[nr] = mask
						rword[nr] = res
						rbits[nr] = bits
						rprio[nr] = age
						nr += 1
			i += 1
			j += 1
	last_max_combat_age = max_age
	return nr


## Marca en _r_chosen lo que entra en el presupuesto (estimado; _encode aplica el tope exacto).
func _select(nr: int) -> void:
	var rk := _r_kind
	var chosen := _r_chosen
	var budget: int = (SnapshotCodec.MAX_SNAPSHOT_BYTES - _BUDGET_PARTS * SnapshotCodec.HEADER_BYTES - _slack_bytes) * 8
	var others: int = 0
	for k: int in nr:
		if rk[k] == _K_REMOVED:
			chosen[k] = 1
			budget -= 9
		else:
			chosen[k] = 0
			others += 1
	if others == 0:
		return
	if _sort_keys.size() < others:
		_sort_keys.resize(others)
	var keys := _sort_keys
	var rprio := _r_prio
	var rot: int = _rot % others
	var m: int = 0
	for k: int in nr:
		if rk[k] != _K_REMOVED:
			var slot: int = m + rot
			if slot >= others:
				slot -= others
			keys[m] = ((_PRIO_APPEAR - rprio[k]) << 40) | (slot << 20) | k
			m += 1
	# Solo se ordena lo usado (el resto del array reutilizado queda con valores viejos al final).
	var used := keys.slice(0, others)
	used.sort()
	var rbits := _r_bits
	var taken: int = 0
	for key: int in used:
		if budget < 24:
			break
		var k: int = key & 0xFFFFF
		var cost: int = rbits[k] + 8
		if cost <= budget:
			chosen[k] = 1
			budget -= cost
			taken += 1
	_rot += taken


## Escribe los paquetes. Aplica los topes exactos (1200 B por paquete, 4096 B en total): lo que no
## entra se desmarca y queda aplazado.
func _encode(world: SnapshotWorld, base: SnapshotState, nr: int, now: int, last_seq: int) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
	var rmask := _r_mask
	var rword := _r_word
	var rbits := _r_bits
	var chosen := _r_chosen
	var wid := world.ids
	var wprog := world.prog
	var wdef := world.def_index
	var wown := world.owner
	var bid := base.ids
	var bw := base.words
	var header_base: int = base_tick if base_tick >= 0 else SnapshotCodec.NO_BASE
	var total: int = 0
	var part: int = 0
	var w := BitWriter.new()
	SnapshotCodec.write_header(w, now, header_base, part, last_seq)
	var n_rem: int = 0
	var n_rec: int = 0
	var prev: int = 0
	var records: int = 0
	var removed: int = 0
	var deferred: int = 0
	var cut: int = 0

	# 1) REMOVED.
	for k: int in nr:
		if rk[k] != _K_REMOVED or chosen[k] == 0:
			continue
		var id: int = bid[rbi[k]]
		var bits: int = BitWriter.varint_bits(id - prev) + 1
		if w.bit_length() + bits > _MAX_PACKET_BITS:
			total += _close_packet(w, n_rem, n_rec, packets)
			part += 1
			w = BitWriter.new()
			SnapshotCodec.write_header(w, now, header_base, part, last_seq)
			n_rem = 0
			n_rec = 0
			prev = 0
			bits = BitWriter.varint_bits(id) + 1
		if total + ((w.bit_length() + bits + 7) >> 3) > SnapshotCodec.MAX_SNAPSHOT_BYTES:
			chosen[k] = 0
			deferred += 1
			continue
		w.write_varint(id - prev)
		w.write_bits(rmask[k], 1)
		prev = id
		n_rem += 1
		removed += 1

	# 2) Apariciones y cambios, en orden de id.
	prev = 0
	for k: int in nr:
		if rk[k] == _K_REMOVED:
			continue
		if chosen[k] == 0:
			deferred += 1
			continue
		var wi: int = rwi[k]
		var id: int = wid[wi]
		var bits: int = BitWriter.varint_bits(id - prev) + rbits[k]
		if w.bit_length() + bits > _MAX_PACKET_BITS:
			total += _close_packet(w, n_rem, n_rec, packets)
			part += 1
			w = BitWriter.new()
			SnapshotCodec.write_header(w, now, header_base, part, last_seq)
			n_rem = 0
			n_rec = 0
			prev = 0
			bits = BitWriter.varint_bits(id) + rbits[k]
		if total + ((w.bit_length() + bits + 7) >> 3) > SnapshotCodec.MAX_SNAPSHOT_BYTES:
			chosen[k] = 0
			deferred += 1
			cut += 1
			continue
		w.write_varint(id - prev)
		if rk[k] == _K_APPEAR:
			SnapshotCodec.write_appear(w, rword[k], wprog[wi], wdef[wi], wown[wi])
		else:
			SnapshotCodec.write_update(w, rmask[k], rword[k], bw[rbi[k]], wprog[wi])
		prev = id
		n_rec += 1
		records += 1
	total += _close_packet(w, n_rem, n_rec, packets)

	# Número de partes (byte alineado de la cabecera).
	var pc_byte: int = SnapshotCodec.PART_COUNT_BIT >> 3
	for p: PackedByteArray in packets:
		p[pc_byte] = packets.size()
	if cut > 0:
		_slack_bytes = mini(_slack_bytes + 32 + cut * 8, _SLACK_MAX)
	else:
		_slack_bytes = maxi(_slack_bytes - 2, _SLACK_MIN)
	last_cap_cuts = cut
	last_bytes = total
	last_packets = packets.size()
	last_records = records
	last_removed = removed
	last_deferred = deferred
	total_bytes += total
	return packets


func _close_packet(w: BitWriter, n_rem: int, n_rec: int, packets: Array[PackedByteArray]) -> int:
	w.patch_bits(SnapshotCodec.REMOVED_COUNT_BIT, n_rem, 16)
	w.patch_bits(SnapshotCodec.RECORD_COUNT_BIT, n_rec, 16)
	var bytes := w.get_bytes()
	packets.append(bytes)
	return bytes.size()


## Guarda en el anillo el estado que tendrá el cliente al recibir completo este snapshot.
func _store_state(world: SnapshotWorld, base: SnapshotState, nr: int, now: int) -> void:
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
	var rword := _r_word
	var chosen := _r_chosen
	var wid := world.ids
	var wprog := world.prog
	var bid := base.ids
	var bw := base.words
	var bprog := base.prog
	var bfresh := base.fresh
	var nb: int = bid.size()
	var appear_count: int = 0
	for k: int in nr:
		if rk[k] == _K_APPEAR and chosen[k] != 0:
			appear_count += 1
	var st := SnapshotState.new()
	st.resize(nb + appear_count, true)
	var sid := st.ids
	var sw := st.words
	var sp := st.prog
	var sf := st.fresh
	var o: int = 0
	var j: int = 0
	for k: int in nr:
		var kind: int = rk[k]
		var rid: int = wid[rwi[k]] if kind == _K_APPEAR else bid[rbi[k]]
		# Lo que está en la base y no tiene registro: visible y sin cambios -> exacto en `now`.
		while j < nb and bid[j] < rid:
			sid[o] = bid[j]
			sw[o] = bw[j]
			sp[o] = bprog[j]
			sf[o] = now
			o += 1
			j += 1
		if kind == _K_APPEAR:
			if chosen[k] != 0:
				sid[o] = rid
				sw[o] = rword[k]
				sp[o] = wprog[rwi[k]]
				sf[o] = now
				o += 1
			continue
		if kind == _K_UPDATE and chosen[k] != 0:
			sid[o] = rid
			sw[o] = rword[k]
			sp[o] = wprog[rwi[k]]
			sf[o] = now
			o += 1
		elif kind == _K_UPDATE or chosen[k] == 0:
			# Cambio aplazado o baja que no entró: el cliente sigue con la base.
			sid[o] = bid[j]
			sw[o] = bw[j]
			sp[o] = bprog[j]
			sf[o] = bfresh[j]
			o += 1
		j += 1
	while j < nb:
		sid[o] = bid[j]
		sw[o] = bw[j]
		sp[o] = bprog[j]
		sf[o] = now
		o += 1
		j += 1
	st.resize(o, true)
	_ring[now] = st
	_ring_ticks.append(now)
	while _ring_ticks.size() > RING_SIZE:
		var old: int = _ring_ticks[0]
		_ring.erase(old)
		_ring_ticks.remove_at(0)
		if old == base_tick:
			base_tick = -1
