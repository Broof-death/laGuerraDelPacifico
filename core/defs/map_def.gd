class_name MapDef
extends Resource
## Datos del mapa lógico (ADR-009 §6). Lo leen el servidor (rutas, validación) y el cliente (vista
## del terreno provisional, minimapa). Lo genera el pipeline del mapa (T-011); mientras tanto, el
## mapa provisional de core/map/test_map_builder.gd. Cambiar de mapa = cambiar estos datos.
##
## Rejilla: 32 x 32 sectores de 4096 m. Un sector es UNIFORME (un solo byte de terreno y una altura
## para todo el sector: mar abierto o fuera del mapa) o tiene su archivo MapSector en sector_dir.
## La máscara jugable es por sector: los sectores fuera de la zona jugable son uniformes Terrain.OUT.

const DEFAULT_PATH: String = "res://data/map/map_def.tres"
const SECTOR_COUNT: int = MapGrid.SECTORS_PER_SIDE * MapGrid.SECTORS_PER_SIDE

@export var map_name: String = ""
## true mientras sea el mapa sintético de prueba (no el del pipeline).
@export var provisional: bool = true
## Escala horizontal de la geografía (1:20) y proyección (transversa de Mercator), informativas:
## el juego solo ve metros de juego.
@export var geo_scale: float = 20.0
@export var central_meridian_deg: float = -72.5
@export var origin_lat_deg: float = -22.5
## Lupas de los sitios clave (ADR-009 §1b), para mostrar lat/long: [cx, cz, r, k, w, rho_c, R].
@export var lenses: Array[PackedFloat64Array] = []
## Rectángulo que contiene la zona jugable (informativo: cámara, minimapa).
@export var playable_rect: Rect2 = Rect2()
## Byte de terreno de cada sector uniforme (índice = sz * 32 + sx). Para los sectores con archivo
## no se usa.
@export var sector_kind: PackedByteArray = PackedByteArray()
## Altura (m) de cada sector uniforme.
@export var sector_height: PackedFloat32Array = PackedFloat32Array()
## Índices (sz * 32 + sx) de los sectores no uniformes, con archivo en sector_dir.
@export var sectors: PackedInt32Array = PackedInt32Array()
@export_dir var sector_dir: String = "res://data/map/sectors"
## Grafo de portales del HPA* por capa (Terrain.Layer), generado junto con los sectores.
## Si falta, LogicMap lo construye al cargar (lento en mapas grandes).
@export var land_graph: PathGraph
@export var sea_graph: PathGraph


static func sector_file_name(sx: int, sz: int) -> String:
	return "s_%d_%d.res" % [sx, sz]


func sector_path(index: int) -> String:
	var sx: int = index % MapGrid.SECTORS_PER_SIDE
	var sz: int = index / MapGrid.SECTORS_PER_SIDE
	return sector_dir.path_join(sector_file_name(sx, sz))


func graph(layer: int) -> PathGraph:
	return land_graph if layer == Terrain.Layer.LAND else sea_graph
