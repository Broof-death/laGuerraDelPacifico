class_name MapGrid
extends RefCounted
## Constantes y conversiones del mapa (ADR-009 punto 3). Solo static/const, sin estado.
## Mundo cuadrado de 131 072 m (2^17) centrado en el origen: x y z van de -65 536 a +65 536 m
## (intervalo semiabierto). x = este (+X), z = sur (+Z). Todas las rejillas parten de -MAP_HALF.

## Lado del mundo en metros.
const MAP_SIZE: float = 131072.0
const MAP_HALF: float = 65536.0
## Cuantización de la posición absoluta en los snapshots: 20 bits por eje, paso de 0,125 m exactos.
const QUANT_BITS: int = 20
const QUANT_MAX: int = (1 << QUANT_BITS) - 1
const QUANT_STEP: float = 0.125
const QUANT_INV_STEP: float = 8.0
## Celda de la SpatialGrid (ADR-006): 2048 por eje, índice global cz * 2048 + cx (22 bits).
const GRID_CELL: float = 64.0
const GRID_CELLS_PER_SIDE: int = 2048
## Visibilidad por equipo (ADR-006): celdas de 32 m en bloques de 2048 m.
const VISION_CELL: float = 32.0
const VISION_BLOCK: float = 2048.0
## Sectores de datos del mapa y de Terrain3D.
const SECTOR: float = 4096.0
const SECTORS_PER_SIDE: int = 32
## Rejilla lógica del terreno.
const TERRAIN_CELL: float = 16.0


## Rectángulo del mundo en el plano (x, z).
static func world_rect() -> Rect2:
	return Rect2(-MAP_HALF, -MAP_HALF, MAP_SIZE, MAP_SIZE)


## Posición en metros -> entero de 20 bits: floor((x + 65536) * 8), acotado a 0..2^20-1.
static func quantize(v: float) -> int:
	return clampi(int(floor((v + MAP_HALF) * QUANT_INV_STEP)), 0, QUANT_MAX)


## Entero de 20 bits -> metros. Devuelve el centro del paso, así el error máximo es medio paso
## (0,0625 m).
static func dequantize(q: int) -> float:
	return (q + 0.5) * QUANT_STEP - MAP_HALF


## Índice global de la celda de 64 m (acotado al mundo).
static func cell_of(x: float, z: float) -> int:
	var cx: int = clampi(int(floor((x + MAP_HALF) / GRID_CELL)), 0, GRID_CELLS_PER_SIDE - 1)
	var cz: int = clampi(int(floor((z + MAP_HALF) / GRID_CELL)), 0, GRID_CELLS_PER_SIDE - 1)
	return cz * GRID_CELLS_PER_SIDE + cx


## Sector (sx, sz) de 4096 m que contiene el punto (acotado al mundo).
static func sector_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x + MAP_HALF) / SECTOR)), 0, SECTORS_PER_SIDE - 1),
			clampi(int(floor((z + MAP_HALF) / SECTOR)), 0, SECTORS_PER_SIDE - 1))


## Único punto de conversión de la simulación al render (ADR-009 punto 4). Hoy sin desplazamiento:
## si algún día hace falta un rebase de origen, se agrega aquí.
static func to_render(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, z)
