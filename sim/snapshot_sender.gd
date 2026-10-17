class_name SnapshotSender
extends RefCounted
## Armado de snapshots para UN cliente (ADR-006 punto 5 y su enmienda de dead reckoning, T-005):
## delta contra el último snapshot que el cliente confirmó con ack, lista REMOVED explícita, tope
## de 4 KB con prioridad y paquetes de <= 1200 B decodificables por separado.
##
## Dead reckoning: lo que el cliente tiene de cada entidad es una trayectoria (posición, velocidad
## y tick de referencia; SnapshotState). Una entidad solo se envía si el error entre su posición
## real y la que el cliente predice desde la base supera SnapshotCodec.DR_THRESHOLD_Q (0,5 m), si
## cambió su velocidad cuantizada, su rumbo, vida, acción o progreso, o como refresco de seguridad
## cada DR_REFRESH_TICKS (10 s). Enviarla la "reancla": posición (delta contra la posición que el
## cliente predice) + velocidad, con referencia en este tick.
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
## por error previsto x antigüedad, con el doble para las entidades en combate. Un cambio de
## velocidad, rumbo, vida o acción pesa como un error de 2 m. Los empates rotan entre snapshots
## para repartir lo aplazado.
## Antigüedad = ticks desde que la copia del cliente estaba "al día": posición predicha dentro del
## umbral y vida, acción y progreso iguales. Un cambio de velocidad o de rumbo que todavía no
## llegó no la deja desactualizada mientras el error siga dentro del umbral (la velocidad nueva se
## nota en la posición recién cuando el error crece, y entonces cuenta).

const RING_SIZE: int = 32
const ACK_TIMEOUT_TICKS: int = SimConstants.TICK_RATE
const _AGE_CAP: int = 1023
## Tope del error al cuadrado (en pasos de 0,125 m) dentro de la prioridad: 4 m.
const _ERR2_CAP: int = 1024
## Peso de un cambio discreto: como un error de 2 m.
const _DISCRETE_ERR2: int = 256
const _PRIO_APPEAR: int = (1 << 22) + 1
## Error al cuadrado (pasos de 0,125 m) hasta el que un reanclaje usa la posición predicha sin
## mandar posición (SnapshotCodec.FLAG_POS_PREDICTED): la mitad del umbral (0,25 m).
const _PRED_ANCHOR_ERR2: int = (SnapshotCodec.DR_THRESHOLD_Q / 2) * (SnapshotCodec.DR_THRESHOLD_Q / 2)
const _K_UPDATE: int = 0
const _K_APPEAR: int = 1
const _K_REMOVED: int = 2
## Partes que se reservan en el presupuesto (cabeceras) al elegir qué entra.
const _BUDGET_PARTS: int = (SnapshotCodec.MAX_SNAPSHOT_BYTES + SnapshotCodec.MAX_PACKET_BYTES - 1) / SnapshotCodec.MAX_PACKET_BYTES
const _SLACK_MIN: int = 32
const _SLACK_MAX: int = 768

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
## Máxima antigüedad (ticks) entre las entidades en combate desactualizadas en el cliente (error
## previsto fuera del umbral, o vida/acción/progreso pendientes).
var last_max_combat_age: int = 0
## Máximo error previsto (pasos de 0,125 m) entre las entidades visibles, antes de enviar.
var last_max_error_q: int = 0
var full_resets: int = 0
## true si tras el último build() el cliente conoce exactamente las entidades que ve (no quedaron
## apariciones ni bajas aplazadas por el tope).
var last_synced: bool = false
## Registros elegidos que el tope exacto tuvo que recortar en el último build().
var last_cap_cuts: int = 0
var total_bytes: int = 0
var snapshots_sent: int = 0

## Margen del presupuesto (bytes) para lo que la estimación no ve (ids que ocupan 2 B, primer id
## de cada paquete, final de paquete). Es adaptativo: crece si el tope exacto tuvo que recortar y
## baja de a poco si no; así el recorte (que va en orden de id, no de prioridad) casi nunca ocurre
## y no deja siempre afuera a los mismos ids altos.
var _slack_bytes: int = 64
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
var _r_vel := PackedInt32Array()
var _r_ref := PackedInt32Array()
var _r_anchor := PackedByteArray()
## 1 si la copia del cliente está desactualizada (ver la antigüedad arriba).
var _r_stale := PackedByteArray()
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


## Recorre en orden de id el mundo y la base, y anota los registros (apariciones, reanclajes,
## cambios discretos y bajas) con su prioridad y una estimación de su tamaño. Los campos exactos
## se calculan en _encode, solo para lo que entra. Devuelve la cantidad de registros.
func _merge(world: SnapshotWorld, base: SnapshotState, now: int) -> int:
	var nw: int = world.count
	var nb: int = base.ids.size()
	var cap: int = nw + nb
	if _r_kind.size() < cap:
		_r_kind.resize(cap)
		_r_wi.resize(cap)
		_r_bi.resize(cap)
		_r_word.resize(cap)
		_r_vel.resize(cap)
		_r_ref.resize(cap)
		_r_anchor.resize(cap)
		_r_stale.resize(cap)
		_r_bits.resize(cap)
		_r_prio.resize(cap)
		_r_chosen.resize(cap)
	var rk := _r_kind
	var rwi := _r_wi
	var rbi := _r_bi
	var ranchor := _r_anchor
	var rstale := _r_stale
	var rbits := _r_bits
	var rprio := _r_prio
	var wid := world.ids
	var ww := world.words
	var wvel := world.vel
	var wprog := world.prog
	var wvis := world.vis
	var wown := world.owner
	var wcombat := world.combat
	var bid := base.ids
	var bw := base.words
	var bvel := base.vel
	var bref := base.ref
	var bprog := base.prog
	var bfresh := base.fresh
	var pid: int = player_id
	var pbit: int = 1 << pid
	var max_age: int = 0
	var max_err2: int = 0
	const BIG: int = 0x7FFFFFFF
	const QM: int = SnapshotCodec.Q_MASK
	const DISC: int = (0xFF << 40) | (0xFF << 48) | (0xF << 56)
	const TH2: int = SnapshotCodec.DR_THRESHOLD_Q2
	const REFRESH: int = SnapshotCodec.DR_REFRESH_TICKS
	const VT: int = SnapshotCodec.VEL_TICKS_PER_QUANTUM
	const VTH: int = SnapshotCodec.VEL_TICKS_PER_QUANTUM / 2
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
				var nwd: int = ww[i]
				var owd: int = bw[j]
				var nv: int = wvel[i]
				var ov: int = bvel[j]
				var dt: int = now - bref[j]
				# Posición que predice el cliente (SnapshotCodec.predict_q en línea).
				var vx: int = ov & 0xFF
				if vx >= 128:
					vx -= 256
				var vz: int = (ov >> 8) & 0xFF
				if vz >= 128:
					vz -= 256
				var n: int = vx * dt
				var px: int = clampi((owd & QM) + (n + (VTH if n >= 0 else -VTH)) / VT, 0, QM)
				n = vz * dt
				var pz: int = clampi(((owd >> 20) & QM) + (n + (VTH if n >= 0 else -VTH)) / VT, 0, QM)
				var ex: int = (nwd & QM) - px
				var ez: int = ((nwd >> 20) & QM) - pz
				var err2: int = ex * ex + ez * ez
				if err2 > max_err2:
					max_err2 = err2
				var disc: int = (nwd ^ owd) & DISC
				var prog_changed: bool = wprog[i] != bprog[j] and SnapshotCodec.action_uses_progress((nwd >> 56) & 0xF)
				var vel_changed: bool = nv != ov
				var off: bool = err2 > TH2
				var anchor: bool = off or vel_changed or dt >= REFRESH
				if anchor or disc != 0 or prog_changed:
					var bits: int = 8
					if anchor:
						# Si el error es chico se reancla en la posición predicha (solo velocidad).
						bits += 16 if err2 <= _PRED_ANCHOR_ERR2 else 32
					if disc & (0xFF << 40):
						bits += 8
					if disc & (0xFF << 48):
						bits += 8
					if disc & (0xF << 56):
						bits += 4
					if prog_changed:
						bits += 8
					var e: int = mini(err2, _ERR2_CAP) if off else 0
					var changed: bool = vel_changed or disc != 0 or prog_changed
					if changed:
						e += _DISCRETE_ERR2
					if e == 0:
						e = 1  # solo refresco de seguridad
					var stale: bool = off or (disc & ((0xFF << 48) | (0xF << 56))) != 0 or prog_changed
					var age: int = clampi(now - bfresh[j], 1, _AGE_CAP)
					if wcombat[i] != 0:
						if stale:
							max_age = maxi(max_age, now - bfresh[j])
						e *= 2
					rk[nr] = _K_UPDATE
					rwi[nr] = i
					rbi[nr] = j
					ranchor[nr] = 1 if anchor else 0
					rstale[nr] = 1 if stale else 0
					rbits[nr] = bits
					rprio[nr] = e * age
					nr += 1
			i += 1
			j += 1
		elif a < b:
			if (wvis[i] & pbit) != 0 or wown[i] == pid:
				rk[nr] = _K_APPEAR
				rwi[nr] = i
				rbi[nr] = -1
				ranchor[nr] = 1
				rbits[nr] = SnapshotCodec.appear_bits((ww[i] >> 56) & 0xF)
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
	last_max_error_q = int(sqrt(float(max_err2)))
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
	var rvel := _r_vel
	var rref := _r_ref
	var ranchor := _r_anchor
	var chosen := _r_chosen
	var wid := world.ids
	var ww := world.words
	var wvel := world.vel
	var wprog := world.prog
	var wdef := world.def_index
	var wown := world.owner
	var bid := base.ids
	var bw := base.words
	var bvel := base.vel
	var bref := base.ref
	var bprog := base.prog
	var hw := BitWriter.new()
	SnapshotCodec.write_header(hw, now, base_tick if base_tick >= 0 else SnapshotCodec.NO_BASE, 0, last_seq)
	var header: PackedByteArray = hw.get_bytes()
	const QM: int = SnapshotCodec.Q_MASK
	const POSM: int = SnapshotCodec.POS_MASK
	const DISC: int = (0xFF << 40) | (0xFF << 48) | (0xF << 56)
	const LIM: int = SnapshotCodec.DELTA_LIMIT
	const VT: int = SnapshotCodec.VEL_TICKS_PER_QUANTUM
	const VTH: int = SnapshotCodec.VEL_TICKS_PER_QUANTUM / 2
	const MAXB: int = SnapshotCodec.MAX_PACKET_BYTES * 8
	const CAP: int = SnapshotCodec.MAX_SNAPSHOT_BYTES
	const F_DELTA: int = SnapshotCodec.FLAG_POS_DELTA
	const F_ABS: int = SnapshotCodec.FLAG_POS_ABS
	const F_PRED: int = SnapshotCodec.FLAG_POS_PREDICTED
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
	# Apariciones o bajas que no entraron: el conjunto de entidades del cliente todavía no es el
	# que ve (sin ellas, la cabecera lleva SYNCED_FLAG).
	var set_pending: int = 0

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
			set_pending += 1
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
			if rk[k] == _K_APPEAR:
				set_pending += 1
			continue
		var wi: int = rwi[k]
		var nwd: int = ww[wi]
		var nv: int = wvel[wi]
		var id: int = wid[wi]
		var anchor: bool = ranchor[k] != 0
		# Campos exactos: palabra resultante y carga en grupos de bits.
		var res: int
		var g1: int  # máscara [+ delta] (o máscara + def + dueño en una aparición)
		var g1b: int
		var abs_pos: bool
		var g2: int  # rumbo, vida, acción, progreso
		var g2b: int
		if rk[k] == _K_APPEAR:
			res = nwd
			g1 = F_APPEAR | (wdef[wi] << 8) | (wown[wi] << 18)
			g1b = 22
			abs_pos = true
			var action: int = (nwd >> 56) & 0xF
			g2 = ((nwd >> 40) & 0xFF) | (((nwd >> 48) & 0xFF) << 8) | (action << 16)
			g2b = 20
			if SnapshotCodec.action_uses_progress(action):
				g2 |= wprog[wi] << 20
				g2b = 28
			rvel[k] = nv
			rref[k] = now
		else:
			var bi: int = rbi[k]
			var owd: int = bw[bi]
			var mask: int = 0
			res = owd
			g1 = 0
			g1b = 8
			abs_pos = false
			if anchor:
				var ov: int = bvel[bi]
				var dt: int = now - bref[bi]
				var vx: int = ov & 0xFF
				if vx >= 128:
					vx -= 256
				var vz: int = (ov >> 8) & 0xFF
				if vz >= 128:
					vz -= 256
				var n: int = vx * dt
				var px: int = clampi((owd & QM) + (n + (VTH if n >= 0 else -VTH)) / VT, 0, QM)
				n = vz * dt
				var pz: int = clampi(((owd >> 20) & QM) + (n + (VTH if n >= 0 else -VTH)) / VT, 0, QM)
				var dx: int = (nwd & QM) - px
				var dz: int = ((nwd >> 20) & QM) - pz
				# Pasos de 0,25 m, redondeando alejándose de cero en los medios.
				var ddx: int = (dx + (1 if dx > 0 else (-1 if dx < 0 else 0))) / 2
				var ddz: int = (dz + (1 if dz > 0 else (-1 if dz < 0 else 0))) / 2
				if dx * dx + dz * dz <= _PRED_ANCHOR_ERR2:
					# Reanclaje en la posición predicha: solo viaja la velocidad.
					mask = F_PRED
					res = (res & ~POSM) | px | (pz << 20)
				elif ddx >= -LIM and ddx <= LIM and ddz >= -LIM and ddz <= LIM:
					mask = F_DELTA
					g1 = ((ddx & 0xFF) << 8) | ((ddz & 0xFF) << 16)
					g1b = 24
					res = (res & ~POSM) | clampi(px + ddx * 2, 0, QM) | (clampi(pz + ddz * 2, 0, QM) << 20)
				else:
					mask = F_ABS
					abs_pos = true
					res = (res & ~POSM) | (nwd & POSM)
				rvel[k] = nv
				rref[k] = now
			else:
				rvel[k] = bvel[bi]
				rref[k] = bref[bi]
			var diff: int = nwd ^ owd
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
			res = (res & ~DISC) | (nwd & DISC)
			if mask == 0:
				rword[k] = owd
				continue
			g1 |= mask
		rword[k] = res
		var d: int = id - prev
		var extra: int = g1b + g2b + (40 if abs_pos else 0) + (16 if anchor else 0)
		var bits: int = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + extra
		if buf.size() * 8 + nacc + bits > MAXB:
			total += _flush_packet(buf, acc, nacc, n_rem, n_rec, packets)
			buf = header.duplicate()
			acc = 0
			nacc = 0
			n_rem = 0
			n_rec = 0
			d = id
			bits = (8 if d < 0x80 else (16 if d < 0x4000 else 32)) + extra
		if total + ((buf.size() * 8 + nacc + bits + 7) >> 3) > CAP:
			chosen[k] = 0
			deferred += 1
			cut += 1
			if rk[k] == _K_APPEAR:
				set_pending += 1
			continue
		# id (varint)
		while d >= 0x80:
			acc |= ((d & 0x7F) | 0x80) << nacc
			nacc += 8
			d >>= 7
		acc |= d << nacc
		nacc += 8
		while nacc >= 8:
			buf.append(acc & 0xFF)
			acc >>= 8
			nacc -= 8
		# máscara [+ delta] (como mucho 24 bits; aquí nacc < 8)
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
		if anchor:
			acc |= nv << nacc
			nacc += 16
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
		packets[pi][pc_byte] = packets.size() | (SnapshotCodec.SYNCED_FLAG if set_pending == 0 else 0)
	last_synced = set_pending == 0
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
	var rvel := _r_vel
	var rref := _r_ref
	var rstale := _r_stale
	var chosen := _r_chosen
	var wid := world.ids
	var wprog := world.prog
	var bid := base.ids
	var bw := base.words
	var bvel := base.vel
	var bref := base.ref
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
	var sv := st.vel
	var sr := st.ref
	var sp := st.prog
	var sf := st.fresh
	var o: int = 0
	var j: int = 0
	for k: int in nr:
		var kind: int = rk[k]
		var rid: int = wid[rwi[k]] if kind == _K_APPEAR else bid[rbi[k]]
		# Lo que está en la base y no tiene registro: dentro del umbral y sin cambios -> al día.
		while j < nb and bid[j] < rid:
			sid[o] = bid[j]
			sw[o] = bw[j]
			sv[o] = bvel[j]
			sr[o] = bref[j]
			sp[o] = bprog[j]
			sf[o] = now
			o += 1
			j += 1
		if kind == _K_APPEAR:
			if chosen[k] != 0:
				sid[o] = rid
				sw[o] = rword[k]
				sv[o] = rvel[k]
				sr[o] = rref[k]
				sp[o] = wprog[rwi[k]]
				sf[o] = now
				o += 1
			continue
		if kind == _K_UPDATE and chosen[k] != 0:
			sid[o] = rid
			sw[o] = rword[k]
			sv[o] = rvel[k]
			sr[o] = rref[k]
			sp[o] = wprog[rwi[k]]
			sf[o] = now
			o += 1
		elif kind == _K_UPDATE or chosen[k] == 0:
			# Cambio aplazado o baja que no entró: el cliente sigue con la base. Si solo cambió
			# la velocidad o el rumbo y el error sigue en el umbral, la copia sigue al día.
			sid[o] = bid[j]
			sw[o] = bw[j]
			sv[o] = bvel[j]
			sr[o] = bref[j]
			sp[o] = bprog[j]
			sf[o] = now if kind == _K_UPDATE and rstale[k] == 0 else bfresh[j]
			o += 1
		j += 1
	while j < nb:
		sid[o] = bid[j]
		sw[o] = bw[j]
		sv[o] = bvel[j]
		sr[o] = bref[j]
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
