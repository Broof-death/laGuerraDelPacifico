class_name LogicMap
extends RefCounted
## Mapa lógico cargado en memoria (ADR-009 §5-6): rejilla de 16 m (8192 x 8192 celdas) guardada
## por sectores de 4096 m con carga dispersa: solo los sectores no uniformes tienen arrays; los
## uniformes (mar abierto, fuera del mapa) son un byte y una altura. Lo usan el servidor (rutas y
## validación del movimiento) y el cliente (vista provisional del terreno). Solo lectura en partida.
##
## Coordenadas de celda globales (gx, gz) en 0..8191; fuera de ese rango todo es Terrain.OUT.

const SIDE: int = MapGrid.TERRAIN_CELLS_PER_SIDE
const SECTORS: int = MapGrid.SECTORS_PER_SIDE

var def: MapDef
## Por sector: bytes de las celdas (vacío si es uniforme).
var _cells: Array[PackedByteArray] = []
var _heights: Array[PackedByteArray] = []
var _uniform_kind: PackedByteArray = PackedByteArray()
var _uniform_height: PackedFloat32Array = PackedFloat32Array()
var _graphs: Array[PathGraph] = [null, null]
## Por capa: tabla byte -> multiplicador de costo (0 = intransitable).
var cost_tables: Array[PackedFloat32Array] = [Terrain.cost_table(Terrain.Layer.LAND), Terrain.cost_table(Terrain.Layer.SEA)]

static var _cache: Dictionary[String, LogicMap] = {}


func _init() -> void:
	_cells.resize(SECTORS * SECTORS)
	_heights.resize(SECTORS * SECTORS)
	_uniform_kind.resize(SECTORS * SECTORS)
	_uniform_kind.fill(Terrain.Kind.OUT)
	_uniform_height.resize(SECTORS * SECTORS)
	for i: int in SECTORS * SECTORS:
		_cells[i] = PackedByteArray()
		_heights[i] = PackedByteArray()


## Carga un MapDef y sus sectores. Si faltan los grafos del HPA*, los construye (lento en mapas
## grandes: el pipeline los debe generar). Devuelve null si algún sector no carga.
static func from_def(map_def: MapDef) -> LogicMap:
	var m := LogicMap.new()
	m.def = map_def
	if map_def.sector_kind.size() == SECTORS * SECTORS:
		m._uniform_kind = map_def.sector_kind.duplicate()
	if map_def.sector_height.size() == SECTORS * SECTORS:
		m._uniform_height = map_def.sector_height.duplicate()
	for idx: int in map_def.sectors:
		var sec: MapSector = load(map_def.sector_path(idx)) as MapSector
		if sec == null or not sec.is_valid():
			push_error("LogicMap: sector %d inválido o inexistente (%s)" % [idx, map_def.sector_path(idx)])
			return null
		m._cells[idx] = sec.cells
		m._heights[idx] = sec.heights
	for layer: int in Terrain.LAYER_COUNT:
		var g: PathGraph = map_def.graph(layer)
		if g == null or not g.is_valid():
			push_warning("LogicMap: falta el grafo HPA* de la capa %d; se construye al cargar" % layer)
			g = PathGraphBuilder.build(m, layer)
		m._graphs[layer] = g
	return m


## Carga (una vez por proceso) el mapa de `path`. El servidor y el cliente del modo de un jugador
## comparten la misma instancia (es de solo lectura).
static func load_shared(path: String = MapDef.DEFAULT_PATH) -> LogicMap:
	if _cache.has(path):
		return _cache[path]
	var map_def: MapDef = load(path) as MapDef
	if map_def == null:
		push_error("LogicMap: no se pudo cargar %s" % path)
		return null
	var m := from_def(map_def)
	if m != null:
		_cache[path] = m
	return m


## Mapa vacío en memoria (pruebas y generadores): todos los sectores uniformes de `byte`.
static func create_uniform(byte: int, height: float = 0.0) -> LogicMap:
	var m := LogicMap.new()
	m._uniform_kind.fill(byte)
	m._uniform_height.fill(height)
	return m


# --- Consultas -----------------------------------------------------------------------------------

## Byte de terreno (clase y costo extra) de la celda global (gx, gz).
func cell_byte(gx: int, gz: int) -> int:
	if gx < 0 or gz < 0 or gx >= SIDE or gz >= SIDE:
		return Terrain.Kind.OUT
	var sec: int = (gz >> 8) * SECTORS + (gx >> 8)
	var arr: PackedByteArray = _cells[sec]
	if arr.is_empty():
		return _uniform_kind[sec]
	return arr[((gz & 255) << 8) | (gx & 255)]


func cell_byte_at(x: float, z: float) -> int:
	return cell_byte(MapGrid.terrain_index(x), MapGrid.terrain_index(z))


func kind_at(x: float, z: float) -> int:
	return cell_byte_at(x, z) & Terrain.KIND_MASK


## Multiplicador de costo de la celda para la capa (0 = intransitable).
func cell_cost(layer: int, gx: int, gz: int) -> float:
	return cost_tables[layer][cell_byte(gx, gz)]


func passable_cell(layer: int, gx: int, gz: int) -> bool:
	return cost_tables[layer][cell_byte(gx, gz)] > 0.0


func passable_at(layer: int, x: float, z: float) -> bool:
	return cost_tables[layer][cell_byte_at(x, z)] > 0.0


## Altura lógica (y de juego, en m) de la celda.
func cell_height(gx: int, gz: int) -> float:
	if gx < 0 or gz < 0 or gx >= SIDE or gz >= SIDE:
		return 0.0
	var sec: int = (gz >> 8) * SECTORS + (gx >> 8)
	var arr: PackedByteArray = _heights[sec]
	if arr.is_empty():
		return _uniform_height[sec]
	return Terrain.decode_height(arr.decode_u16((((gz & 255) << 8) | (gx & 255)) * 2))


func height_at(x: float, z: float) -> float:
	return cell_height(MapGrid.terrain_index(x), MapGrid.terrain_index(z))


## Costos de la capa en el rectángulo de celdas [gx0, gx0 + w) x [gz0, gz0 + h), fila por fila
## (índice = (gz - gz0) * w + (gx - gx0)). 0 = intransitable. Lo usan las búsquedas locales.
func region_costs(layer: int, gx0: int, gz0: int, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var table: PackedFloat32Array = cost_tables[layer]
	var i: int = 0
	for gz: int in range(gz0, gz0 + h):
		if gz < 0 or gz >= SIDE:
			for k: int in w:
				out[i] = 0.0
				i += 1
			continue
		var row_base: int = (gz >> 8) * SECTORS
		var lz: int = (gz & 255) << 8
		for gx: int in range(gx0, gx0 + w):
			if gx < 0 or gx >= SIDE:
				out[i] = 0.0
			else:
				var sec: int = row_base + (gx >> 8)
				var arr: PackedByteArray = _cells[sec]
				out[i] = table[_uniform_kind[sec] if arr.is_empty() else arr[lz | (gx & 255)]]
			i += 1
	return out


## Como region_costs, pero las celdas transitables que tocan (8 vecinos) una celda prohibida
## cuestan NEAR_BLOCKED_PENALTY veces más: las rutas se separan de la costa y de los obstáculos
## cuando hay lugar, y las unidades que las siguen con su desplazamiento de formación no rozan el
## terreno prohibido. Es la que usan las búsquedas (grafo del HPA* y A* locales).
const NEAR_BLOCKED_PENALTY: float = 2.0


func region_costs_safe(layer: int, gx0: int, gz0: int, w: int, h: int) -> PackedFloat32Array:
	var wide := region_costs(layer, gx0 - 1, gz0 - 1, w + 2, h + 2)
	var ww: int = w + 2
	var out := PackedFloat32Array()
	out.resize(w * h)
	var i: int = 0
	for z: int in h:
		var row: int = (z + 1) * ww
		for x: int in w:
			var c: float = wide[row + x + 1]
			if c > 0.0:
				var up: int = row - ww + x
				var down: int = row + ww + x
				if wide[up] <= 0.0 or wide[up + 1] <= 0.0 or wide[up + 2] <= 0.0 \
						or wide[row + x] <= 0.0 or wide[row + x + 2] <= 0.0 \
						or wide[down] <= 0.0 or wide[down + 1] <= 0.0 or wide[down + 2] <= 0.0:
					c *= NEAR_BLOCKED_PENALTY
			out[i] = c
			i += 1
	return out


## true si el segmento recto de (ax, az) a (bx, bz) solo pasa por celdas transitables de la capa.
## Recorre TODAS las celdas que toca el segmento (supercover): si pasa justo por una esquina,
## exige las dos celdas laterales. Así un segmento aceptado nunca roza una celda prohibida.
func segment_passable(layer: int, ax: float, az: float, bx: float, bz: float) -> bool:
	var table: PackedFloat32Array = cost_tables[layer]
	var inv: float = 1.0 / MapGrid.TERRAIN_CELL
	var fx0: float = (ax + MapGrid.MAP_HALF) * inv
	var fz0: float = (az + MapGrid.MAP_HALF) * inv
	var fx1: float = (bx + MapGrid.MAP_HALF) * inv
	var fz1: float = (bz + MapGrid.MAP_HALF) * inv
	var gx: int = int(floor(fx0))
	var gz: int = int(floor(fz0))
	var gx1: int = int(floor(fx1))
	var gz1: int = int(floor(fz1))
	if table[cell_byte(gx, gz)] <= 0.0:
		return false
	var dx: float = fx1 - fx0
	var dz: float = fz1 - fz0
	var sx: int = 1 if dx > 0.0 else -1
	var sz: int = 1 if dz > 0.0 else -1
	var tdx: float = INF if dx == 0.0 else absf(1.0 / dx)
	var tdz: float = INF if dz == 0.0 else absf(1.0 / dz)
	var tmx: float = INF
	if dx > 0.0:
		tmx = (gx + 1 - fx0) / dx
	elif dx < 0.0:
		tmx = (fx0 - gx) / -dx
	var tmz: float = INF
	if dz > 0.0:
		tmz = (gz + 1 - fz0) / dz
	elif dz < 0.0:
		tmz = (fz0 - gz) / -dz
	var steps: int = absi(gx1 - gx) + absi(gz1 - gz)
	# Caché del sector actual (la consulta de cada celda va en línea: es el bucle caliente).
	var cur_sec: int = -1
	var cur_arr: PackedByteArray
	var cur_uniform: float = 0.0
	while steps > 0 and (gx != gx1 or gz != gz1):
		if absf(tmx - tmz) < 1e-9:
			# Esquina exacta: las dos celdas laterales también cuentan.
			if table[cell_byte(gx + sx, gz)] <= 0.0 or table[cell_byte(gx, gz + sz)] <= 0.0:
				return false
			gx += sx
			gz += sz
			tmx += tdx
			tmz += tdz
			steps -= 2
		elif tmx < tmz:
			gx += sx
			tmx += tdx
			steps -= 1
		else:
			gz += sz
			tmz += tdz
			steps -= 1
		if gx < 0 or gz < 0 or gx >= SIDE or gz >= SIDE:
			return false
		var sec: int = (gz >> 8) * SECTORS + (gx >> 8)
		if sec != cur_sec:
			cur_sec = sec
			cur_arr = _cells[sec]
			cur_uniform = table[_uniform_kind[sec]]
		if cur_arr.is_empty():
			if cur_uniform <= 0.0:
				return false
		elif table[cur_arr[((gz & 255) << 8) | (gx & 255)]] <= 0.0:
			return false
	return true


## true si el sector existe como datos (no uniforme).
func sector_loaded(index: int) -> bool:
	return not _cells[index].is_empty()


func sector_cells(index: int) -> PackedByteArray:
	return _cells[index]


func sector_heights(index: int) -> PackedByteArray:
	return _heights[index]


func uniform_kind(index: int) -> int:
	return _uniform_kind[index]


func uniform_height(index: int) -> float:
	return _uniform_height[index]


func graph(layer: int) -> PathGraph:
	return _graphs[layer]


func set_graph(layer: int, g: PathGraph) -> void:
	_graphs[layer] = g


## Rectángulo (en sectores) que contiene todos los sectores que no son OUT.
func active_sector_rect() -> Rect2i:
	var r := Rect2i()
	var first: bool = true
	for idx: int in SECTORS * SECTORS:
		if _cells[idx].is_empty() and _uniform_kind[idx] == Terrain.Kind.OUT:
			continue
		var p := Vector2i(idx % SECTORS, idx / SECTORS)
		if first:
			r = Rect2i(p, Vector2i.ONE)
			first = false
		else:
			r = r.expand(p).merge(Rect2i(p, Vector2i.ONE))
	return r


## Memoria aproximada de los datos (rejilla y grafos), en bytes.
func memory_bytes() -> Dictionary:
	var grid: int = _uniform_kind.size() + _uniform_height.size() * 4
	var loaded: int = 0
	for idx: int in SECTORS * SECTORS:
		if not _cells[idx].is_empty():
			grid += _cells[idx].size() + _heights[idx].size()
			loaded += 1
	var graphs: int = 0
	for g: PathGraph in _graphs:
		if g != null:
			graphs += g.memory_bytes()
	return {"grid": grid, "sectors_loaded": loaded, "graphs": graphs, "total": grid + graphs}


# --- Escritura (generadores y pruebas; nunca durante la partida) ---------------------------------

## Fija el byte y la altura de una celda. Si el sector era uniforme, lo materializa.
func set_cell(gx: int, gz: int, byte: int, height: float = 0.0) -> void:
	if gx < 0 or gz < 0 or gx >= SIDE or gz >= SIDE:
		return
	var sec: int = (gz >> 8) * SECTORS + (gx >> 8)
	_materialize(sec)
	var li: int = ((gz & 255) << 8) | (gx & 255)
	_cells[sec][li] = byte
	_heights[sec].encode_u16(li * 2, Terrain.encode_height(height))


## Fija el valor uniforme de un sector (descarta sus datos si los tenía).
func set_sector_uniform(index: int, byte: int, height: float = 0.0) -> void:
	_cells[index] = PackedByteArray()
	_heights[index] = PackedByteArray()
	_uniform_kind[index] = byte
	_uniform_height[index] = height


## Pone los datos completos de un sector.
func set_sector_data(index: int, cells: PackedByteArray, heights: PackedByteArray) -> void:
	_cells[index] = cells
	_heights[index] = heights


func _materialize(sec: int) -> void:
	if not _cells[sec].is_empty():
		return
	var cells := PackedByteArray()
	cells.resize(MapSector.CELLS)
	cells.fill(_uniform_kind[sec])
	var heights := PackedByteArray()
	heights.resize(MapSector.CELLS * 2)
	var q: int = Terrain.encode_height(_uniform_height[sec])
	for i: int in MapSector.CELLS:
		heights.encode_u16(i * 2, q)
	_cells[sec] = cells
	_heights[sec] = heights
