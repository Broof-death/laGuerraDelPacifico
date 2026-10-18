class_name MapSector
extends Resource
## Rejilla lógica de un sector de 4096 m (ADR-009 §6): 256 x 256 celdas de 16 m, 3 B por celda.
## Solo existen los sectores no uniformes (con tierra y costa, relieve u obstáculos); los uniformes
## los describe MapDef con un solo valor. Lo genera el pipeline del mapa (T-011) o, mientras tanto,
## el mapa provisional (core/map/test_map_builder.gd). Solo lectura durante la partida.

const SIDE: int = 256
const CELLS: int = SIDE * SIDE

## Coordenadas del sector (0..31 por eje; el sector 0 empieza en -65 536 m).
@export var sx: int = 0
@export var sz: int = 0
## Un byte por celda (Terrain: clase y costo extra), índice = lz * 256 + lx.
@export var cells: PackedByteArray = PackedByteArray()
## Altura uint16 por celda en little endian (Terrain.encode_height), índice = 2 * (lz * 256 + lx).
@export var heights: PackedByteArray = PackedByteArray()


func is_valid() -> bool:
	return cells.size() == CELLS and heights.size() == CELLS * 2
