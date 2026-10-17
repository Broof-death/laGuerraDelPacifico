class_name SpatialGrid
extends RefCounted
## Partición espacial uniforme de celdas de 64 m (ADR-006 punto 2), reconstruida una vez por tick.
##
## Con un mapa de 125 km hay ~3,8 millones de celdas, así que no se guarda un array por celda:
## cada entidad aporta una clave (celda << CELL_SHIFT) | (dueño << OWNER_SHIFT) | slot y las claves
## se ordenan con el sort nativo de PackedInt64Array (O(n log n) en C++). Las entidades de una
## celda, o de una fila de celdas contiguas, quedan en un rango contiguo de `keys` que se encuentra
## con bsearch; dentro de cada celda van agrupadas por dueño, así que una búsqueda de enemigos
## puede saltar de una vez a todas las entidades aliadas de una celda (run_end()).
## Celda = cz * cols + cx. Nada aquí es O(n^2).

const SLOT_BITS: int = 16
const SLOT_MASK: int = (1 << SLOT_BITS) - 1
const OWNER_SHIFT: int = SLOT_BITS
const OWNER_MASK: int = 0xF
const CELL_SHIFT: int = SLOT_BITS + 4

var cell_size: float = SimConstants.GRID_CELL_SIZE
var origin_x: float = 0.0
var origin_z: float = 0.0
var cols: int = 1
var rows: int = 1
## Claves ordenadas de las entidades vivas (tamaño = número de entidades en el último rebuild).
var keys: PackedInt64Array = PackedInt64Array()


func _init(map_size_x: float = SimConstants.DEFAULT_MAP_SIZE, map_size_z: float = SimConstants.DEFAULT_MAP_SIZE,
		p_origin_x: float = 0.0, p_origin_z: float = 0.0, p_cell_size: float = SimConstants.GRID_CELL_SIZE) -> void:
	cell_size = p_cell_size
	origin_x = p_origin_x
	origin_z = p_origin_z
	cols = maxi(1, ceili(map_size_x / cell_size))
	rows = maxi(1, ceili(map_size_z / cell_size))


func cell_x_of(x: float) -> int:
	return clampi(int(floor((x - origin_x) / cell_size)), 0, cols - 1)


func cell_z_of(z: float) -> int:
	return clampi(int(floor((z - origin_z) / cell_size)), 0, rows - 1)


func cell_of(x: float, z: float) -> int:
	return cell_z_of(z) * cols + cell_x_of(x)


## Recalcula store.cell de cada entidad y reordena las claves. Una vez por tick.
func rebuild(store: EntityStore) -> void:
	var n: int = store.count
	assert(n <= SLOT_MASK + 1, "SpatialGrid: demasiadas entidades para SLOT_BITS")
	var px := store.pos_x
	var pz := store.pos_z
	var owners := store.owner
	var cells := store.cell
	keys.resize(n)
	var inv: float = 1.0 / cell_size
	var max_cx: int = cols - 1
	var max_cz: int = rows - 1
	for s: int in n:
		var cx: int = clampi(int(floor((px[s] - origin_x) * inv)), 0, max_cx)
		var cz: int = clampi(int(floor((pz[s] - origin_z) * inv)), 0, max_cz)
		var c: int = cz * cols + cx
		cells[s] = c
		keys[s] = (c << CELL_SHIFT) | (owners[s] << OWNER_SHIFT) | s
	keys.sort()


## Rango [inicio, fin) de `keys` con las entidades de las celdas cx0..cx1 (inclusive) de la fila cz.
## Las celdas de una fila son consecutivas, así que bastan dos bsearch.
func row_range(cz: int, cx0: int, cx1: int) -> Vector2i:
	var first_cell: int = cz * cols + cx0
	var last_cell: int = cz * cols + cx1
	var start: int = keys.bsearch(first_cell << CELL_SHIFT, true)
	var end: int = keys.bsearch((last_cell + 1) << CELL_SHIFT, true)
	return Vector2i(start, end)


## Índice siguiente al último elemento con la misma celda y el mismo dueño que keys[i]
## (para saltar de una vez a todos los aliados de una celda).
func run_end(i: int) -> int:
	return keys.bsearch(((keys[i] >> OWNER_SHIFT) + 1) << OWNER_SHIFT, true)


## Agrega a `out` los slots de las entidades cuya celda toca el cuadrado de lado 2*radius
## centrado en (x, z). Es un filtro grueso: el llamador comprueba la distancia exacta.
func query_box(x: float, z: float, radius: float, out: PackedInt32Array) -> void:
	var cx0: int = cell_x_of(x - radius)
	var cx1: int = cell_x_of(x + radius)
	var cz0: int = cell_z_of(z - radius)
	var cz1: int = cell_z_of(z + radius)
	for cz: int in range(cz0, cz1 + 1):
		var r: Vector2i = row_range(cz, cx0, cx1)
		for k: int in range(r.x, r.y):
			out.append(keys[k] & SLOT_MASK)
