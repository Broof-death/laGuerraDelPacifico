class_name TestMapBuilder
extends RefCounted
## MAPA PROVISIONAL de prueba (T-013), hasta que el pipeline de T-011 genere el mapa real. Es una
## costa sintética que reproduce la de la partida de prueba (main/test_skirmish.gd: tierra al
## oeste y mar al este de x ≈ 250 m cerca del origen) y la extiende para que haya rutas largas:
##
## - Zona jugable: 6 x 8 sectores (x de -12 288 a 12 288 m, z de -16 384 a 16 384 m); el resto
##   del mundo es Terrain.OUT.
## - Costa norte-sur con ondulaciones, una BAHÍA (z ≈ -1500, el mar entra ~750 m) y una
##   PENÍNSULA (z ≈ 1700, ~1500 m mar adentro), tres islas, playa de 24 m y mar costero de 320 m.
## - Obstáculos en tierra: cerros infranqueables (uno, el "cerro de prueba", a ~650 m al oeste de
##   los ejércitos) y una QUEBRADA este-oeste en z ≈ 5200 con un vado.
##
## La geometría es una función analítica (sample) que el cliente NO usa: el cliente dibuja la
## costa desde los mismos datos de la rejilla (client/world/logic_map_view.gd). Cuando exista el
## mapa real solo cambian los archivos de data/map/.
##
## Regenerar los datos (unos segundos):
##   godot --headless --path . -s res://tests/tools/build_test_map.gd

const SECTOR_MIN := Vector2i(13, 12)
const SECTOR_COUNT := Vector2i(6, 8)
const COAST_BASE_X: float = 250.0
const BEACH_WIDTH: float = 24.0
const SHALLOW_WIDTH: float = 320.0
## Distancia a tierra desde la que el mar es uniforme (profundidad máxima).
const DEEP_SATURATION: float = 1500.0
## Bahía y península: centro en z, semiancho y profundidad (m).
const BAY := Vector3(-1500.0, 450.0, 750.0)
const PENINSULA := Vector3(1700.0, 230.0, 1500.0)
## Cerros infranqueables: [cx, cz, radio x, radio z, altura].
const HILLS: Array = [
	[-650.0, 120.0, 170.0, 120.0, 45.0],
	[-3000.0, -2600.0, 380.0, 260.0, 70.0],
	[-5500.0, 1800.0, 600.0, 420.0, 110.0],
	[-2200.0, -8800.0, 450.0, 300.0, 80.0],
	[-8000.0, -12000.0, 900.0, 700.0, 150.0],
	[-9000.0, 9000.0, 700.0, 500.0, 120.0],
	[-1500.0, 11000.0, 300.0, 500.0, 60.0],
]
## Islas: [cx, cz, radio].
const ISLANDS: Array = [
	[2600.0, -5200.0, 500.0],
	[3800.0, 7600.0, 750.0],
	[1600.0, 12500.0, 300.0],
]
## Quebrada: z central, semiancho, x inicial y final, x del vado y su semiancho.
const RAVINE_Z: float = 5200.0
const RAVINE_HALF: float = 24.0
const RAVINE_X0: float = -12288.0
const RAVINE_X1: float = -800.0
const FORD_X: float = -6000.0
const FORD_HALF: float = 40.0

## Puntos de referencia para pruebas y mediciones.
const PORT_NORTH := Vector2(500.0, -14500.0)
const PORT_SOUTH := Vector2(-100.0, 14500.0)
const LAND_NORTH := Vector2(-10000.0, -14000.0)
const LAND_SOUTH := Vector2(-10000.0, 14000.0)


static func playable_rect() -> Rect2:
	var o := Vector2(SECTOR_MIN) * MapGrid.SECTOR - Vector2(MapGrid.MAP_HALF, MapGrid.MAP_HALF)
	return Rect2(o, Vector2(SECTOR_COUNT) * MapGrid.SECTOR)


## x de la línea de costa (tierra al oeste, mar al este) para un z dado.
static func coast_x(z: float) -> float:
	var x: float = COAST_BASE_X
	x += 40.0 * sin(z / 310.0) * smoothstep(500.0, 1200.0, absf(z))
	x += 900.0 * sin(z / 4100.0 + 0.6) * smoothstep(2500.0, 6000.0, absf(z))
	var tb: float = absf(z - BAY.x) / BAY.y
	if tb < 1.0:
		var c: float = cos(tb * PI * 0.5)
		x -= BAY.z * c * c
	var tp: float = absf(z - PENINSULA.x) / PENINSULA.y
	if tp < 1.0:
		x += PENINSULA.z * (1.0 - smoothstep(0.55, 1.0, tp))
	return x


static func ravine_z(x: float) -> float:
	return RAVINE_Z + 120.0 * sin(x / 900.0)


## Byte de terreno (x) y altura (y) en el punto.
static func sample(x: float, z: float) -> Vector2:
	var d: float = x - coast_x(z)  # > 0: mar
	var island: float = INF  # distancia (con signo) al borde de la isla más cercana
	for isl: Array in ISLANDS:
		island = minf(island, Vector2(x - isl[0], z - isl[1]).length() - isl[2])
	if d > 0.0 and island > 0.0:
		var dist_land: float = minf(d, island)
		var y: float = -2.0 - 18.0 * minf(dist_land, DEEP_SATURATION) / DEEP_SATURATION
		var kind: int = Terrain.Kind.SHALLOW_SEA if dist_land < SHALLOW_WIDTH else Terrain.Kind.DEEP_SEA
		return Vector2(kind, y)
	# Tierra.
	for h: Array in HILLS:
		var ex: float = (x - h[0]) / h[2]
		var ez: float = (z - h[1]) / h[3]
		var e: float = ex * ex + ez * ez
		if e < 1.0:
			return Vector2(Terrain.Kind.IMPASSABLE, h[4] * (1.0 - e))
	if x >= RAVINE_X0 and x <= RAVINE_X1 and absf(z - ravine_z(x)) < RAVINE_HALF:
		if absf(x - FORD_X) < FORD_HALF:
			return Vector2(Terrain.Kind.FORD, 0.0)
		return Vector2(Terrain.Kind.IMPASSABLE, -12.0)
	var shore: float = -d if d <= 0.0 else INF
	if island <= 0.0:
		shore = minf(shore, -island)
	if shore < BEACH_WIDTH:
		return Vector2(Terrain.Kind.BEACH, 0.0)
	return Vector2(Terrain.Kind.LAND, 0.0)


## Genera el mapa en memoria. Con `with_graphs`, construye también los grafos del HPA*.
static func build(with_graphs: bool = true) -> LogicMap:
	var m := LogicMap.create_uniform(Terrain.Kind.OUT)
	var cells_per_sector: int = MapGrid.SECTOR_CELLS
	for sz: int in range(SECTOR_MIN.y, SECTOR_MIN.y + SECTOR_COUNT.y):
		for sx: int in range(SECTOR_MIN.x, SECTOR_MIN.x + SECTOR_COUNT.x):
			var idx: int = sz * MapGrid.SECTORS_PER_SIDE + sx
			var x0: float = sx * MapGrid.SECTOR - MapGrid.MAP_HALF
			var z0: float = sz * MapGrid.SECTOR - MapGrid.MAP_HALF
			var rect := Rect2(x0, z0, MapGrid.SECTOR, MapGrid.SECTOR)
			if not _has_features(rect):
				var v := sample(x0 + MapGrid.SECTOR * 0.5, z0 + MapGrid.SECTOR * 0.5)
				m.set_sector_uniform(idx, int(v.x), v.y)
				continue
			var cells := PackedByteArray()
			cells.resize(MapSector.CELLS)
			var heights := PackedByteArray()
			heights.resize(MapSector.CELLS * 2)
			var first_b: int = -1
			var first_h: int = -1
			var uniform: bool = true
			for lz: int in cells_per_sector:
				var z: float = z0 + (lz + 0.5) * MapGrid.TERRAIN_CELL
				for lx: int in cells_per_sector:
					var v := sample(x0 + (lx + 0.5) * MapGrid.TERRAIN_CELL, z)
					var i: int = lz * cells_per_sector + lx
					var b: int = int(v.x)
					var hq: int = Terrain.encode_height(v.y)
					cells[i] = b
					heights.encode_u16(i * 2, hq)
					if first_b < 0:
						first_b = b
						first_h = hq
					elif b != first_b or hq != first_h:
						uniform = false
			if uniform:
				m.set_sector_uniform(idx, first_b, Terrain.decode_height(first_h))
			else:
				m.set_sector_data(idx, cells, heights)
	if with_graphs:
		for layer: int in Terrain.LAYER_COUNT:
			m.set_graph(layer, PathGraphBuilder.build(m, layer))
	var d := MapDef.new()
	d.map_name = "Costa de prueba (provisional, T-013)"
	d.provisional = true
	d.playable_rect = playable_rect()
	_fill_def(m, d)
	m.def = d
	return m


## Guarda el mapa en `dir` (MapDef en map_def.tres, sectores y grafos en .res comprimidos).
static func save(m: LogicMap, dir: String = "res://data/map") -> Error:
	var sector_dir := dir.path_join("sectors")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sector_dir))
	# Borra los sectores viejos para no dejar archivos huérfanos.
	var da := DirAccess.open(sector_dir)
	if da != null:
		for f: String in da.get_files():
			if f.begins_with("s_") and (f.ends_with(".res") or f.ends_with(".res.import")):
				da.remove(f)
	var d: MapDef = m.def if m.def != null else MapDef.new()
	d.sector_dir = sector_dir
	_fill_def(m, d)
	for idx: int in d.sectors:
		var sec := MapSector.new()
		sec.sx = idx % MapGrid.SECTORS_PER_SIDE
		sec.sz = idx / MapGrid.SECTORS_PER_SIDE
		sec.cells = m.sector_cells(idx)
		sec.heights = m.sector_heights(idx)
		var err := ResourceSaver.save(sec, d.sector_path(idx), ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			return err
	for layer: int in Terrain.LAYER_COUNT:
		var g: PathGraph = m.graph(layer)
		if g == null:
			continue
		var gp := dir.path_join("path_graph_%s.res" % ("land" if layer == Terrain.Layer.LAND else "sea"))
		var err := ResourceSaver.save(g, gp, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			return err
		g.take_over_path(gp)
	d.land_graph = m.graph(Terrain.Layer.LAND)
	d.sea_graph = m.graph(Terrain.Layer.SEA)
	return ResourceSaver.save(d, dir.path_join("map_def.tres"))


static func _fill_def(m: LogicMap, d: MapDef) -> void:
	var n: int = MapDef.SECTOR_COUNT
	d.sector_kind.resize(n)
	d.sector_height.resize(n)
	d.sectors = PackedInt32Array()
	for idx: int in n:
		if m.sector_loaded(idx):
			d.sectors.append(idx)
			d.sector_kind[idx] = Terrain.Kind.OUT
			d.sector_height[idx] = 0.0
		else:
			d.sector_kind[idx] = m.uniform_kind(idx)
			d.sector_height[idx] = m.uniform_height(idx)


## true si algún elemento del mapa (costa con su mar costero, islas, cerros, quebrada) puede caer
## en el rectángulo; si no, el sector es uniforme (tierra llana o mar profundo).
static func _has_features(r: Rect2) -> bool:
	var margin: float = DEEP_SATURATION + MapGrid.TERRAIN_CELL
	var cmin: float = INF
	var cmax: float = -INF
	var z: float = r.position.y
	while z <= r.end.y:
		var c: float = coast_x(z)
		cmin = minf(cmin, c)
		cmax = maxf(cmax, c)
		z += MapGrid.TERRAIN_CELL * 0.5
	if Rect2(cmin - BEACH_WIDTH - 32.0, r.position.y, cmax + margin - cmin + BEACH_WIDTH + 32.0, r.size.y).intersects(r):
		return true
	for isl: Array in ISLANDS:
		var e: float = isl[2] + margin
		if Rect2(isl[0] - e, isl[1] - e, 2.0 * e, 2.0 * e).intersects(r):
			return true
	for h: Array in HILLS:
		if Rect2(h[0] - h[2] - 32.0, h[1] - h[3] - 32.0, 2.0 * h[2] + 64.0, 2.0 * h[3] + 64.0).intersects(r):
			return true
	if Rect2(RAVINE_X0, RAVINE_Z - 120.0 - RAVINE_HALF - 32.0, RAVINE_X1 - RAVINE_X0, 240.0 + 2.0 * RAVINE_HALF + 64.0).intersects(r):
		return true
	return false
