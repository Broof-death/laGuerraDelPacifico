class_name GridSearch
extends RefCounted
## Búsquedas en una ventana rectangular de la rejilla lógica de 16 m (ADR-009): A* y Dijkstra con
## 8 vecinos y sin cortar esquinas (una diagonal exige que las dos celdas ortogonales sean
## transitables). Trabajan sobre un array de costos de la ventana (LogicMap.region_costs: 0 =
## intransitable, si no, el multiplicador de costo de la celda). El costo de un paso es la longitud
## en metros (16 o 16·√2) por el multiplicador de la celda de LLEGADA.
## Deterministas: la cola de prioridad desempata por índice de celda.
## Las usan el constructor del grafo del HPA* (core/) y el buscador de rutas del servidor (sim/).

const STEP: float = MapGrid.TERRAIN_CELL
const DIAG_STEP: float = MapGrid.TERRAIN_CELL * 1.4142135623730951
## Desplazamientos de los 8 vecinos (los 4 primeros ortogonales).
const DX: PackedInt32Array = [1, -1, 0, 0, 1, 1, -1, -1]
const DZ: PackedInt32Array = [0, 0, 1, -1, 1, -1, 1, -1]
## Bits de la clave de la cola reservados al índice de celda (ventanas de hasta 4 M celdas).
const IDX_BITS: int = 22
const IDX_MASK: int = (1 << IDX_BITS) - 1
## Resolución de la prioridad en la clave (1/8 m).
const KEY_SCALE: float = 8.0

## Celdas expandidas por la última búsqueda (estadística).
static var last_expanded: int = 0


## Distancia octil en metros entre dos celdas (sin obstáculos, costo 1).
static func octile(dx: int, dz: int) -> float:
	var ax: int = absi(dx)
	var az: int = absi(dz)
	return STEP * (maxi(ax, az) - mini(ax, az)) + DIAG_STEP * mini(ax, az)


## A* de `start` a `goal` (índices locales: z * w + x). Devuelve los índices del camino, de start
## a goal inclusive, o un array vacío si no hay camino. `min_cost`: menor multiplicador posible
## (heurística admisible).
static func astar(costs: PackedFloat32Array, w: int, h: int, start: int, goal: int, min_cost: float) -> PackedInt32Array:
	var n: int = w * h
	if start < 0 or goal < 0 or start >= n or goal >= n or costs[start] <= 0.0 or costs[goal] <= 0.0:
		return PackedInt32Array()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap := PackedInt64Array()
	var gx: int = goal % w
	var gz: int = goal / w
	var hk: float = min_cost
	g[start] = 0.0
	parent[start] = -1
	_push(heap, int(octile(start % w - gx, start / w - gz) * hk * KEY_SCALE), start)
	var expanded: int = 0
	var found: bool = false
	while not heap.is_empty():
		var idx: int = _pop(heap) & IDX_MASK
		if closed[idx] != 0:
			continue
		closed[idx] = 1
		expanded += 1
		if idx == goal:
			found = true
			break
		var x: int = idx % w
		var z: int = idx / w
		var gi: float = g[idx]
		for d: int in 8:
			var nx: int = x + DX[d]
			var nz: int = z + DZ[d]
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var ni: int = nz * w + nx
			var c: float = costs[ni]
			if c <= 0.0 or closed[ni] != 0:
				continue
			var step: float = STEP
			if d >= 4:
				if costs[z * w + nx] <= 0.0 or costs[nz * w + x] <= 0.0:
					continue
				step = DIAG_STEP
			var ng: float = gi + step * c
			if ng < g[ni]:
				g[ni] = ng
				parent[ni] = idx
				_push(heap, int((ng + octile(nx - gx, nz - gz) * hk) * KEY_SCALE), ni)
	last_expanded = expanded
	if not found:
		return PackedInt32Array()
	var path := PackedInt32Array()
	var cur: int = goal
	while cur != -1:
		path.append(cur)
		cur = parent[cur]
	path.reverse()
	return path


## Dijkstra desde `start`. Devuelve el costo (m) a cada celda de la ventana (INF si no se alcanza).
## Si `targets` no está vacío, termina cuando los cerró todos.
static func dijkstra(costs: PackedFloat32Array, w: int, h: int, start: int, targets: PackedInt32Array = PackedInt32Array()) -> PackedFloat32Array:
	var n: int = w * h
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	if start < 0 or start >= n or costs[start] <= 0.0:
		return g
	var closed := PackedByteArray()
	closed.resize(n)
	var is_target := PackedByteArray()
	var remaining: int = 0
	if not targets.is_empty():
		is_target.resize(n)
		for t: int in targets:
			if t >= 0 and t < n and is_target[t] == 0:
				is_target[t] = 1
				remaining += 1
	var heap := PackedInt64Array()
	g[start] = 0.0
	_push(heap, 0, start)
	var expanded: int = 0
	while not heap.is_empty():
		var idx: int = _pop(heap) & IDX_MASK
		if closed[idx] != 0:
			continue
		closed[idx] = 1
		expanded += 1
		if remaining > 0 and is_target[idx] != 0:
			remaining -= 1
			if remaining == 0:
				break
		var x: int = idx % w
		var z: int = idx / w
		var gi: float = g[idx]
		for d: int in 8:
			var nx: int = x + DX[d]
			var nz: int = z + DZ[d]
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var ni: int = nz * w + nx
			var c: float = costs[ni]
			if c <= 0.0 or closed[ni] != 0:
				continue
			var step: float = STEP
			if d >= 4:
				if costs[z * w + nx] <= 0.0 or costs[nz * w + x] <= 0.0:
					continue
				step = DIAG_STEP
			var ng: float = gi + step * c
			if ng < g[ni]:
				g[ni] = ng
				_push(heap, int(ng * KEY_SCALE), ni)
	last_expanded = expanded
	return g


## Etiqueta las celdas transitables de la ventana conectadas a `seed` (mismas reglas de vecinos)
## con `label` en `labels` (solo las que tienen `unset`). Devuelve cuántas etiquetó.
static func flood(costs: PackedFloat32Array, w: int, h: int, seed: int, labels: PackedInt32Array, label: int, unset: int) -> int:
	if costs[seed] <= 0.0 or labels[seed] != unset:
		return 0
	var stack := PackedInt32Array([seed])
	labels[seed] = label
	var count: int = 1
	while not stack.is_empty():
		var idx: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x: int = idx % w
		var z: int = idx / w
		for d: int in 8:
			var nx: int = x + DX[d]
			var nz: int = z + DZ[d]
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var ni: int = nz * w + nx
			if costs[ni] <= 0.0 or labels[ni] != unset:
				continue
			if d >= 4 and (costs[z * w + nx] <= 0.0 or costs[nz * w + x] <= 0.0):
				continue
			labels[ni] = label
			count += 1
			stack.append(ni)
	return count


# --- Cola de prioridad binaria (mínimo) sobre claves int64: prioridad << IDX_BITS | índice ---------

static func _push(heap: PackedInt64Array, priority: int, idx: int) -> void:
	var key: int = (priority << IDX_BITS) | idx
	heap.append(key)
	var i: int = heap.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		var pk: int = heap[p]
		if pk <= key:
			break
		heap[i] = pk
		i = p
	heap[i] = key


static func _pop(heap: PackedInt64Array) -> int:
	var top: int = heap[0]
	var last: int = heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	var n: int = heap.size()
	if n == 0:
		return top
	var i: int = 0
	while true:
		var l: int = 2 * i + 1
		if l >= n:
			break
		var r: int = l + 1
		var c: int = l
		if r < n and heap[r] < heap[l]:
			c = r
		if heap[c] >= last:
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


## Push y pop públicos (los usa el A* del grafo abstracto).
static func heap_push(heap: PackedInt64Array, priority: int, idx: int) -> void:
	_push(heap, priority, idx)


static func heap_pop(heap: PackedInt64Array) -> int:
	return _pop(heap) & IDX_MASK
