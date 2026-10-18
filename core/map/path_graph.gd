class_name PathGraph
extends Resource
## Grafo abstracto del HPA* de una capa (tierra o mar) sobre clusters de 512 m (ADR-009 §5 y §9):
## 256 x 256 clusters de 32 x 32 celdas de 16 m. Los nodos son las celdas de entrada en los bordes
## entre clusters vecinos; las aristas son los cruces de borde (entre clusters) y los costos
## precalculados dentro de cada cluster. Lo genera el pipeline del mapa junto con los sectores
## (PathGraphBuilder); el servidor lo usa en PathFinder. Solo lectura durante la partida.
##
## Nodos ordenados por (cluster, celda): los de un cluster son un rango contiguo (cluster_nodes).
## Aristas en formato CSR: las de un nodo v son [edge_start[v], edge_start[v + 1]).

enum ClusterState {
	BLOCKED = 0, ## ninguna celda transitable
	OPEN = 1,    ## todas transitables y con el mismo costo: el camino interno es la recta (octil)
	MIXED = 2,   ## hay obstáculos o costos distintos: hace falta búsqueda local
}

const CLUSTERS: int = MapGrid.CLUSTERS_PER_SIDE * MapGrid.CLUSTERS_PER_SIDE

@export var layer: int = 0
## Estado de cada cluster (índice = cz * 256 + cx).
@export var cluster_state: PackedByteArray = PackedByteArray()
## Celda global de cada nodo (gz * 8192 + gx).
@export var node_cell: PackedInt32Array = PackedInt32Array()
## Cluster de cada nodo (ordenado de menor a mayor).
@export var node_cluster: PackedInt32Array = PackedInt32Array()
## Componente conexa de cada nodo (dos nodos con distinto componente no se conectan).
@export var node_comp: PackedInt32Array = PackedInt32Array()
@export var edge_start: PackedInt32Array = PackedInt32Array()
@export var edge_to: PackedInt32Array = PackedInt32Array()
## Costo de la arista en metros ponderados por el terreno.
@export var edge_cost: PackedFloat32Array = PackedFloat32Array()


func node_count() -> int:
	return node_cell.size()


func is_valid() -> bool:
	return cluster_state.size() == CLUSTERS and edge_start.size() == node_cell.size() + 1 \
			and node_cluster.size() == node_cell.size() and node_comp.size() == node_cell.size() \
			and edge_to.size() == edge_cost.size()


## Rango [x, y) de los nodos del cluster c.
func cluster_nodes(c: int) -> Vector2i:
	var a: int = node_cluster.bsearch(c, true)
	var b: int = node_cluster.bsearch(c, false)
	return Vector2i(a, b)


static func cluster_of_cell(gx: int, gz: int) -> int:
	return (gz >> 5) * MapGrid.CLUSTERS_PER_SIDE + (gx >> 5)


func memory_bytes() -> int:
	return cluster_state.size() + (node_cell.size() + node_cluster.size() + node_comp.size()
			+ edge_start.size() + edge_to.size() + edge_cost.size()) * 4
