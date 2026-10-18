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

const SNAP_RADIUS_CELLS: int = 64
const DIRECT_MAX: float = 4096.0
const SMOOTH_MAX: float = 2048.0

enum Kind { NONE, DIRECT, LOCAL, HPA }

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
# Arrays del A* abstracto, reutilizados entre búsquedas (con sello de búsqueda).
var _ag: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _aparent: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _astamp: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _aclosed: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _stamp: int = 0


func _init(p_map: LogicMap) -> void:
	map = p_map


## Ruta de (sx, sz) a (tx, tz) para la capa.
func find(layer: int, sx: float, sz: float, tx: float, tz: float) -> Result:
	var res := Result.new()
	var graph: PathGraph = map.graph(layer)
	# 1) Origen.
	var s_cell := Vector2i(MapGrid.terrain_index(sx), MapGrid.terrain_index(sz))
	var start := Vector2(sx, sz)
	if not map.passable_cell(layer, s_cell.x, s_cell.y):
		s_cell = _nearest(layer, s_cell, sx, sz, 0, false)
		if s_cell.x < 0:
			res.reason = Command.Reject.UNREACHABLE
			return res
		start = _center(s_cell)
	var comp: int = component_of(layer, s_cell.x, s_cell.y)
	# Destino.
	var g_cell := Vector2i(MapGrid.terrain_index(tx), MapGrid.terrain_index(tz))
	var goal := Vector2(tx, tz)
	if not map.passable_cell(layer, g_cell.x, g_cell.y) or component_of(layer, g_cell.x, g_cell.y) != comp:
		g_cell = _nearest(layer, g_cell, tx, tz, comp, true)
		if g_cell.x < 0:
			res.reason = Command.Reject.UNREACHABLE
			return res
		goal = _center(g_cell)
		res.adjusted = true
	res.goal = goal
	# 2) Recta.
	if start.distance_to(goal) <= DIRECT_MAX and map.segment_passable(layer, start.x, start.y, goal.x, goal.y):
		res.ok = true
		res.kind = Kind.DIRECT
		if start != Vector2(sx, sz):
			res.points.append_array([start.x, start.y])
		res.points.append_array([goal.x, goal.y])
		return res
	var pts := PackedVector2Array([start])
	# 3) Mismo cluster.
	var sc: int = PathGraph.cluster_of_cell(s_cell.x, s_cell.y)
	var gc: int = PathGraph.cluster_of_cell(g_cell.x, g_cell.y)
	var done: bool = false
	if sc == gc:
		var local := _local_path(layer, sc, s_cell, g_cell)
		res.local_expanded += GridSearch.last_expanded
		if not local.is_empty():
			for k: int in range(1, local.size() - 1):
				pts.append(_center(local[k]))
			res.kind = Kind.LOCAL
			done = true
	# 4) HPA*.
	if not done:
		if graph == null:
			res.reason = Command.Reject.UNREACHABLE
			return res
		var abstract := _abstract_path(layer, graph, s_cell, g_cell, res)
		if abstract.is_empty():
			res.reason = Command.Reject.UNREACHABLE
			return res
		res.kind = Kind.HPA
		# Refinamiento: abstract trae las celdas de los nodos (sin origen ni destino).
		var prev_cell := s_cell
		var prev_pt := start
		var chain: Array[Vector2i] = []
		chain.append_array(abstract)
		chain.append(g_cell)
		for i: int in chain.size():
			var cell: Vector2i = chain[i]
			var pt: Vector2 = goal if i == chain.size() - 1 else _center(cell)
			if not map.segment_passable(layer, prev_pt.x, prev_pt.y, pt.x, pt.y):
				var c: int = PathGraph.cluster_of_cell(prev_cell.x, prev_cell.y)
				if c == PathGraph.cluster_of_cell(cell.x, cell.y):
					var local := _local_path(layer, c, prev_cell, cell)
					res.local_expanded += GridSearch.last_expanded
					for k: int in range(1, local.size() - 1):
						pts.append(_center(local[k]))
			if i < chain.size() - 1:
				pts.append(pt)
			prev_cell = cell
			prev_pt = pt
	pts.append(goal)
	# 5) Suavizado.
	var smooth := _string_pull(layer, pts)
	res.ok = true
	for i: int in range(1, smooth.size()):
		res.points.append_array([smooth[i].x, smooth[i].y])
	if start != Vector2(sx, sz):
		# El origen se movió a una celda válida: es el primer punto a seguir.
		var head := PackedFloat64Array([start.x, start.y])
		head.append_array(res.points)
		res.points = head
	return res


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
## SNAP_RADIUS_CELLS; con `match_comp`, solo de la componente `comp`. (-1, -1) si no hay.
func _nearest(layer: int, around: Vector2i, x: float, z: float, comp: int, match_comp: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for r: int in range(0, SNAP_RADIUS_CELLS + 1):
		if best.x >= 0 and (r - 1) * MapGrid.TERRAIN_CELL > best_d:
			break
		for dz: int in range(-r, r + 1):
			var edge: bool = absi(dz) == r
			var dx: int = -r
			while dx <= r:
				var gx: int = around.x + dx
				var gz: int = around.y + dz
				if map.passable_cell(layer, gx, gz) and (not match_comp or component_of(layer, gx, gz) == comp):
					var d: float = Vector2(MapGrid.terrain_center(gx) - x, MapGrid.terrain_center(gz) - z).length()
					# Desempate determinista: menor distancia y, a igualdad, el primero visitado.
					if d < best_d:
						best_d = d
						best = Vector2i(gx, gz)
				if edge or r == 0:
					dx += 1
				else:
					dx += 2 * r  # solo los dos extremos de las filas interiores del anillo
	return best


## A* local dentro del cluster c entre dos celdas globales. Devuelve celdas globales.
func _local_path(layer: int, c: int, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var costs := map.region_costs(layer, ox, oz, cc, cc)
	var path := GridSearch.astar(costs, cc, cc, (a.y - oz) * cc + (a.x - ox), (b.y - oz) * cc + (b.x - ox), Terrain.MIN_COST[layer])
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
	var cc: int = MapGrid.CLUSTER_CELLS
	var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
	var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
	var region := map.region_costs(layer, ox, oz, cc, cc)
	var targets := PackedInt32Array()
	for v: int in range(r.x, r.y):
		var nc: int = graph.node_cell[v]
		targets.append((nc / LogicMap.SIDE - oz) * cc + (nc % LogicMap.SIDE - ox))
	var dist := GridSearch.dijkstra(region, cc, cc, (cell.y - oz) * cc + (cell.x - ox), targets)
	for i: int in targets.size():
		if dist[targets[i]] < INF:
			nodes.append(r.x + i)
			costs.append(dist[targets[i]])
	return [nodes, costs]


## A* sobre el grafo de portales. Devuelve las celdas de los nodos del camino (sin el origen ni el
## destino), o vacío si no hay camino.
func _abstract_path(layer: int, graph: PathGraph, s_cell: Vector2i, g_cell: Vector2i, res: Result) -> Array[Vector2i]:
	var n: int = graph.node_count()
	var S: int = n
	var G: int = n + 1
	var out: Array[Vector2i] = []
	var from_s: Array = _connect(layer, graph, s_cell)
	var to_g: Array = _connect(layer, graph, g_cell)
	res.local_expanded += GridSearch.last_expanded
	if (from_s[0] as PackedInt32Array).is_empty() or (to_g[0] as PackedInt32Array).is_empty():
		return out
	if _ag[layer].size() != n + 2:
		_ag[layer].resize(n + 2)
		_aparent[layer].resize(n + 2)
		_astamp[layer].resize(n + 2)
		_aclosed[layer].resize(n + 2)
		_astamp[layer].fill(0)
		_aclosed[layer].fill(0)
	_stamp += 1
	var stamp: int = _stamp
	var g := _ag[layer]
	var parent := _aparent[layer]
	var seen := _astamp[layer]
	var closed := _aclosed[layer]
	# Costo extra de cada nodo hasta G (los del cluster del destino).
	var goal_extra: Dictionary[int, float] = {}
	var tg_nodes: PackedInt32Array = to_g[0]
	var tg_costs: PackedFloat32Array = to_g[1]
	for i: int in tg_nodes.size():
		goal_extra[tg_nodes[i]] = tg_costs[i]
	var hk: float = Terrain.MIN_COST[layer]
	var heap := PackedInt64Array()
	g[S] = 0.0
	seen[S] = stamp
	parent[S] = -1
	var fs_nodes: PackedInt32Array = from_s[0]
	var fs_costs: PackedFloat32Array = from_s[1]
	for i: int in fs_nodes.size():
		var v: int = fs_nodes[i]
		var ng: float = fs_costs[i]
		if seen[v] != stamp or ng < g[v]:
			seen[v] = stamp
			g[v] = ng
			parent[v] = S
			var cell: int = graph.node_cell[v]
			GridSearch.heap_push(heap, int((ng + GridSearch.octile(cell % LogicMap.SIDE - g_cell.x, cell / LogicMap.SIDE - g_cell.y) * hk) * GridSearch.KEY_SCALE), v)
	var expanded: int = 0
	var found: bool = false
	var starts := graph.edge_start
	var tos := graph.edge_to
	var ecost := graph.edge_cost
	var ncell := graph.node_cell
	while not heap.is_empty():
		var v: int = GridSearch.heap_pop(heap)
		if closed[v] == stamp:
			continue
		closed[v] = stamp
		expanded += 1
		if v == G:
			found = true
			break
		var gv: float = g[v]
		if goal_extra.has(v):
			var ng: float = gv + goal_extra[v]
			if seen[G] != stamp or ng < g[G]:
				seen[G] = stamp
				g[G] = ng
				parent[G] = v
				GridSearch.heap_push(heap, int(ng * GridSearch.KEY_SCALE), G)
		for k: int in range(starts[v], starts[v + 1]):
			var u: int = tos[k]
			if closed[u] == stamp:
				continue
			var ng: float = gv + ecost[k]
			if seen[u] != stamp or ng < g[u]:
				seen[u] = stamp
				g[u] = ng
				parent[u] = v
				var cell: int = ncell[u]
				GridSearch.heap_push(heap, int((ng + GridSearch.octile(cell % LogicMap.SIDE - g_cell.x, cell / LogicMap.SIDE - g_cell.y) * hk) * GridSearch.KEY_SCALE), u)
	res.abstract_expanded = expanded
	if not found:
		return out
	var cur: int = parent[G]
	while cur != S and cur >= 0:
		var cell: int = ncell[cur]
		out.append(Vector2i(cell % LogicMap.SIDE, cell / LogicMap.SIDE))
		cur = parent[cur]
	out.reverse()
	return out


## String pulling: desde cada punto, salta al más lejano visible (segmento transitable) sin pasar
## de SMOOTH_MAX metros.
func _string_pull(layer: int, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var last: int = pts.size() - 1
	var i: int = 0
	while i < last:
		var best: int = i + 1
		var j: int = i + 2
		while j <= last and pts[i].distance_to(pts[j]) <= SMOOTH_MAX:
			if map.segment_passable(layer, pts[i].x, pts[i].y, pts[j].x, pts[j].y):
				best = j
			elif j - best > 3:
				break  # ya no se ve desde hace varios puntos: no seguir buscando
			j += 1
		out.append(pts[best])
		i = best
	return out
