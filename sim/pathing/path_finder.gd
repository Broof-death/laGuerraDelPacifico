class_name PathFinder
extends RefCounted
## Búsqueda de rutas del servidor (T-013, ADR-006 §1 y ADR-009 §9) sobre el mapa lógico de 16 m,
## con una capa para tierra y otra para mar (Terrain.Layer):
##
## 1. Origen y destino: si el origen cae en una celda intransitable para la capa, se usa la celda
##    transitable más cercana. Si el destino es inválido (tropa al mar, buque a tierra) o está en
##    otra componente conexa (isla, lago), se AJUSTA a la celda transitable más cercana de la misma
##    componente que el origen, dentro de SNAP_RADIUS_CELLS; si no hay ninguna, la ruta falla con
##    Command.Reject.UNREACHABLE.
## 2. Recta directa si el segmento es transitable (lo más común en órdenes cortas).
## 3. Origen y destino en el mismo cluster de 512 m: A* local en la rejilla de 16 m del cluster.
## 4. Si no: HPA* sobre el grafo de portales (PathGraph) y refinamiento con A* local solo en los
##    tramos que no se pueden recorrer en línea recta.
## 5. Suavizado (string pulling): se saltan los puntos intermedios mientras el segmento siga siendo
##    transitable (supercover: nunca roza una celda prohibida), en tramos de hasta SMOOTH_MAX m.
## Determinista: mismas entradas, misma ruta (colas con desempate por índice, sin azar).
##
## BÚSQUEDA INCREMENTAL (T-018): cada búsqueda es un Job con su propio estado (cola, g, padre,
## cadena, puntos) que avanza por etapas (INIT -> CONNECT -> ABSTRACT -> REFINE -> SMOOTH) con un
## presupuesto de trabajo. El trabajo se CUENTA en unidades deterministas (WORK_*: nodos del A*
## abstracto, aristas, celdas de los A* locales y de los segmentos recorridos...), nunca con el
## reloj, así que el reparto entre ticks es igual en cualquier máquina. Las unidades están
## calibradas para que 1 unidad cueste ~1 µs en el binario de depuración del PC de referencia.
## find() hace la búsqueda completa de una vez (presupuesto ilimitado) por el mismo camino.

const SNAP_RADIUS_CELLS: int = 64
const DIRECT_MAX: float = 4096.0
const SMOOTH_MAX: float = 2048.0
## Holgura lateral del suavizado: un atajo solo se toma si también son transitables los dos
## segmentos paralelos a esta distancia (las unidades siguen la ruta con su desplazamiento de
## formación y no deben rozar el terreno prohibido).
const CLEARANCE: float = 6.0
## Peso de la heurística del A* abstracto por capa (A* ponderado: expande muchos menos nodos en
## rutas largas a cambio de rutas algo menos óptimas, que el suavizado corrige en parte).
const ABSTRACT_HEURISTIC: PackedFloat32Array = [1.25, 1.25]

enum Kind { NONE, DIRECT, LOCAL, HPA }
enum Stage { INIT, SNAP_START, SNAP_GOAL, DIRECT, CONNECT_START, CONNECT_GOAL, ABSTRACT, REFINE, SMOOTH, DONE }

## Unidades de trabajo (≈ µs; ver arriba). Pasos: inicio, tramo del refinamiento y candidato del
## suavizado; nodo sacado de la cola del A* abstracto y arista revisada (con su posible entrada en
## la cola); nodo metido en la cola al conectar el origen;
## celda expandida por un A* o Dijkstra local (con sus 8 vecinos) y celda preparada de la ventana
## de costos; celdas de 16 m recorridas por un segmento (cada WORK_SEG_DIV celdas, 1 unidad);
## celdas revisadas al buscar la celda válida más cercana (cada WORK_NEAR_DIV, 1 unidad); y el
## arranque del A* abstracto (cada WORK_ALLOC_DIV nodos del grafo, 1 unidad).
const WORK_STEP: int = 4
const WORK_POP: int = 1
const WORK_EDGE: int = 1
const WORK_PUSH: int = 1
const WORK_LOCAL_CELL: int = 3
const WORK_REGION_CELL_DIV: int = 2
const WORK_SEG_DIV: int = 4
const WORK_NEAR_DIV: int = 2
const WORK_ALLOC_DIV: int = 256
const UNLIMITED: int = 0x7FFFFFFFFFFF
const OPENED: int = 1
const CLOSED: int = 2

## Búsqueda incremental: estado completo de una búsqueda a medias.
class Job:
	var layer: int = 0
	var sx: float = 0.0
	var sz: float = 0.0
	var tx: float = 0.0
	var tz: float = 0.0
	var stage: int = 0
	var res: Result = Result.new()
	## Trabajo acumulado (unidades WORK_*).
	var work: int = 0
	var s_cell: Vector2i
	var g_cell: Vector2i
	var start: Vector2
	var goal: Vector2
	## Puntos antes del suavizado (desde el origen).
	var pts: PackedVector2Array = PackedVector2Array()
	# A* abstracto.
	var graph: PathGraph
	var node_s: int = 0
	var node_g: int = 0
	var hk: float = 1.0
	var heap: PackedInt64Array = PackedInt64Array()
	var ag: PackedFloat32Array = PackedFloat32Array()
	var aparent: PackedInt32Array = PackedInt32Array()
	## 0 = sin ver, OPENED, CLOSED.
	var astate: PackedByteArray = PackedByteArray()
	var goal_extra: Dictionary[int, float] = {}
	# Refinamiento.
	var chain: Array[Vector2i] = []
	var ri: int = 0
	var prev_cell: Vector2i
	var prev_pt: Vector2
	# Suavizado: punto de salida actual, candidato j y mejor visible hasta ahora.
	var sm_out: PackedVector2Array = PackedVector2Array()
	var sm_i: int = 0
	var sm_j: int = 0
	var sm_best: int = 0
	# Búsqueda de la celda válida más cercana (un anillo por paso).
	var near_around: Vector2i
	var near_x: float = 0.0
	var near_z: float = 0.0
	var near_comp: int = 0
	var near_match: bool = false
	var near_r: int = 0
	var near_best: Vector2i
	var near_best_d: float = INF
	var comp: int = 0
	# Conexión al grafo: [nodos, costos] del origen.
	var from_s: Array = []

	func is_done() -> bool:
		return stage == Stage.DONE

## Resultado de una búsqueda.
class Result:
	var ok: bool = false
	## Command.Reject.UNREACHABLE si falla.
	var reason: int = 0
	## Puntos a seguir (x, z intercalados), SIN el origen; el último es el destino (ajustado).
	var points: PackedFloat64Array = PackedFloat64Array()
	## Destino final (ajustado si hacía falta) y si se ajustó.
	var goal: Vector2 = Vector2.ZERO
	var adjusted: bool = false
	var kind: int = Kind.NONE
	## Nodos abstractos expandidos (HPA*) y celdas expandidas en búsquedas locales.
	var abstract_expanded: int = 0
	var local_expanded: int = 0

	func length_from(sx: float, sz: float) -> float:
		var total: float = 0.0
		var px: float = sx
		var pz: float = sz
		for i: int in range(0, points.size(), 2):
			total += Vector2(points[i] - px, points[i + 1] - pz).length()
			px = points[i]
			pz = points[i + 1]
		return total


var map: LogicMap
## Etiquetas de componente por celda de los clusters MIXED, calculadas a pedido
## (clave = capa * 65536 + cluster).
var _labels: Dictionary[int, PackedInt32Array] = {}
## Trabajo contado (unidades WORK_*), acumulado desde que se creó el buscador.
var _work: int = 0
## Caché de costos por cluster (_cluster_costs): clave -> costos, y orden de entrada (FIFO).
const COST_CACHE_MAX: int = 1024
var _cost_cache: Dictionary[int, PackedFloat32Array] = {}
var _cost_cache_order := PackedInt32Array()
var _cost_cache_head: int = 0


func _init(p_map: LogicMap) -> void:
	map = p_map


## Ruta de (sx, sz) a (tx, tz) para la capa, completa en una sola llamada (sin presupuesto).
## Es lo mismo que crear un Job y avanzarlo hasta el final: da exactamente la misma ruta que la
## búsqueda incremental de RouteStore.
func find(layer: int, sx: float, sz: float, tx: float, tz: float) -> Result:
	var job := start_job(layer, sx, sz, tx, tz)
	advance(job, UNLIMITED)
	return job.res


## Crea una búsqueda incremental (todavía no hace trabajo).
func start_job(layer: int, sx: float, sz: float, tx: float, tz: float) -> Job:
	var job := Job.new()
	job.layer = layer
	job.sx = sx
	job.sz = sz
	job.tx = tx
	job.tz = tz
	return job


## Avanza la búsqueda hasta terminarla o hasta gastar `budget` unidades de trabajo (WORK_*).
## Los pasos atómicos (un A* local, la conexión al grafo, un punto del suavizado...) no se parten,
## así que puede pasarse un poco del presupuesto: devuelve el trabajo realmente hecho (RouteStore
## descuenta el exceso del tick siguiente). Determinista: el trabajo se cuenta, no se mide con el
## reloj, y la ruta no depende de cómo se reparta la búsqueda entre ticks.
func advance(job: Job, budget: int) -> int:
	var w0: int = _work
	while job.stage != Stage.DONE and _work - w0 < budget:
		match job.stage:
			Stage.INIT:
				_stage_init(job)
			Stage.SNAP_START:
				_stage_snap_start(job)
			Stage.SNAP_GOAL:
				_stage_snap_goal(job)
			Stage.DIRECT:
				_stage_direct(job)
			Stage.CONNECT_START:
				_stage_connect_start(job)
			Stage.CONNECT_GOAL:
				_stage_connect_goal(job)
			Stage.ABSTRACT:
				_stage_abstract(job, budget - (_work - w0))
			Stage.REFINE:
				_stage_refine(job)
			Stage.SMOOTH:
				_stage_smooth(job)
	var used: int = _work - w0
	job.work += used
	return used


## Trabajo total contado por este buscador (estadística).
func total_work() -> int:
	return _work


func _finish_fail(job: Job) -> void:
	job.res.ok = false
	job.res.reason = Command.Reject.UNREACHABLE
	job.stage = Stage.DONE
	_release(job)


func _release(job: Job) -> void:
	job.heap = PackedInt64Array()
	job.ag = PackedFloat32Array()
	job.aparent = PackedInt32Array()
	job.astate = PackedByteArray()
	job.goal_extra = {}


## 1) Origen: si cae en una celda intransitable, busca la más cercana (anillo por anillo).
func _stage_init(job: Job) -> void:
	_work += WORK_STEP
	job.s_cell = Vector2i(MapGrid.terrain_index(job.sx), MapGrid.terrain_index(job.sz))
	job.start = Vector2(job.sx, job.sz)
	if map.passable_cell(job.layer, job.s_cell.x, job.s_cell.y):
		_begin_goal(job)
		return
	_near_begin(job, job.s_cell, job.sx, job.sz, 0, false)
	job.stage = Stage.SNAP_START


func _stage_snap_start(job: Job) -> void:
	if not _near_step(job):
		return
	if job.near_best.x < 0:
		_finish_fail(job)
		return
	job.s_cell = job.near_best
	job.start = _center(job.s_cell)
	_begin_goal(job)


## Destino: si es inválido (tropa al mar, buque a tierra) o de otra componente, se ajusta a la
## celda válida más cercana de la componente del origen.
func _begin_goal(job: Job) -> void:
	var layer: int = job.layer
	job.comp = component_of(layer, job.s_cell.x, job.s_cell.y)
	job.g_cell = Vector2i(MapGrid.terrain_index(job.tx), MapGrid.terrain_index(job.tz))
	job.goal = Vector2(job.tx, job.tz)
	if not map.passable_cell(layer, job.g_cell.x, job.g_cell.y) or component_of(layer, job.g_cell.x, job.g_cell.y) != job.comp:
		_near_begin(job, job.g_cell, job.tx, job.tz, job.comp, true)
		job.stage = Stage.SNAP_GOAL
		return
	job.res.goal = job.goal
	job.stage = Stage.DIRECT


func _stage_snap_goal(job: Job) -> void:
	if not _near_step(job):
		return
	if job.near_best.x < 0:
		_finish_fail(job)
		return
	job.g_cell = job.near_best
	job.goal = _center(job.g_cell)
	job.res.adjusted = true
	job.res.goal = job.goal
	job.stage = Stage.DIRECT


## 2) Recta; 3) mismo cluster (A* local). Si no, pasa al HPA*.
func _stage_direct(job: Job) -> void:
	var res := job.res
	var layer: int = job.layer
	var start: Vector2 = job.start
	var goal: Vector2 = job.goal
	_work += WORK_STEP
	if start.distance_to(goal) <= DIRECT_MAX and _seg(layer, start.x, start.y, goal.x, goal.y):
		res.ok = true
		res.kind = Kind.DIRECT
		if start != Vector2(job.sx, job.sz):
			res.points.append_array([start.x, start.y])
		res.points.append_array([goal.x, goal.y])
		job.stage = Stage.DONE
		return
	job.pts = PackedVector2Array([start])
	var sc: int = PathGraph.cluster_of_cell(job.s_cell.x, job.s_cell.y)
	var gc: int = PathGraph.cluster_of_cell(job.g_cell.x, job.g_cell.y)
	if sc == gc:
		var local := _local_path(layer, sc, job.s_cell, job.g_cell)
		res.local_expanded += GridSearch.last_expanded
		if not local.is_empty():
			for k: int in range(1, local.size() - 1):
				job.pts.append(_center(local[k]))
			res.kind = Kind.LOCAL
			_begin_smooth(job)
			return
	# 4) HPA*.
	job.graph = map.graph(layer)
	if job.graph == null:
		_finish_fail(job)
		return
	job.stage = Stage.CONNECT_START


## Costos del origen a los nodos de su cluster.
func _stage_connect_start(job: Job) -> void:
	job.from_s = _connect(job.layer, job.graph, job.s_cell)
	if (job.from_s[0] as PackedInt32Array).is_empty():
		_finish_fail(job)
		return
	job.stage = Stage.CONNECT_GOAL


## Costos del destino a los nodos de su cluster, y arranque del A* abstracto.
func _stage_connect_goal(job: Job) -> void:
	var graph: PathGraph = job.graph
	var to_g: Array = _connect(job.layer, graph, job.g_cell)
	if (to_g[0] as PackedInt32Array).is_empty():
		_finish_fail(job)
		return
	var n: int = graph.node_count()
	job.node_s = n
	job.node_g = n + 1
	# Estado propio de la búsqueda (no compartido): una búsqueda puede quedar a medias entre ticks.
	job.ag.resize(n + 2)
	job.aparent.resize(n + 2)
	job.astate.resize(n + 2)
	job.astate.fill(0)
	_work += (n + 2) / WORK_ALLOC_DIV
	var tg_nodes: PackedInt32Array = to_g[0]
	var tg_costs: PackedFloat32Array = to_g[1]
	for i: int in tg_nodes.size():
		job.goal_extra[tg_nodes[i]] = tg_costs[i]
	job.hk = ABSTRACT_HEURISTIC[job.layer]
	var S: int = job.node_s
	job.ag[S] = 0.0
	job.astate[S] = OPENED
	job.aparent[S] = -1
	var fs_nodes: PackedInt32Array = job.from_s[0]
	var fs_costs: PackedFloat32Array = job.from_s[1]
	job.from_s = []
	var gx: int = job.g_cell.x
	var gz: int = job.g_cell.y
	for i: int in fs_nodes.size():
		var v: int = fs_nodes[i]
		var ng: float = fs_costs[i]
		if job.astate[v] == 0 or ng < job.ag[v]:
			job.astate[v] = OPENED
			job.ag[v] = ng
			job.aparent[v] = S
			var cell: int = graph.node_cell[v]
			GridSearch.heap_push(job.heap, int((ng + GridSearch.octile(cell % LogicMap.SIDE - gx, cell / LogicMap.SIDE - gz) * job.hk) * GridSearch.KEY_SCALE), v)
	_work += fs_nodes.size() * WORK_PUSH + tg_nodes.size()
	job.stage = Stage.ABSTRACT


## A* sobre el grafo de portales, interrumpible entre expansiones.
func _stage_abstract(job: Job, budget: int) -> void:
	var graph: PathGraph = job.graph
	var g := job.ag
	var parent := job.aparent
	var state := job.astate
	var heap := job.heap
	var goal_extra := job.goal_extra
	var starts := graph.edge_start
	var tos := graph.edge_to
	var ecost := graph.edge_cost
	var ncell := graph.node_cell
	var G: int = job.node_g
	var hk: float = job.hk
	var gx: int = job.g_cell.x
	var gz: int = job.g_cell.y
	const SIDE: int = LogicMap.SIDE
	const KS: float = GridSearch.KEY_SCALE
	const STEP: float = GridSearch.STEP
	const DIAG: float = GridSearch.DIAG_STEP
	var work: int = 0
	var expanded: int = 0
	var found: bool = false
	while not heap.is_empty() and work < budget:
		var v: int = GridSearch.heap_pop(heap)
		work += WORK_POP
		if state[v] == CLOSED:
			continue
		state[v] = CLOSED
		expanded += 1
		if v == G:
			found = true
			break
		var gv: float = g[v]
		if goal_extra.has(v):
			var ng: float = gv + goal_extra[v]
			if state[G] == 0 or ng < g[G]:
				state[G] = OPENED
				g[G] = ng
				parent[G] = v
				GridSearch.heap_push(heap, int(ng * KS), G)
		var e0: int = starts[v]
		var e1: int = starts[v + 1]
		work += (e1 - e0) * WORK_EDGE
		for k: int in range(e0, e1):
			var u: int = tos[k]
			var su: int = state[u]
			if su == CLOSED:
				continue
			var ng: float = gv + ecost[k]
			if su == 0 or ng < g[u]:
				state[u] = OPENED
				g[u] = ng
				parent[u] = v
				var cell: int = ncell[u]
				# Octil en línea (es el bucle caliente).
				var ax: int = absi(cell % SIDE - gx)
				var az: int = absi(cell / SIDE - gz)
				var h: float = STEP * absi(ax - az) + DIAG * mini(ax, az)
				GridSearch.heap_push(heap, int((ng + h * hk) * KS), u)
	_work += work
	job.res.abstract_expanded += expanded
	if found:
		var chain: Array[Vector2i] = []
		var cur: int = parent[G]
		while cur != job.node_s and cur >= 0:
			var cell: int = ncell[cur]
			chain.append(Vector2i(cell % SIDE, cell / SIDE))
			cur = parent[cur]
		chain.reverse()
		_work += chain.size()
		_release(job)
		job.res.kind = Kind.HPA
		# Refinamiento: la cadena trae las celdas de los nodos (sin el origen) y el destino.
		chain.append(job.g_cell)
		job.chain = chain
		job.ri = 0
		job.prev_cell = job.s_cell
		job.prev_pt = job.start
		job.stage = Stage.REFINE
	elif heap.is_empty():
		_finish_fail(job)


## Refinamiento de un tramo de la cadena abstracta por paso: A* local solo en los tramos que no se
## pueden recorrer en línea recta.
func _stage_refine(job: Job) -> void:
	var layer: int = job.layer
	var chain := job.chain
	var i: int = job.ri
	var cell: Vector2i = chain[i]
	var last: bool = i == chain.size() - 1
	var pt: Vector2 = job.goal if last else _center(cell)
	var prev_cell: Vector2i = job.prev_cell
	var prev_pt: Vector2 = job.prev_pt
	_work += WORK_STEP
	if not _seg(layer, prev_pt.x, prev_pt.y, pt.x, pt.y):
		var c: int = PathGraph.cluster_of_cell(prev_cell.x, prev_cell.y)
		if c == PathGraph.cluster_of_cell(cell.x, cell.y):
			var local := _local_path(layer, c, prev_cell, cell)
			job.res.local_expanded += GridSearch.last_expanded
			for k: int in range(1, local.size() - 1):
				job.pts.append(_center(local[k]))
	if not last:
		job.pts.append(pt)
	job.prev_cell = cell
	job.prev_pt = pt
	job.ri = i + 1
	if job.ri >= chain.size():
		job.chain = []
		_begin_smooth(job)


func _begin_smooth(job: Job) -> void:
	job.pts.append(job.goal)
	job.sm_out = PackedVector2Array([job.pts[0]])
	job.sm_i = 0
	job.sm_best = 1
	job.sm_j = 2
	job.stage = Stage.SMOOTH


## 5) Suavizado (string pulling): desde cada punto, salta al más lejano visible (segmento
## transitable con holgura) sin pasar de SMOOTH_MAX metros. Un candidato por paso.
func _stage_smooth(job: Job) -> void:
	var pts := job.pts
	var last: int = pts.size() - 1
	var i: int = job.sm_i
	if i < last:
		var j: int = job.sm_j
		_work += WORK_STEP
		if j <= last and pts[i].distance_to(pts[j]) <= SMOOTH_MAX and j - job.sm_best <= 4:
			if _wide_passable(job.layer, pts[i], pts[j]):
				job.sm_best = j
			job.sm_j = j + 1
			return
		# Ya no se ve desde hace varios puntos (o se terminó): avanza al mejor.
		var best: int = job.sm_best
		job.sm_out.append(pts[best])
		job.sm_i = best
		job.sm_best = best + 1
		job.sm_j = best + 2
		return
	var res := job.res
	var smooth := job.sm_out
	res.ok = true
	for k: int in range(1, smooth.size()):
		res.points.append_array([smooth[k].x, smooth[k].y])
	if job.start != Vector2(job.sx, job.sz):
		# El origen se movió a una celda válida: es el primer punto a seguir.
		var head := PackedFloat64Array([job.start.x, job.start.y])
		head.append_array(res.points)
		res.points = head
	job.pts = PackedVector2Array()
	job.sm_out = PackedVector2Array()
	job.stage = Stage.DONE


## Componente conexa de la celda en la capa: la del grafo (>= 0) o, si la celda está en un bolsón
## sin portales, un valor negativo propio. INT_MIN si la celda es intransitable.
func component_of(layer: int, gx: int, gz: int) -> int:
	if not map.passable_cell(layer, gx, gz):
		return -0x7FFFFFFF
	var graph: PathGraph = map.graph(layer)
	var c: int = PathGraph.cluster_of_cell(gx, gz)
	if graph == null:
		return 0
	var st: int = graph.cluster_state[c]
	if st == PathGraph.ClusterState.OPEN:
		var r: Vector2i = graph.cluster_nodes(c)
		return graph.node_comp[r.x] if r.y > r.x else -(1 + c)
	var labels := _cluster_labels(layer, graph, c)
	var cc: int = MapGrid.CLUSTER_CELLS
	return labels[(gz & (cc - 1)) * cc + (gx & (cc - 1))]


## Línea de 16 m -> centro de la celda.
static func _center(cell: Vector2i) -> Vector2:
	return Vector2(MapGrid.terrain_center(cell.x), MapGrid.terrain_center(cell.y))


## Celda transitable más cercana a (x, z) (distancia euclídea a su centro) dentro de
## SNAP_RADIUS_CELLS; con `match_comp`, solo de la componente `comp`. Se recorre un anillo por paso
## (_near_step); el resultado queda en job.near_best ((-1, -1) si no hay).
func _near_begin(job: Job, around: Vector2i, x: float, z: float, comp: int, match_comp: bool) -> void:
	job.near_around = around
	job.near_x = x
	job.near_z = z
	job.near_comp = comp
	job.near_match = match_comp
	job.near_r = 0
	job.near_best = Vector2i(-1, -1)
	job.near_best_d = INF


## Recorre el anillo job.near_r. Devuelve true cuando la búsqueda terminó.
func _near_step(job: Job) -> bool:
	var r: int = job.near_r
	if r > SNAP_RADIUS_CELLS or (job.near_best.x >= 0 and (r - 1) * MapGrid.TERRAIN_CELL > job.near_best_d):
		return true
	var layer: int = job.layer
	var around: Vector2i = job.near_around
	var visited: int = 0
	for dz: int in range(-r, r + 1):
		var edge: bool = absi(dz) == r
		var dx: int = -r
		while dx <= r:
			var gx: int = around.x + dx
			var gz: int = around.y + dz
			visited += 1
			if map.passable_cell(layer, gx, gz) and (not job.near_match or component_of(layer, gx, gz) == job.near_comp):
				var d: float = Vector2(MapGrid.terrain_center(gx) - job.near_x, MapGrid.terrain_center(gz) - job.near_z).length()
				# Desempate determinista: menor distancia y, a igualdad, el primero visitado.
				if d < job.near_best_d:
					job.near_best_d = d
					job.near_best = Vector2i(gx, gz)
			if edge or r == 0:
				dx += 1
			else:
				dx += 2 * r  # solo los dos extremos de las filas interiores del anillo
	_work += WORK_STEP + visited / WORK_NEAR_DIV
	job.near_r = r + 1
	return false


## Costos (con la penalización junto a lo prohibido) de las celdas del cluster c, con caché: el
## mapa es de solo lectura. La caché guarda como mucho COST_CACHE_MAX clusters (~4 KB cada uno) y
## descarta el más viejo. Prepararlos cuenta como trabajo solo la primera vez (determinista: la
## caché depende solo de la secuencia de búsquedas).
func _cluster_costs(layer: int, c: int) -> PackedFloat32Array:
	var key: int = layer * PathGraph.CLUSTERS + c
	if _cost_cache.has(key):
		return _cost_cache[key]
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var costs := map.region_costs_safe(layer, ox, oz, cc, cc)
	_work += cc * cc / WORK_REGION_CELL_DIV
	if _cost_cache_order.size() >= COST_CACHE_MAX:
		_cost_cache.erase(_cost_cache_order[_cost_cache_head])
		_cost_cache_order[_cost_cache_head] = key
		_cost_cache_head = (_cost_cache_head + 1) % COST_CACHE_MAX
	else:
		_cost_cache_order.append(key)
	_cost_cache[key] = costs
	return costs


## A* local dentro del cluster c entre dos celdas globales. Devuelve celdas globales.
func _local_path(layer: int, c: int, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var costs := _cluster_costs(layer, c)
	var path := GridSearch.astar(costs, cc, cc, (a.y - oz) * cc + (a.x - ox), (b.y - oz) * cc + (b.x - ox), Terrain.MIN_COST[layer])
	_work += GridSearch.last_expanded * WORK_LOCAL_CELL
	var out: Array[Vector2i] = []
	for li: int in path:
		out.append(Vector2i(ox + li % cc, oz + li / cc))
	return out


## Etiquetas de componente de las celdas de un cluster MIXED (caché).
func _cluster_labels(layer: int, graph: PathGraph, c: int) -> PackedInt32Array:
	var key: int = layer * PathGraph.CLUSTERS + c
	if _labels.has(key):
		return _labels[key]
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var costs := map.region_costs(layer, ox, oz, cc, cc)
	_work += cc * cc
	var labels := PackedInt32Array()
	labels.resize(cc * cc)
	var unset: int = -0x7FFFFFFF
	labels.fill(unset)
	var r: Vector2i = graph.cluster_nodes(c)
	for v: int in range(r.x, r.y):
		var cell: int = graph.node_cell[v]
		var li: int = (cell / LogicMap.SIDE - oz) * cc + (cell % LogicMap.SIDE - ox)
		GridSearch.flood(costs, cc, cc, li, labels, graph.node_comp[v], unset)
	for li: int in cc * cc:
		if costs[li] > 0.0 and labels[li] == unset:
			# Bolsón sin portales: componente propia (negativa y única en el mapa).
			var gcell: int = (oz + li / cc) * LogicMap.SIDE + ox + li % cc
			GridSearch.flood(costs, cc, cc, li, labels, -(1 + PathGraph.CLUSTERS + gcell), unset)
	_labels[key] = labels
	return labels


## Costos de una celda a los nodos de su cluster: [nodos, costos]. OPEN: octil; MIXED: Dijkstra.
func _connect(layer: int, graph: PathGraph, cell: Vector2i) -> Array:
	var c: int = PathGraph.cluster_of_cell(cell.x, cell.y)
	var r: Vector2i = graph.cluster_nodes(c)
	var nodes := PackedInt32Array()
	var costs := PackedFloat32Array()
	if r.y <= r.x:
		return [nodes, costs]
	if graph.cluster_state[c] == PathGraph.ClusterState.OPEN:
		var k: float = map.cell_cost(layer, cell.x, cell.y)
		for v: int in range(r.x, r.y):
			var nc: int = graph.node_cell[v]
			nodes.append(v)
			costs.append(GridSearch.octile(nc % LogicMap.SIDE - cell.x, nc / LogicMap.SIDE - cell.y) * k)
		return [nodes, costs]
	# Atajo: si se ven TODOS los nodos del cluster en línea recta, su costo es el largo por el costo
	# de la celda y no hace falta el Dijkstra local.
	var k0: float = map.cell_cost(layer, cell.x, cell.y)
	var cx0: float = MapGrid.terrain_center(cell.x)
	var cz0: float = MapGrid.terrain_center(cell.y)
	for v: int in range(r.x, r.y):
		var nc: int = graph.node_cell[v]
		var nx: float = MapGrid.terrain_center(nc % LogicMap.SIDE)
		var nz: float = MapGrid.terrain_center(nc / LogicMap.SIDE)
		_work += WORK_STEP + int((absf(nx - cx0) + absf(nz - cz0)) / (MapGrid.TERRAIN_CELL * WORK_SEG_DIV))
		if not map.segment_passable(layer, cx0, cz0, nx, nz):
			nodes.clear()
			costs.clear()
			break
		nodes.append(v)
		costs.append(Vector2(nx - cx0, nz - cz0).length() * k0)
	if not nodes.is_empty():
		return [nodes, costs]
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var region := _cluster_costs(layer, c)
	var targets := PackedInt32Array()
	for v: int in range(r.x, r.y):
		var nc: int = graph.node_cell[v]
		targets.append((nc / LogicMap.SIDE - oz) * cc + (nc % LogicMap.SIDE - ox))
	var dist := GridSearch.dijkstra(region, cc, cc, (cell.y - oz) * cc + (cell.x - ox), targets)
	_work += GridSearch.last_expanded * WORK_LOCAL_CELL
	for i: int in targets.size():
		if dist[targets[i]] < INF:
			nodes.append(r.x + i)
			costs.append(dist[targets[i]])
	return [nodes, costs]


## Segmento transitable con holgura lateral CLEARANCE a ambos lados.
func _wide_passable(layer: int, a: Vector2, b: Vector2) -> bool:
	if not _seg(layer, a.x, a.y, b.x, b.y):
		return false
	var d := b - a
	if d.length_squared() < 0.0001:
		return true
	var n := Vector2(-d.y, d.x).normalized() * CLEARANCE
	if not _seg(layer, a.x + n.x, a.y + n.y, b.x + n.x, b.y + n.y):
		return false
	return _seg(layer, a.x - n.x, a.y - n.y, b.x - n.x, b.y - n.y)


## Segmento transitable (supercover de 16 m). Atajo: si todos los clusters de 512 m que toca son
## OPEN para la capa (todo transitable), no hace falta recorrer las celdas.
func _seg(layer: int, ax: float, az: float, bx: float, bz: float) -> bool:
	var graph: PathGraph = map.graph(layer)
	_work += 1
	if graph != null and _clusters_open(graph, ax, az, bx, bz):
		return true
	_work += int((absf(bx - ax) + absf(bz - az)) / (MapGrid.TERRAIN_CELL * WORK_SEG_DIV))
	return map.segment_passable(layer, ax, az, bx, bz)


## Celdas de 16 m recorridas por segment_clear (aproximadas por el largo; las que se ahorra el
## atajo de los clusters abiertos no cuentan). El movimiento lo pone a 0 en cada tick y lo usa
## como presupuesto determinista de los arranques de ruta.
static var clear_cells: int = 0


## Segmento transitable para la capa (lo usa el movimiento): si todos los clusters de 512 m que
## toca son OPEN no recorre las celdas.
static func segment_clear(map: LogicMap, layer: int, ax: float, az: float, bx: float, bz: float) -> bool:
	var graph: PathGraph = map.graph(layer)
	if graph != null and _clusters_open(graph, ax, az, bx, bz):
		return true
	clear_cells += int((absf(bx - ax) + absf(bz - az)) / MapGrid.TERRAIN_CELL)
	return map.segment_passable(layer, ax, az, bx, bz)


## true si todos los clusters que toca el segmento (supercover sobre la rejilla de 512 m) son OPEN.
static func _clusters_open(graph: PathGraph, ax: float, az: float, bx: float, bz: float) -> bool:
	var states := graph.cluster_state
	const SIDE: int = MapGrid.CLUSTERS_PER_SIDE
	var inv: float = 1.0 / MapGrid.CLUSTER
	var fx0: float = (ax + MapGrid.MAP_HALF) * inv
	var fz0: float = (az + MapGrid.MAP_HALF) * inv
	var fx1: float = (bx + MapGrid.MAP_HALF) * inv
	var fz1: float = (bz + MapGrid.MAP_HALF) * inv
	var cx: int = int(floor(fx0))
	var cz: int = int(floor(fz0))
	var cx1: int = int(floor(fx1))
	var cz1: int = int(floor(fz1))
	if cx < 0 or cz < 0 or cx >= SIDE or cz >= SIDE or cx1 < 0 or cz1 < 0 or cx1 >= SIDE or cz1 >= SIDE:
		return false
	if states[cz * SIDE + cx] != PathGraph.ClusterState.OPEN:
		return false
	var dx: float = fx1 - fx0
	var dz: float = fz1 - fz0
	var sx: int = 1 if dx > 0.0 else -1
	var sz: int = 1 if dz > 0.0 else -1
	var tdx: float = INF if dx == 0.0 else absf(1.0 / dx)
	var tdz: float = INF if dz == 0.0 else absf(1.0 / dz)
	var tmx: float = INF
	if dx > 0.0:
		tmx = (cx + 1 - fx0) / dx
	elif dx < 0.0:
		tmx = (fx0 - cx) / -dx
	var tmz: float = INF
	if dz > 0.0:
		tmz = (cz + 1 - fz0) / dz
	elif dz < 0.0:
		tmz = (fz0 - cz) / -dz
	var steps: int = absi(cx1 - cx) + absi(cz1 - cz)
	while steps > 0 and (cx != cx1 or cz != cz1):
		if absf(tmx - tmz) < 1e-9:
			if states[cz * SIDE + cx + sx] != PathGraph.ClusterState.OPEN or states[(cz + sz) * SIDE + cx] != PathGraph.ClusterState.OPEN:
				return false
			cx += sx
			cz += sz
			tmx += tdx
			tmz += tdz
			steps -= 2
		elif tmx < tmz:
			cx += sx
			tmx += tdx
			steps -= 1
		else:
			cz += sz
			tmz += tdz
			steps -= 1
		if states[cz * SIDE + cx] != PathGraph.ClusterState.OPEN:
			return false
	return true
