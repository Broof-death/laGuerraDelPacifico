class_name RouteStore
extends RefCounted
## Rutas de la simulación (T-013, ADR-006 §1 y §3): UNA ruta por orden de movimiento y capa (la
## comparten todas las unidades que la recibieron; si son 8 o más, son además un grupo de
## movimiento de MoveGroups). Las búsquedas esperan en una cola FIFO y se resuelven como mucho
## MAX_SEARCHES_PER_TICK por tick (Simulation.step, antes del movimiento). Mientras la ruta está
## PENDING, sus unidades esperan quietas.
## Los ids de ruta son internos y se reutilizan (0 = ninguna). Cada unidad que la usa cuenta como
## una referencia; al llegar, detenerse, recibir otra orden o morir, la suelta.

enum Status { FREE = 0, PENDING = 1, READY = 2, FAILED = 3 }

const MAX_SEARCHES_PER_TICK: int = 8

var status: PackedByteArray = PackedByteArray([Status.FREE])
var refs: PackedInt32Array = PackedInt32Array([0])
var layer: PackedByteArray = PackedByteArray([0])
var player: PackedInt32Array = PackedInt32Array([0])
var seq: PackedInt32Array = PackedInt32Array([0])
## Origen de la búsqueda (la unidad más cercana al centro del grupo) y destino pedido.
var start_x: PackedFloat64Array = PackedFloat64Array([0.0])
var start_z: PackedFloat64Array = PackedFloat64Array([0.0])
var goal_x: PackedFloat64Array = PackedFloat64Array([0.0])
var goal_z: PackedFloat64Array = PackedFloat64Array([0.0])
## Destino final después del ajuste (válido para la capa).
var final_x: PackedFloat64Array = PackedFloat64Array([0.0])
var final_z: PackedFloat64Array = PackedFloat64Array([0.0])
## Puntos de paso (x, z intercalados), sin el origen; el último es (final_x, final_z).
var points: Array[PackedFloat64Array] = [PackedFloat64Array()]

## Búsquedas hechas en el último process() y en total.
var last_searches: int = 0
var total_searches: int = 0
## Tiempo de cada búsqueda (µs) del último process(), para la medición.
var last_search_usec: PackedInt64Array = PackedInt64Array()

var _free: PackedInt32Array = PackedInt32Array()
var _queue: PackedInt32Array = PackedInt32Array()
var _queue_head: int = 0


## Crea una ruta pendiente con `members` referencias y la pone en la cola.
func create(members: int, p_layer: int, p_player: int, p_seq: int, sx: float, sz: float, tx: float, tz: float) -> int:
	var rid: int
	if _free.is_empty():
		rid = status.size()
		status.append(Status.FREE)
		refs.append(0)
		layer.append(0)
		player.append(0)
		seq.append(0)
		start_x.append(0.0)
		start_z.append(0.0)
		goal_x.append(0.0)
		goal_z.append(0.0)
		final_x.append(0.0)
		final_z.append(0.0)
		points.append(PackedFloat64Array())
	else:
		rid = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	status[rid] = Status.PENDING
	refs[rid] = members
	layer[rid] = p_layer
	player[rid] = p_player
	seq[rid] = p_seq
	start_x[rid] = sx
	start_z[rid] = sz
	goal_x[rid] = tx
	goal_z[rid] = tz
	final_x[rid] = tx
	final_z[rid] = tz
	points[rid] = PackedFloat64Array()
	_queue.append(rid)
	return rid


## Suelta una referencia; con la última, la ruta se libera (si estaba en la cola, se salta).
func release(rid: int) -> void:
	if rid <= 0 or rid >= status.size() or status[rid] == Status.FREE:
		return
	refs[rid] -= 1
	if refs[rid] <= 0:
		status[rid] = Status.FREE
		points[rid] = PackedFloat64Array()
		_free.append(rid)


func pending_count() -> int:
	var n: int = 0
	for i: int in range(_queue_head, _queue.size()):
		if status[_queue[i]] == Status.PENDING:
			n += 1
	return n


func active_count() -> int:
	return status.size() - 1 - _free.size()


func point_count(rid: int) -> int:
	return points[rid].size() / 2


## Resuelve como mucho `max_searches` rutas de la cola. Sin mapa (finder null), la ruta es la
## recta al destino y no cuenta como búsqueda. Las que fallan se anotan en `rejections`
## ([player_id, seq, motivo], como CommandQueue.rejections).
func process(finder: PathFinder, rejections: Array[PackedInt32Array], max_searches: int = MAX_SEARCHES_PER_TICK) -> void:
	last_searches = 0
	last_search_usec.clear()
	while _queue_head < _queue.size() and last_searches < max_searches:
		var rid: int = _queue[_queue_head]
		_queue_head += 1
		if status[rid] != Status.PENDING:
			continue
		if finder == null:
			points[rid] = PackedFloat64Array([goal_x[rid], goal_z[rid]])
			status[rid] = Status.READY
			continue
		var t0: int = Time.get_ticks_usec()
		var res: PathFinder.Result = finder.find(layer[rid], start_x[rid], start_z[rid], goal_x[rid], goal_z[rid])
		last_search_usec.append(Time.get_ticks_usec() - t0)
		last_searches += 1
		total_searches += 1
		if res.ok:
			points[rid] = res.points
			final_x[rid] = res.goal.x
			final_z[rid] = res.goal.y
			status[rid] = Status.READY
		else:
			status[rid] = Status.FAILED
			if player[rid] > 0:
				rejections.append(PackedInt32Array([player[rid], seq[rid], res.reason]))
	# Compacta la cola de vez en cuando.
	if _queue_head > 256 and _queue_head * 2 > _queue.size():
		_queue = _queue.slice(_queue_head)
		_queue_head = 0
