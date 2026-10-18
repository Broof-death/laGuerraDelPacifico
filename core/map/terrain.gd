class_name Terrain
extends RefCounted
## Clases de la rejilla lógica del terreno (ADR-009 §5) y su costo por capa de movimiento.
## Solo static/const. Cada celda de 16 m guarda 1 B: la clase en los 4 bits bajos y un costo
## extra en los 4 altos (cada paso suma un 25 % al costo base de la clase; 0 = sin extra).
## La altura va aparte (uint16, paso de 0,01 m sobre y en [-60, 595,35] m; ver encode_height).

## Clase de terreno (4 bits). OUT = fuera del mapa o de la zona jugable (intransitable para todo).
enum Kind {
	DEEP_SEA = 0,    ## mar profundo
	SHALLOW_SEA = 1, ## mar costero
	BEACH = 2,       ## playa o costa
	LAND = 3,        ## tierra
	FORD = 4,        ## río o vado
	ROAD = 5,        ## camino
	IMPASSABLE = 6,  ## infranqueable (cerro, acantilado, quebrada)
	OUT = 7,         ## fuera del mapa
}

## Capas de rutas: las tropas usan LAND y los buques SEA (UnitDef.domain).
enum Layer { LAND = 0, SEA = 1 }
const LAYER_COUNT: int = 2

const KIND_MASK: int = 0x0F
const EXTRA_SHIFT: int = 4
const EXTRA_STEP: float = 0.25

## Multiplicador base del costo por clase (0 = intransitable). Índice = Kind (16 valores; los
## que no existen son intransitables).
const LAND_COST: PackedFloat32Array = [0.0, 0.0, 1.0, 1.0, 2.5, 0.7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const SEA_COST: PackedFloat32Array = [1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## Menor multiplicador posible por capa (para que la heurística de A* sea admisible).
const MIN_COST: PackedFloat32Array = [0.7, 1.0]

## Altura en la rejilla lógica (ADR-009 §1a): uint16 con paso de 0,01 m sobre y en [-60, 595,35].
const HEIGHT_MIN: float = -60.0
const HEIGHT_STEP: float = 0.01


static func make_byte(kind: Kind, extra: int = 0) -> int:
	return (clampi(extra, 0, 15) << EXTRA_SHIFT) | (kind & KIND_MASK)


static func kind_of(byte: int) -> int:
	return byte & KIND_MASK


## Multiplicador de costo de una celda (byte completo) para una capa; 0 = intransitable.
static func cost(layer: int, byte: int) -> float:
	var base: float = LAND_COST[byte & KIND_MASK] if layer == Layer.LAND else SEA_COST[byte & KIND_MASK]
	if base <= 0.0:
		return 0.0
	return base * (1.0 + EXTRA_STEP * (byte >> EXTRA_SHIFT))


static func passable(layer: int, byte: int) -> bool:
	return cost(layer, byte) > 0.0


## Tabla de 256 entradas byte -> multiplicador de costo de la capa (para los bucles calientes).
static func cost_table(layer: int) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(256)
	for b: int in 256:
		t[b] = cost(layer, b)
	return t


static func is_sea_kind(kind: int) -> bool:
	return kind == Kind.DEEP_SEA or kind == Kind.SHALLOW_SEA


## Capa de rutas de un dominio de UnitDef (LAND = 0, SEA = 1).
static func layer_for_domain(domain: int) -> int:
	return Layer.SEA if domain == UnitDef.Domain.SEA else Layer.LAND


static func encode_height(y: float) -> int:
	return clampi(roundi((y - HEIGHT_MIN) / HEIGHT_STEP), 0, 65535)


static func decode_height(q: int) -> float:
	return q * HEIGHT_STEP + HEIGHT_MIN
