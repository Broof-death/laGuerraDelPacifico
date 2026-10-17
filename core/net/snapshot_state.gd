class_name SnapshotState
extends RefCounted
## Estado cuantizado de las entidades que un cliente conoce en un snapshot (ADR-006 punto 5).
## Lo guardan los dos lados: el servidor, en el anillo de estados enviados a cada cliente (para
## hacer el delta contra el último confirmado por ack), y el cliente, en el anillo de estados
## recibidos completos (para decodificar los deltas). Ambos lados lo construyen igual, así que
## coinciden bit a bit.
## Arrays paralelos ordenados por id (unos 21-25 B por entidad):
##   ids    id de la entidad (creciente)
##   words  SnapshotCodec.pack_word: x y z (20 bits), rumbo (8), vida (8) y acción (4)
##   vel    velocidad cuantizada de la trayectoria (SnapshotCodec.pack_vel, 16 bits)
##   ref    tick de referencia de la trayectoria (dead reckoning: la posición de `words` es la del
##          tick ref y el cliente la extrapola con `vel`)
##   prog   progreso cuantizado (8 bits; 0 si la acción no lo usa)
##   fresh  solo servidor: último tick en que la copia del cliente era exacta (para la antigüedad)

var ids: PackedInt32Array = PackedInt32Array()
var words: PackedInt64Array = PackedInt64Array()
var vel: PackedInt32Array = PackedInt32Array()
var ref: PackedInt32Array = PackedInt32Array()
var prog: PackedByteArray = PackedByteArray()
var fresh: PackedInt32Array = PackedInt32Array()


func size() -> int:
	return ids.size()


## Índice de `id` o -1.
func index_of(id: int) -> int:
	var i: int = ids.bsearch(id)
	if i < ids.size() and ids[i] == id:
		return i
	return -1


func resize(n: int, with_fresh: bool) -> void:
	ids.resize(n)
	words.resize(n)
	vel.resize(n)
	ref.resize(n)
	prog.resize(n)
	fresh.resize(n if with_fresh else 0)
