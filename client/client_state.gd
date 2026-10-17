class_name ClientState
extends RefCounted
## Estado de las entidades en el cliente, en arrays (SoA, ADR-006 punto 6): no hay un nodo ni un
## objeto por entidad. Lo llena MatchClient con las partes de snapshot que llegan; las vistas
## (T-017) leen render_x/render_z/render_heading por slot después de interpolate().
##
## Dead reckoning (enmienda de ADR-006, T-005): de cada entidad se guardan las dos últimas
## trayectorias recibidas (posición en el tick ref, velocidad y rumbo). El dibujo va con un retraso
## fijo (MatchClient: 200 ms); en el instante de dibujo t se usa la trayectoria más nueva cuyo ref
## sea <= t (o la anterior si todavía no se llegó a la nueva) y se extrapola: p = p_ref + v·(t-ref).
## Al cambiar de trayectoria (porque llegó una nueva o porque el instante de dibujo la alcanzó), la
## diferencia de posición se guarda como una corrección que se desvanece en ~CORRECTION_TIME, para
## que la unidad no salte. Si la corrección supera SNAP_DISTANCE se descarta (teletransporte).

const CORRECTION_TIME: float = 0.15
const SNAP_DISTANCE: float = 20.0

var count: int = 0
var ids := PackedInt32Array()
var def_index := PackedInt32Array()
var owner := PackedInt32Array()
var action := PackedInt32Array()
## Vida como fracción de max_hp (0..1).
var hp_ratio := PackedFloat32Array()
var progress := PackedFloat32Array()
## Resultado de interpolate(): posición en metros (plano x, z) y rumbo en radianes.
var render_x := PackedFloat64Array()
var render_z := PackedFloat64Array()
var render_heading := PackedFloat32Array()

# Trayectorias: slot * 2 + 0 = la anterior, slot * 2 + 1 = la más nueva.
var _tr_t := PackedInt32Array()
var _tr_x := PackedFloat64Array()
var _tr_z := PackedFloat64Array()
var _tr_vx := PackedFloat32Array()
var _tr_vz := PackedFloat32Array()
var _tr_h := PackedFloat32Array()
## Trayectorias válidas por slot (1 o 2).
var _tr_n := PackedInt32Array()
## ref de la trayectoria que se usó en el último dibujo.
var _sel := PackedInt32Array()
var _corr_x := PackedFloat64Array()
var _corr_z := PackedFloat64Array()
var _last_render_tick: float = -1.0
## Tick del último registro aplicado a cada slot (para no borrar en reconcile() lo que llegó en
## partes más nuevas que el estado completo).
var _touch := PackedInt32Array()
## id -> slot (-1 = no está).
var _id_to_slot := PackedInt32Array()


func slot_of(id: int) -> int:
	if id <= 0 or id >= _id_to_slot.size():
		return -1
	return _id_to_slot[id]


## Aplica una parte de snapshot (ya decodificada por SnapshotReceiver).
func apply_part(p: SnapshotCodec.Part) -> void:
	for id: int in p.removed_ids:
		remove(id)
	const VS: float = SnapshotCodec.VEL_STEP
	for i: int in p.rec_ids.size():
		var id: int = p.rec_ids[i]
		var s: int = slot_of(id)
		var w: int = p.rec_words[i]
		var v: int = p.rec_vel[i]
		var ref: int = p.rec_ref[i]
		var x: float = MapGrid.dequantize(w & SnapshotCodec.Q_MASK)
		var z: float = MapGrid.dequantize((w >> SnapshotCodec.QZ_SHIFT) & SnapshotCodec.Q_MASK)
		var vx: float = SnapshotCodec.vel_x8(v) * VS
		var vz: float = SnapshotCodec.vel_z8(v) * VS
		var h: float = SnapshotCodec.dequantize_heading(SnapshotCodec.word_heading8(w))
		if s < 0:
			if p.rec_def[i] < 0 or id <= 0 or id > SimConstants.MAX_ENTITY_ID:
				continue  # entidad sin datos de aparición o id fuera de rango (no debería pasar)
			s = _add(id, p.rec_def[i], p.rec_owner[i])
			_set_traj(s * 2 + 1, ref, x, z, vx, vz, h)
			_tr_n[s] = 1
			_sel[s] = ref
			_corr_x[s] = 0.0
			_corr_z[s] = 0.0
			render_x[s] = x
			render_z[s] = z
			render_heading[s] = h
		else:
			var b: int = s * 2 + 1
			var tb: int = _tr_t[b]
			if ref > tb:
				# Nueva trayectoria: la diferencia en el último instante dibujado pasa a corrección.
				var have_render: bool = _last_render_tick >= 0.0
				var before := _pos_at(s, _last_render_tick, true) if have_render else Vector2.ZERO
				_set_traj(b - 1, tb, _tr_x[b], _tr_z[b], _tr_vx[b], _tr_vz[b], _tr_h[b])
				_set_traj(b, ref, x, z, vx, vz, h)
				_tr_n[s] = 2
				if have_render:
					var c := before - _pos_at(s, _last_render_tick, false)
					if c.length() > SNAP_DISTANCE:
						c = Vector2.ZERO
					_corr_x[s] = c.x
					_corr_z[s] = c.y
					_sel[s] = _tr_t[_pick(s, _last_render_tick)]
			elif ref == tb:
				_tr_h[b] = h  # cambio de rumbo sin reanclar la posición
		_touch[s] = maxi(_touch[s], p.tick)
		action[s] = SnapshotCodec.word_action(w)
		hp_ratio[s] = SnapshotCodec.dequantize_hp(SnapshotCodec.word_hp8(w))
		progress[s] = p.rec_prog[i] / 255.0


func remove(id: int) -> void:
	var s: int = slot_of(id)
	if s < 0:
		return
	var last: int = count - 1
	if s != last:
		ids[s] = ids[last]
		def_index[s] = def_index[last]
		owner[s] = owner[last]
		action[s] = action[last]
		hp_ratio[s] = hp_ratio[last]
		progress[s] = progress[last]
		render_x[s] = render_x[last]
		render_z[s] = render_z[last]
		render_heading[s] = render_heading[last]
		for k: int in 2:
			var o: int = last * 2 + k
			_set_traj(s * 2 + k, _tr_t[o], _tr_x[o], _tr_z[o], _tr_vx[o], _tr_vz[o], _tr_h[o])
		_tr_n[s] = _tr_n[last]
		_sel[s] = _sel[last]
		_touch[s] = _touch[last]
		_corr_x[s] = _corr_x[last]
		_corr_z[s] = _corr_z[last]
		_id_to_slot[ids[s]] = s
	_id_to_slot[id] = -1
	count = last


## Borra las entidades que no están en `st` (el estado completo del tick `tick`, ver
## SnapshotReceiver.reconcile_tick), salvo las que recibieron datos de un snapshot más nuevo.
## Devuelve cuántas borró.
func reconcile(st: SnapshotState, tick: int) -> int:
	var removed: int = 0
	var s: int = count - 1
	while s >= 0:
		if _touch[s] <= tick and st.index_of(ids[s]) < 0:
			remove(ids[s])
			removed += 1
		s -= 1
	return removed


## Ancla de la trayectoria más nueva: Vector3(x, z, tick ref).
func latest_sample(s: int) -> Vector3:
	var b: int = s * 2 + 1
	return Vector3(_tr_x[b], _tr_z[b], _tr_t[b])


## Posición que predice el dead reckoning en `tick` (sin la corrección visual).
func predicted(s: int, tick: float) -> Vector2:
	return _pos_at(s, tick, false)


## Calcula render_x/z/heading para el instante `render_tick` (en ticks del servidor, con
## decimales).
func interpolate(render_tick: float) -> void:
	var dtr: float = render_tick - _last_render_tick if _last_render_tick >= 0.0 else 0.0
	_last_render_tick = render_tick
	const DT: float = SimConstants.TICK_DT
	var decay: float = exp(-maxf(dtr, 0.0) * DT / CORRECTION_TIME)
	var tt := _tr_t
	var tx := _tr_x
	var tz := _tr_z
	var tvx := _tr_vx
	var tvz := _tr_vz
	var th := _tr_h
	var tn := _tr_n
	var sel := _sel
	var cx := _corr_x
	var cz := _corr_z
	var rx := render_x
	var rz := render_z
	var rh := render_heading
	const SNAP2: float = SNAP_DISTANCE * SNAP_DISTANCE
	for s: int in count:
		var b: int = s * 2 + 1
		var use: int = b
		if tn[s] == 2 and render_tick < tt[b]:
			use = b - 1
		if tt[use] != sel[s]:
			# El instante de dibujo alcanzó la trayectoria nueva: suavizar el cambio.
			var other: int = b - 1 if use == b else b
			if tt[other] == sel[s]:
				var dto: float = maxf(render_tick - tt[other], 0.0) * DT
				var dtu: float = maxf(render_tick - tt[use], 0.0) * DT
				var ox: float = tx[other] + tvx[other] * dto - tx[use] - tvx[use] * dtu
				var oz: float = tz[other] + tvz[other] * dto - tz[use] - tvz[use] * dtu
				if ox * ox + oz * oz <= SNAP2:
					cx[s] += ox
					cz[s] += oz
			sel[s] = tt[use]
		var dt: float = maxf(render_tick - tt[use], 0.0) * DT
		cx[s] *= decay
		cz[s] *= decay
		rx[s] = tx[use] + tvx[use] * dt + cx[s]
		rz[s] = tz[use] + tvz[use] * dt + cz[s]
		rh[s] = th[use]


## Índice de la trayectoria que corresponde al instante t.
func _pick(s: int, t: float) -> int:
	var b: int = s * 2 + 1
	if _tr_n[s] == 2 and t < _tr_t[b]:
		return b - 1
	return b


func _pos_at(s: int, t: float, with_corr: bool) -> Vector2:
	var u: int = _pick(s, t)
	var dt: float = maxf(t - _tr_t[u], 0.0) * SimConstants.TICK_DT
	var out := Vector2(_tr_x[u] + _tr_vx[u] * dt, _tr_z[u] + _tr_vz[u] * dt)
	if with_corr:
		out += Vector2(_corr_x[s], _corr_z[s])
	return out


func _set_traj(i: int, t: int, x: float, z: float, vx: float, vz: float, h: float) -> void:
	_tr_t[i] = t
	_tr_x[i] = x
	_tr_z[i] = z
	_tr_vx[i] = vx
	_tr_vz[i] = vz
	_tr_h[i] = h


func _add(id: int, p_def: int, p_owner: int) -> int:
	var s: int = count
	count += 1
	if ids.size() < count:
		var cap: int = maxi(64, count * 2)
		ids.resize(cap)
		def_index.resize(cap)
		owner.resize(cap)
		action.resize(cap)
		hp_ratio.resize(cap)
		progress.resize(cap)
		render_x.resize(cap)
		render_z.resize(cap)
		render_heading.resize(cap)
		_tr_t.resize(cap * 2)
		_tr_x.resize(cap * 2)
		_tr_z.resize(cap * 2)
		_tr_vx.resize(cap * 2)
		_tr_vz.resize(cap * 2)
		_tr_h.resize(cap * 2)
		_tr_n.resize(cap)
		_sel.resize(cap)
		_touch.resize(cap)
		_corr_x.resize(cap)
		_corr_z.resize(cap)
	if id >= _id_to_slot.size():
		var old: int = _id_to_slot.size()
		_id_to_slot.resize(maxi(id + 1, old * 2))
		for i: int in range(old, _id_to_slot.size()):
			_id_to_slot[i] = -1
	ids[s] = id
	def_index[s] = p_def
	owner[s] = p_owner
	_touch[s] = 0
	_id_to_slot[id] = s
	return s
