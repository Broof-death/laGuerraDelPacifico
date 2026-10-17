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
var last_max_packet_bytes: int = 0
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


## Recorre en orden de id el mundo y la base, y anota los registros: apariciones, cambios y bajas,
## con su prioridad y una estimación de su tamaño (el cálculo exacto de los campos se hace en
## _encode y solo para lo que entra). Devuelve la cantidad de registros.
func _merge(world: SnapshotWorld, base: SnapshotState, now: int) -> int:
	var nw: int = world.count
	var nb: int = base.ids.size()
	var cap: int = nw + nb
	if _r_kind.size() < cap:
		_r_kind.resize(cap)
		_r_wi.resize(cap)
		_r_bi.resize(cap)
		_r_word.resize(cap)
		_r_bits.resize(cap)
		_r_prio.resize(cap)
		_r_chosen.resize(cap)
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
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
	const POSM: int = SnapshotCodec.POS_MASK
	const HM: int = 0xFF << 40
	const HPM: int = 0xFF << 48
	const AM: int = 0xF << 56
	const APPEAR_BITS: int = 8 + 10 + 4 + 40 + 8 + 8 + 4
	const DIED: int = SnapshotCodec.RemoveReason.DIED
	const OUT: int = SnapshotCodec.RemoveReason.OUT_OF_VIEW
	var nr: int = 0
	var i: int = 0
	var j: int = 0
	while i < nw or j < nb:
		var a: int = wid[i] if i < nw else BIG
		var b: int = bid[j] if j < nb else BIG
		if a == b:
			if (wvis[i] & pbit) == 0 and wown[i] != pid:
				rk[nr] = _K_REMOVED
				rbi[nr] = j
				rbits[nr] = OUT
				nr += 1
			else:
				var diff: int = ww[i] ^ bw[j]
				var prog_changed: bool = wprog[i] != bprog[j] and SnapshotCodec.action_uses_progress((ww[i] >> 56) & 0xF)
				if diff != 0 or prog_changed:
					var bits: int = 8
					if diff & POSM:
						bits += 16
					if diff & HM:
						bits += 8
					if diff & HPM:
						bits += 8
					if diff & AM:
						bits += 4
					if prog_changed:
						bits += 8
					var age: int = mini(now - bfresh[j], _AGE_CAP)
					if wcombat[i] != 0:
						max_age = maxi(max_age, age)
						age *= 2
					rk[nr] = _K_UPDATE
					rwi[nr] = i
					rbi[nr] = j
					rbits[nr] = bits
					rprio[nr] = age
					nr += 1
			i += 1
			j += 1
		elif a < b:
			if (wvis[i] & pbit) != 0 or wown[i] == pid:
				rk[nr] = _K_APPEAR
				rwi[nr] = i
				rbi[nr] = -1
				rbits[nr] = APPEAR_BITS + (8 if SnapshotCodec.action_uses_progress((ww[i] >> 56) & 0xF) else 0)
				rprio[nr] = _PRIO_APPEAR
				nr += 1
			i += 1
		else:
			rk[nr] = _K_REMOVED
			rbi[nr] = j
			rbits[nr] = DIED
			nr += 1
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
	if _sort_keys.size() != others:
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
	keys.sort()
	var rbits := _r_bits
	var taken: int = 0
	for key: int in keys:
		if budget < 24:
			break
		var k: int = key & 0xFFFFF
		var cost: int = rbits[k] + 8
		if cost <= budget:
			chosen[k] = 1
			budget -= cost
			taken += 1
	_rot += taken


## Escribe los paquetes con un acumulador de bits local (el formato es el de SnapshotCodec; aquí
## va en línea porque es el bucle más caliente del servidor). Calcula los campos exactos de lo que
## entra y aplica los topes exactos (1200 B por paquete, 4096 B en total): lo que no entra se
## desmarca y queda aplazado.
func _encode(world: SnapshotWorld, base: SnapshotState, nr: int, now: int, last_seq: int) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
	var rbits := _r_bits
	var rword := _r_word
	var chosen := _r_chosen
	var wid := world.ids
	var ww := world.words
	var wprog := world.prog
	var wdef := world.def_index
	var wown := world.owner
	var bid := base.ids
	var bw := base.words
	var bprog := base.prog
	var hw := BitWriter.new()
	SnapshotCodec.write_header(hw, now, base_tick if base_tick >= 0 else SnapshotCodec.NO_BASE, 0, last_seq)
	var header: PackedByteArray = hw.get_bytes()
	const QM: int = SnapshotCodec.Q_MASK
	const POSM: int = SnapshotCodec.POS_MASK
	const LIM: int = SnapshotCodec.DELTA_LIMIT
	const MAXB: int = SnapshotCodec.MAX_PACKET_BYTES * 8
	const CAP: int = SnapshotCodec.MAX_SNAPSHOT_BYTES
	const F_DELTA: int = SnapshotCodec.FLAG_POS_DELTA
	const F_ABS: int = SnapshotCodec.FLAG_POS_ABS
	const F_HEAD: int = SnapshotCodec.FLAG_HEADING
	const F_HP: int = SnapshotCodec.FLAG_HP
	const F_ACT: int = SnapshotCodec.FLAG_ACTION
	const F_PROG: int = SnapshotCodec.FLAG_PROGRESS
	const F_APPEAR: int = SnapshotCodec.FLAG_APPEAR

	var buf: PackedByteArray = header.duplicate()
	var acc: int = 0
	var nacc: int = 0
	var total: int = 0
	var n_rem: int = 0
	var n_rec: int = 0
	var prev: int = 0
	var removed: int = 0
	var records: int = 0
	var deferred: int = 0
	var cut: int = 0

	# 1) REMOVED (motivo en rbits).
	for k: int in nr:
		if rk[k] != _K_REMOVED or chosen[k] == 0:
			continue
		var id: int = bid[rbi[k]]
		var d: int = id - prev
		var bits: int = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + 1
		if buf.size() * 8 + nacc + bits > MAXB:
			total += _flush_packet(buf, acc, nacc, n_rem, n_rec, packets)
			buf = header.duplicate()
			acc = 0
			nacc = 0
			n_rem = 0
			n_rec = 0
			d = id
			bits = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + 1
		if total + ((buf.size() * 8 + nacc + bits + 7) >> 3) > CAP:
			chosen[k] = 0
			deferred += 1
			cut += 1
			continue
		while d >= 0x80:
			acc |= ((d & 0x7F) | 0x80) << nacc
			nacc += 8
			d >>= 7
		acc |= ((d | (rbits[k] << 8)) & 0x1FF) << nacc
		nacc += 9
		while nacc >= 8:
			buf.append(acc & 0xFF)
			acc >>= 8
			nacc -= 8
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
		var nwd: int = ww[wi]
		var id: int = wid[wi]
		# Campos exactos: máscara, palabra resultante y carga en dos grupos de bits.
		var mask: int
		var res: int
		var g1: int  # máscara [+ delta]
		var g1b: int
		var g2: int  # rumbo, vida, acción, progreso (o el resto de la aparición)
		var g2b: int
		var abs_pos: bool
		if rk[k] == _K_APPEAR:
			res = nwd
			mask = F_APPEAR
			g1 = F_APPEAR | (wdef[wi] << 8) | (wown[wi] << 18)
			g1b = 22
			abs_pos = true
			var action: int = (nwd >> 56) & 0xF
			g2 = ((nwd >> 40) & 0xFF) | (((nwd >> 48) & 0xFF) << 8) | (action << 16)
			g2b = 20
			if SnapshotCodec.action_uses_progress(action):
				g2 |= wprog[wi] << 20
				g2b = 28
		else:
			var bi: int = rbi[k]
			var owd: int = bw[bi]
			var diff: int = nwd ^ owd
			mask = 0
			res = owd
			g1 = 0
			g1b = 8
			abs_pos = false
			if (diff & POSM) != 0:
				var oqx: int = owd & QM
				var oqz: int = (owd >> 20) & QM
				var dx: int = (nwd & QM) - oqx
				var dz: int = ((nwd >> 20) & QM) - oqz
				# Pasos de 0,25 m, redondeando alejándose de cero en los medios.
				var ddx: int = (dx + (1 if dx > 0 else (-1 if dx < 0 else 0))) / 2
				var ddz: int = (dz + (1 if dz > 0 else (-1 if dz < 0 else 0))) / 2
				if ddx >= -LIM and ddx <= LIM and ddz >= -LIM and ddz <= LIM:
					if ddx != 0 or ddz != 0:
						mask = F_DELTA
						g1 = ((ddx & 0xFF) << 8) | ((ddz & 0xFF) << 16)
						g1b = 24
						res = (res & ~POSM) | clampi(oqx + ddx * 2, 0, QM) | (clampi(oqz + ddz * 2, 0, QM) << 20)
				else:
					mask = F_ABS
					abs_pos = true
					res = (res & ~POSM) | (nwd & POSM)
			g2 = 0
			g2b = 0
			if (diff & (0xFF << 40)) != 0:
				mask |= F_HEAD
				g2 = (nwd >> 40) & 0xFF
				g2b = 8
			if (diff & (0xFF << 48)) != 0:
				mask |= F_HP
				g2 |= ((nwd >> 48) & 0xFF) << g2b
				g2b += 8
			if (diff & (0xF << 56)) != 0:
				mask |= F_ACT
				g2 |= ((nwd >> 56) & 0xF) << g2b
				g2b += 4
			if wprog[wi] != bprog[bi] and SnapshotCodec.action_uses_progress((nwd >> 56) & 0xF):
				mask |= F_PROG
				g2 |= wprog[wi] << g2b
				g2b += 8
			res = (res & ~((0xFF << 40) | (0xFF << 48) | (0xF << 56))) | (nwd & ((0xFF << 40) | (0xFF << 48) | (0xF << 56)))
			if mask == 0:
				# Movimiento menor que el paso del delta: el cliente ya está al día.
				rword[k] = owd
				continue
			g1 |= mask
		rword[k] = res
		var d: int = id - prev
		var bits: int = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + g1b + g2b + (40 if abs_pos else 0)
		if buf.size() * 8 + nacc + bits > MAXB:
			total += _flush_packet(buf, acc, nacc, n_rem, n_rec, packets)
			buf = header.duplicate()
			acc = 0
			nacc = 0
			n_rem = 0
			n_rec = 0
			d = id
			bits = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + g1b + g2b + (40 if abs_pos else 0)
		if total + ((buf.size() * 8 + nacc + bits + 7) >> 3) > CAP:
			chosen[k] = 0
			deferred += 1
			cut += 1
			continue
		# id (varint)
		while d >= 0x80:
			acc |= ((d & 0x7F) | 0x80) << nacc
			nacc += 8
			d >>= 7
		acc |= d << nacc
		nacc += 8
		if nacc >= 32:
			while nacc >= 8:
				buf.append(acc & 0xFF)
				acc >>= 8
				nacc -= 8
		# máscara [+ delta] (como mucho 24 bits; aquí nacc < 32)
		acc |= g1 << nacc
		nacc += g1b
		while nacc >= 8:
			buf.append(acc & 0xFF)
			acc >>= 8
			nacc -= 8
		if abs_pos:
			acc |= (nwd & QM) << nacc
			nacc += 20
			acc |= ((nwd >> 20) & QM) << nacc
			nacc += 20
			while nacc >= 8:
				buf.append(acc & 0xFF)
				acc >>= 8
				nacc -= 8
		if g2b > 0:
			acc |= g2 << nacc
			nacc += g2b
			while nacc >= 8:
				buf.append(acc & 0xFF)
				acc >>= 8
				nacc -= 8
		prev = id
		n_rec += 1
		records += 1
	total += _flush_packet(buf, acc, nacc, n_rem, n_rec, packets)

	# Número de partes e índice de cada una (bytes alineados de la cabecera).
	var pc_byte: int = SnapshotCodec.PART_COUNT_BIT >> 3
	for pi: int in packets.size():
		packets[pi][pc_byte - 1] = pi
		packets[pi][pc_byte] = packets.size()
	if cut > 0:
		_slack_bytes = mini(_slack_bytes + 32 + cut * 8, _SLACK_MAX)
	else:
		_slack_bytes = maxi(_slack_bytes - 2, _SLACK_MIN)
	last_cap_cuts = cut
	last_max_packet_bytes = 0
	for p: PackedByteArray in packets:
		last_max_packet_bytes = maxi(last_max_packet_bytes, p.size())
	last_bytes = total
	last_packets = packets.size()
	last_records = records
	last_removed = removed
	last_deferred = deferred
	total_bytes += total
	return packets


## Cierra un paquete: vuelca los bits pendientes y escribe los contadores en la cabecera.
func _flush_packet(buf: PackedByteArray, acc: int, nacc: int, n_rem: int, n_rec: int, packets: Array[PackedByteArray]) -> int:
	var a: int = acc
	var n: int = nacc
	while n > 0:
		buf.append(a & 0xFF)
		a >>= 8
		n -= 8
	var rb: int = SnapshotCodec.REMOVED_COUNT_BIT >> 3
	var cb: int = SnapshotCodec.RECORD_COUNT_BIT >> 3
	buf[rb] = n_rem & 0xFF
	buf[rb + 1] = (n_rem >> 8) & 0xFF
	buf[cb] = n_rec & 0xFF
	buf[cb + 1] = (n_rec >> 8) & 0xFF
	packets.append(buf)
	return buf.size()


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
