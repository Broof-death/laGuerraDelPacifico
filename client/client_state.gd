class_name ClientState
extends RefCounted
## Estado de las entidades en el cliente, en arrays (SoA, ADR-006 punto 6): no hay un nodo ni un
## objeto por entidad. Lo llena MatchClient con las partes de snapshot que llegan y lo interpola
## con un retraso fijo; las vistas (T-017) leen render_x/render_z/render_heading por slot.
##
## Interpolación: cada slot guarda sus últimas SAMPLES muestras (tick del servidor, x, z, rumbo).
## Con 200 ms de retraso y snapshots cada 100 ms hacen falta al menos 3 muestras para tener
## siempre un par que rodee al instante de dibujo, así que se guardan 4 (ADR-006 decía "los dos
## últimos estados"; con dos el retraso no se podría cubrir).
## Si el instante de dibujo pasa la última muestra (entidad aplazada por el tope de 4 KB), se
## extrapola con la última velocidad hasta EXTRAPOLATE_TICKS (300 ms) y después queda quieta.

const SAMPLES: int = 4
const EXTRAPOLATE_TICKS: float = 6.0

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

# Muestras: slot * SAMPLES + k, en anillo; _smp_head[slot] es la próxima posición a escribir.
var _smp_tick := PackedInt32Array()
var _smp_x := PackedFloat64Array()
var _smp_z := PackedFloat64Array()
var _smp_h := PackedFloat32Array()
var _smp_n := PackedInt32Array()
var _smp_head := PackedInt32Array()
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
	var tick: int = p.tick
	for i: int in p.rec_ids.size():
		var id: int = p.rec_ids[i]
		var s: int = slot_of(id)
		if s < 0:
			if p.rec_def[i] < 0:
				continue  # entidad sin datos de aparición (no debería pasar)
			s = _add(id, p.rec_def[i], p.rec_owner[i])
		var w: int = p.rec_words[i]
		action[s] = SnapshotCodec.word_action(w)
		hp_ratio[s] = SnapshotCodec.dequantize_hp(SnapshotCodec.word_hp8(w))
		progress[s] = p.rec_prog[i] / 255.0
		_push_sample(s, tick, MapGrid.dequantize(SnapshotCodec.word_qx(w)),
				MapGrid.dequantize(SnapshotCodec.word_qz(w)),
				SnapshotCodec.dequantize_heading(SnapshotCodec.word_heading8(w)))


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
		for k: int in SAMPLES:
			_smp_tick[s * SAMPLES + k] = _smp_tick[last * SAMPLES + k]
			_smp_x[s * SAMPLES + k] = _smp_x[last * SAMPLES + k]
			_smp_z[s * SAMPLES + k] = _smp_z[last * SAMPLES + k]
			_smp_h[s * SAMPLES + k] = _smp_h[last * SAMPLES + k]
		_smp_n[s] = _smp_n[last]
		_smp_head[s] = _smp_head[last]
		_id_to_slot[ids[s]] = s
	_id_to_slot[id] = -1
	count = last


## Última muestra recibida de un slot: Vector3(x, z, tick).
func latest_sample(s: int) -> Vector3:
	var k: int = (_smp_head[s] + SAMPLES - 1) % SAMPLES
	var i: int = s * SAMPLES + k
	return Vector3(_smp_x[i], _smp_z[i], _smp_tick[i])


## Calcula render_x/z/heading para el instante `render_tick` (en ticks del servidor, con
## decimales).
func interpolate(render_tick: float) -> void:
	var st := _smp_tick
	var sx := _smp_x
	var sz := _smp_z
	var sh := _smp_h
	var rx := render_x
	var rz := render_z
	var rh := render_heading
	for s: int in count:
		var n: int = _smp_n[s]
		var head: int = _smp_head[s]
		var base: int = s * SAMPLES
		var newest: int = base + (head + SAMPLES - 1) % SAMPLES
		if n == 1 or render_tick <= st[base + (head + SAMPLES - n) % SAMPLES]:
			# Una sola muestra, o el instante es anterior a todas: la más vieja disponible.
			var oldest: int = base + (head + SAMPLES - n) % SAMPLES
			rx[s] = sx[oldest]
			rz[s] = sz[oldest]
			rh[s] = sh[oldest]
			continue
		if render_tick >= st[newest]:
			# Extrapolación con la última velocidad, como mucho EXTRAPOLATE_TICKS.
			var prev: int = base + (head + SAMPLES - 2) % SAMPLES
			var span: float = st[newest] - st[prev]
			var ahead: float = minf(render_tick - st[newest], EXTRAPOLATE_TICKS)
			var f: float = ahead / span if span > 0.0 else 0.0
			rx[s] = sx[newest] + (sx[newest] - sx[prev]) * f
			rz[s] = sz[newest] + (sz[newest] - sz[prev]) * f
			rh[s] = sh[newest]
			continue
		# Buscar el par (a, b) con t_a <= render_tick < t_b, de la más nueva hacia atrás.
		for k: int in range(1, n):
			var a: int = base + (head + SAMPLES - 1 - k) % SAMPLES
			if st[a] <= render_tick:
				var b: int = base + (head + SAMPLES - k) % SAMPLES
				var t: float = (render_tick - st[a]) / float(st[b] - st[a])
				rx[s] = lerpf(sx[a], sx[b], t)
				rz[s] = lerpf(sz[a], sz[b], t)
				rh[s] = lerp_angle(sh[a], sh[b], t)
				break


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
		_smp_tick.resize(cap * SAMPLES)
		_smp_x.resize(cap * SAMPLES)
		_smp_z.resize(cap * SAMPLES)
		_smp_h.resize(cap * SAMPLES)
		_smp_n.resize(cap)
		_smp_head.resize(cap)
	if id >= _id_to_slot.size():
		var old: int = _id_to_slot.size()
		_id_to_slot.resize(maxi(id + 1, old * 2))
		for i: int in range(old, _id_to_slot.size()):
			_id_to_slot[i] = -1
	ids[s] = id
	def_index[s] = p_def
	owner[s] = p_owner
	_smp_n[s] = 0
	_smp_head[s] = 0
	_id_to_slot[id] = s
	return s


func _push_sample(s: int, tick: int, x: float, z: float, h: float) -> void:
	var n: int = _smp_n[s]
	if n > 0:
		var li: int = s * SAMPLES + (_smp_head[s] + SAMPLES - 1) % SAMPLES
		var last_tick: int = _smp_tick[li]
		if tick <= last_tick:
			return
		# Si la entidad no se actualizaba desde hace más de un intervalo, estaba quieta hasta el
		# snapshot anterior: se agrega esa muestra para no deslizarla desde el pasado.
		var gap_tick: int = tick - SimConstants.SNAPSHOT_EVERY_TICKS
		if last_tick < gap_tick:
			_write_sample(s, gap_tick, _smp_x[li], _smp_z[li], _smp_h[li])
	else:
		render_x[s] = x
		render_z[s] = z
		render_heading[s] = h
	_write_sample(s, tick, x, z, h)


func _write_sample(s: int, tick: int, x: float, z: float, h: float) -> void:
	var head: int = _smp_head[s]
	var i: int = s * SAMPLES + head
	_smp_tick[i] = tick
	_smp_x[i] = x
	_smp_z[i] = z
	_smp_h[i] = h
	_smp_head[s] = (head + 1) % SAMPLES
	_smp_n[s] = mini(_smp_n[s] + 1, SAMPLES)
