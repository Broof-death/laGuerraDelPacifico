class_name PathGraphBuilder
extends RefCounted
## Construye el grafo del HPA* (PathGraph) de una capa a partir de la rejilla lógica. Es parte del
## pipeline del mapa (lo llama el generador del mapa provisional y lo llamará T-011); LogicMap lo
## usa al cargar solo si el MapDef no trae el grafo.
##
## 1. Estado de cada cluster de 32 x 32 celdas: BLOCKED, OPEN (todo transitable con un solo costo)
##    o MIXED. Los sectores uniformes no se recorren celda a celda.
## 2. Entradas: en cada borde entre dos clusters vecinos, los tramos contiguos de celdas
##    transitables a ambos lados. Un tramo corto (< 12 celdas) da una entrada en su centro; uno
##    largo, dos, a 2 celdas de cada extremo. Cada entrada son dos nodos (uno a cada lado) unidos
##    por una arista de un paso ortogonal.
## 3. Aristas internas entre los nodos de un mismo cluster: en OPEN, la distancia octil por el
##    costo; en MIXED, Dijkstra local desde cada nodo.
## 4. Componentes conexas (union-find) para descartar destinos inalcanzables sin buscar.

const SHORT_SEGMENT: int = 12
const INSET: int = 2

static var last_build_msec: int = 0


## `cluster_rect` en clusters; vacío = los clusters de los sectores que no son OUT.
static func build(map: LogicMap, layer: int, cluster_rect: Rect2i = Rect2i()) -> PathGraph:
	var t0: int = Time.get_ticks_msec()
	var rect := cluster_rect
	if not rect.has_area():
		var sr := map.active_sector_rect()
		rect = Rect2i(sr.position * 8, sr.size * 8)
	rect = rect.intersection(Rect2i(0, 0, MapGrid.CLUSTERS_PER_SIDE, MapGrid.CLUSTERS_PER_SIDE))
	var g := PathGraph.new()
	g.layer = layer
	g.cluster_state.resize(PathGraph.CLUSTERS)
	var cc: int = MapGrid.CLUSTER_CELLS
	var min_cost: float = Terrain.MIN_COST[layer]

	# 1) Estados y costos de los clusters MIXED.
	var mixed_costs: Dictionary[int, PackedFloat32Array] = {}
	var open_cost: Dictionary[int, float] = {}
	for cz: int in range(rect.position.y, rect.end.y):
		for cx: int in range(rect.position.x, rect.end.x):
			var c: int = cz * MapGrid.CLUSTERS_PER_SIDE + cx
			var sec: int = (cz >> 3) * MapGrid.SECTORS_PER_SIDE + (cx >> 3)
			if not map.sector_loaded(sec):
				var u: float = map.cost_tables[layer][map.uniform_kind(sec)]
				g.cluster_state[c] = PathGraph.ClusterState.OPEN if u > 0.0 else PathGraph.ClusterState.BLOCKED
				if u > 0.0:
					open_cost[c] = u
				continue
			var costs := map.region_costs(layer, cx * cc, cz * cc, cc, cc)
			var first: float = costs[0]
			var uniform: bool = true
			var any: bool = false
			for v: float in costs:
				if v != first:
					uniform = false
				if v > 0.0:
					any = true
			if uniform and first > 0.0:
				g.cluster_state[c] = PathGraph.ClusterState.OPEN
				open_cost[c] = first
			elif not any:
				g.cluster_state[c] = PathGraph.ClusterState.BLOCKED
			else:
				g.cluster_state[c] = PathGraph.ClusterState.MIXED
				mixed_costs[c] = costs

	# 2) Entradas.
	var node_of_cell: Dictionary[int, int] = {}
	var cells := PackedInt32Array()
	var clusters := PackedInt32Array()
	var e_from := PackedInt32Array()
	var e_to := PackedInt32Array()
	var e_cost := PackedFloat32Array()
	for cz: int in range(rect.position.y, rect.end.y):
		for cx: int in range(rect.position.x, rect.end.x):
			var c: int = cz * MapGrid.CLUSTERS_PER_SIDE + cx
			if g.cluster_state[c] == PathGraph.ClusterState.BLOCKED:
				continue
			for dir: int in 2:  # 0 = este, 1 = sur
				var nx: int = cx + (1 if dir == 0 else 0)
				var nz: int = cz + (1 if dir == 1 else 0)
				if nx >= rect.end.x or nz >= rect.end.y:
					continue
				var nc: int = nz * MapGrid.CLUSTERS_PER_SIDE + nx
				if g.cluster_state[nc] == PathGraph.ClusterState.BLOCKED:
					continue
				var ca := PackedFloat32Array()
				var cb := PackedFloat32Array()
				ca.resize(cc)
				cb.resize(cc)
				for i: int in cc:
					if dir == 0:
						ca[i] = _cost_in(c, cc - 1, i, mixed_costs, open_cost)
						cb[i] = _cost_in(nc, 0, i, mixed_costs, open_cost)
					else:
						ca[i] = _cost_in(c, i, cc - 1, mixed_costs, open_cost)
						cb[i] = _cost_in(nc, i, 0, mixed_costs, open_cost)
				var i: int = 0
				while i < cc:
					if ca[i] <= 0.0 or cb[i] <= 0.0:
						i += 1
						continue
					var s: int = i
					while i < cc and ca[i] > 0.0 and cb[i] > 0.0:
						i += 1
					var e: int = i - 1
					var picks := PackedInt32Array()
					if e - s + 1 < SHORT_SEGMENT:
						picks.append((s + e) / 2)
					else:
						picks.append(s + INSET)
						picks.append(e - INSET)
					for p: int in picks:
						var ax: int
						var az: int
						var bx: int
						var bz: int
						if dir == 0:
							ax = cx * cc + cc - 1
							az = cz * cc + p
							bx = ax + 1
							bz = az
						else:
							ax = cx * cc + p
							az = cz * cc + cc - 1
							bx = ax
							bz = az + 1
						var a: int = _node(ax, az, c, node_of_cell, cells, clusters)
						var b: int = _node(bx, bz, nc, node_of_cell, cells, clusters)
						e_from.append(a)
						e_to.append(b)
						e_cost.append(GridSearch.STEP * cb[p])
						e_from.append(b)
						e_to.append(a)
						e_cost.append(GridSearch.STEP * ca[p])

	# 3) Aristas internas.
	var by_cluster: Dictionary[int, PackedInt32Array] = {}
	for v: int in cells.size():
		var c: int = clusters[v]
		if not by_cluster.has(c):
			by_cluster[c] = PackedInt32Array()
		by_cluster[c].append(v)
	for c: int in by_cluster:
		var nodes: PackedInt32Array = by_cluster[c]
		if nodes.size() < 2:
			continue
		var ox: int = (c % MapGrid.CLUSTERS_PER_SIDE) * cc
		var oz: int = (c / MapGrid.CLUSTERS_PER_SIDE) * cc
		if g.cluster_state[c] == PathGraph.ClusterState.OPEN:
			var k: float = open_cost[c]
			for i: int in nodes.size():
				for j: int in range(i + 1, nodes.size()):
					var a: int = nodes[i]
					var b: int = nodes[j]
					var d: float = GridSearch.octile((cells[a] % LogicMap.SIDE) - (cells[b] % LogicMap.SIDE),
							(cells[a] / LogicMap.SIDE) - (cells[b] / LogicMap.SIDE)) * k
					e_from.append(a)
					e_to.append(b)
					e_cost.append(d)
					e_from.append(b)
					e_to.append(a)
					e_cost.append(d)
		else:
			var costs: PackedFloat32Array = mixed_costs[c]
			var locals := PackedInt32Array()
			for v: int in nodes:
				locals.append((cells[v] / LogicMap.SIDE - oz) * cc + (cells[v] % LogicMap.SIDE - ox))
			for i: int in nodes.size():
				var dist := GridSearch.dijkstra(costs, cc, cc, locals[i], locals)
				for j: int in nodes.size():
					if j == i or dist[locals[j]] == INF:
						continue
					e_from.append(nodes[i])
					e_to.append(nodes[j])
					e_cost.append(dist[locals[j]])

	# 4) Orden por (cluster, celda), CSR y componentes.
	var n: int = cells.size()
	var keys := PackedInt64Array()
	keys.resize(n)
	for v: int in n:
		keys[v] = (clusters[v] << 27) | cells[v]
	keys.sort()
	var remap := PackedInt32Array()
	remap.resize(n)
	g.node_cell.resize(n)
	g.node_cluster.resize(n)
	for i: int in n:
		var cell: int = keys[i] & ((1 << 27) - 1)
		var old: int = node_of_cell[cell]
		remap[old] = i
		g.node_cell[i] = cell
		g.node_cluster[i] = keys[i] >> 27
	var m: int = e_from.size()
	g.edge_start.resize(n + 1)
	for k: int in m:
		g.edge_start[remap[e_from[k]] + 1] += 1
	for v: int in n:
		g.edge_start[v + 1] += g.edge_start[v]
	g.edge_to.resize(m)
	g.edge_cost.resize(m)
	var fill := g.edge_start.duplicate()
	# Aristas en orden determinista: por origen y, dentro del origen, por orden de creación.
	for k: int in m:
		var a: int = remap[e_from[k]]
		var pos: int = fill[a]
		fill[a] += 1
		g.edge_to[pos] = remap[e_to[k]]
		g.edge_cost[pos] = e_cost[k]
	g.node_comp = _components(n, g.edge_start, g.edge_to)
	last_build_msec = Time.get_ticks_msec() - t0
	return g


static func _cost_in(c: int, lx: int, lz: int, mixed: Dictionary[int, PackedFloat32Array], open_cost: Dictionary[int, float]) -> float:
	if mixed.has(c):
		return mixed[c][lz * MapGrid.CLUSTER_CELLS + lx]
	return open_cost.get(c, 0.0)


static func _node(gx: int, gz: int, c: int, node_of_cell: Dictionary[int, int], cells: PackedInt32Array, clusters: PackedInt32Array) -> int:
	var cell: int = gz * LogicMap.SIDE + gx
	if node_of_cell.has(cell):
		return node_of_cell[cell]
	var v: int = cells.size()
	cells.append(cell)
	clusters.append(c)
	node_of_cell[cell] = v
	return v


static func _components(n: int, starts: PackedInt32Array, tos: PackedInt32Array) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(n)
	for v: int in n:
		parent[v] = v
	for v: int in n:
		for k: int in range(starts[v], starts[v + 1]):
			var a: int = _find(parent, v)
			var b: int = _find(parent, tos[k])
			if a != b:
				parent[maxi(a, b)] = mini(a, b)
	var comp := PackedInt32Array()
	comp.resize(n)
	for v: int in n:
		comp[v] = _find(parent, v)
	return comp


static func _find(parent: PackedInt32Array, v: int) -> int:
	var r: int = v
	while parent[r] != r:
		r = parent[r]
	var x: int = v
	while parent[x] != r:
		var nx: int = parent[x]
		parent[x] = r
		x = nx
	return r
