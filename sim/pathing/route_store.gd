class_name RouteStore
extends RefCounted
## Rutas de la simulación (T-013, ADR-006 §1 y §3): UNA ruta por orden de movimiento y capa (la
## comparten todas las unidades que la recibieron; si son 8 o más, son además un grupo de
## movimiento de MoveGroups). Las búsquedas esperan en una cola FIFO y se resuelven como mucho
## MAX_SEARCHES_PER_TICK por tick (Simulation.step, antes del movimiento). Mientras la ruta está
## PENDING, sus unidades esperan quietas.
##
## PRESUPUESTO DETERMINISTA (T-018): además del tope de búsquedas, cada tick tiene WORK_PER_TICK
## unidades de trabajo de PathFinder (contadas, no medidas: ~1 µs cada una en el PC de
## referencia). La búsqueda de la cabeza de la cola avanza hasta gastar el presupuesto y, si no
## termina, sigue en el tick siguiente con su estado guardado (PathFinder.Job): las cortas se
## resuelven en un tick y las largas (30 km) se reparten en varios. Si un paso atómico se pasa del
## presupuesto, el exceso se descuenta del tick siguiente. La ruta es idéntica a la de una búsqueda
## completa (PathFinder.find).
## Los ids de ruta son internos y se reutilizan (0 = ninguna). Cada unidad que la usa cuenta como
## una referencia; al llegar, detenerse, recibir otra orden o morir, la suelta.

enum Status { FREE = 0, PENDING = 1, READY = 2, FAILED = 3 }

const MAX_SEARCHES_PER_TICK: int = 8
## Unidades de trabajo de PathFinder por tick: entre 0,5 y 1,5 ms en el PC de referencia (build de
## depuración), según el tipo de búsqueda. Calibrado con S2 + path_stress (rutas p99 <= 3 ms).
const WORK_PER_TICK: int = 1200

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

## 1 si la orden admite el régimen de marcha (T-018: MOVE de al menos MARCH_MIN_ORDER_DIST).
var march: PackedByteArray = PackedByteArray([0])
## Tick hasta el que la ruta está en alerta (enemigo cerca de alguna de sus unidades): sus unidades
## van a velocidad táctica.
var alert_until: PackedInt32Array = PackedInt32Array([0])
## Generación de cada id (cambia al reutilizarlo): una búsqueda a medias de una ruta liberada y
## vuelta a crear no se confunde con la nueva.
var gen: PackedInt32Array = PackedInt32Array([0])

## Búsquedas terminadas en el último process() y en total.
var last_searches: int = 0
var total_searches: int = 0
## Trabajo (unidades de PathFinder) gastado en el último process() y en total.
var last_work: int = 0
var total_work: int = 0
## Tiempo (µs) de cada tramo de búsqueda del último process(), para la medición (no se usa para
## decidir nada: el reparto es por trabajo contado).
var last_search_usec: PackedInt64Array = PackedInt64Array()
## Ticks que tardó cada búsqueda terminada en el último process() (1 = en el mismo tick).
var last_search_ticks: PackedInt32Array = PackedInt32Array()
## Trabajo total de cada búsqueda terminada en el último process().
var last_search_work: PackedInt32Array = PackedInt32Array()

var _job: PathFinder.Job = null
var _job_rid: int = 0
var _job_gen: int = 0
var _job_ticks: int = 0
var _debt: int = 0

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
		gen.append(0)
		march.append(0)
		alert_until.append(0)
	else:
		rid = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	status[rid] = Status.PENDING
	gen[rid] += 1
	march[rid] = 0
	alert_until[rid] = 0
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


func _finish(rid: int, res: PathFinder.Result, rejections: Array[PackedInt32Array]) -> void:
	if res.ok:
		points[rid] = res.points
		final_x[rid] = res.goal.x
		final_z[rid] = res.goal.y
		status[rid] = Status.READY
	else:
		status[rid] = Status.FAILED
		if player[rid] > 0:
			rejections.append(PackedInt32Array([player[rid], seq[rid], res.reason]))


## true si hay una búsqueda a medias (seguirá en el próximo process()).
func has_partial_search() -> bool:
	return _job != null


## Rutas que esperan búsqueda (incluida la que está a medias).
func pending_count() -> int:
	var n: int = 0
	if _job != null and status[_job_rid] == Status.PENDING and gen[_job_rid] == _job_gen:
		n += 1
	for i: int in range(_queue_head, _queue.size()):
		if status[_queue[i]] == Status.PENDING:
			n += 1
	return n


func active_count() -> int:
	return status.size() - 1 - _free.size()


func point_count(rid: int) -> int:
	return points[rid].size() / 2


## Avanza las búsquedas de la cola con el presupuesto del tick (`work_budget` unidades, menos
## el exceso del tick anterior) y termina como mucho `max_searches`. Sin mapa (finder null), la
## ruta es la recta al destino y no cuenta como búsqueda. Las que fallan se anotan en
## `rejections` ([player_id, seq, motivo], como CommandQueue.rejections).
func process(finder: PathFinder, rejections: Array[PackedInt32Array], max_searches: int = MAX_SEARCHES_PER_TICK,
		work_budget: int = WORK_PER_TICK) -> void:
	last_searches = 0
	last_work = 0
	last_search_usec.clear()
	last_search_ticks.clear()
	last_search_work.clear()
	var budget: int = work_budget - _debt
	_debt = 0
	if _job != null:
		_job_ticks += 1
	while last_searches < max_searches:
		if _job != null and (status[_job_rid] != Status.PENDING or gen[_job_rid] != _job_gen):
			_job = null  # la ruta se liberó mientras se buscaba
		if _job == null:
			if _queue_head >= _queue.size():
				break
			var rid: int = _queue[_queue_head]
			if status[rid] != Status.PENDING:
				_queue_head += 1
				continue
			if finder == null:
				_queue_head += 1
				points[rid] = PackedFloat64Array([goal_x[rid], goal_z[rid]])
				status[rid] = Status.READY
				continue
			if budget <= 0:
				break
			_queue_head += 1
			_job = finder.start_job(layer[rid], start_x[rid], start_z[rid], goal_x[rid], goal_z[rid])
			_job_rid = rid
			_job_gen = gen[rid]
			_job_ticks = 1
		if budget <= 0:
			break
		var t0: int = Time.get_ticks_usec()
		var used: int = finder.advance(_job, budget)
		last_search_usec.append(Time.get_ticks_usec() - t0)
		budget -= used
		last_work += used
		total_work += used
		if not _job.is_done():
			break
		_finish(_job_rid, _job.res, rejections)
		last_search_ticks.append(_job_ticks)
		last_search_work.append(_job.work)
		last_searches += 1
		total_searches += 1
		_job = null
	if budget < 0:
		_debt = -budget
	# Compacta la cola de vez en cuando.
	if _queue_head > 256 and _queue_head * 2 > _queue.size():
		_queue = _queue.slice(_queue_head)
		_queue_head = 0
