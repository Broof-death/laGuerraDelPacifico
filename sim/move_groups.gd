class_name MoveGroups
extends RefCounted
## Grupos de movimiento internos de la simulación (ADR-006 punto 3).
## Un MOVE/ATTACK_MOVE con 8 o más unidades crea un grupo con UNA ruta (RouteStore) y una
## formación (FormationLayout). Todos los miembros avanzan a la velocidad del más lento, táctica o
## de marcha (T-018). El grupo se disuelve cuando su último miembro
## llega, se detiene, recibe otra orden o muere. No cambia el protocolo de red.
## Los ids de grupo son internos y se reutilizan (0 = ninguno).

## Miembros vivos de cada grupo (0 = grupo libre). Índice 0 reservado.
var member_count: PackedInt32Array = PackedInt32Array([0])
## Velocidad táctica máxima del grupo (la del miembro más lento), en m/s.
var speed_cap: PackedFloat32Array = PackedFloat32Array([0.0])
## Velocidad de marcha máxima del grupo (la menor de los miembros), en m/s.
var march_cap: PackedFloat32Array = PackedFloat32Array([0.0])
## Destino del grupo (la ruta).
var dest_x: PackedFloat64Array = PackedFloat64Array([0.0])
var dest_z: PackedFloat64Array = PackedFloat64Array([0.0])
var _free: PackedInt32Array = PackedInt32Array()


func create(members: int, p_speed_cap: float, x: float, z: float, p_march_cap: float = -1.0) -> int:
	var gid: int
	if _free.is_empty():
		gid = member_count.size()
		member_count.append(0)
		speed_cap.append(0.0)
		march_cap.append(0.0)
		dest_x.append(0.0)
		dest_z.append(0.0)
	else:
		gid = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	member_count[gid] = members
	speed_cap[gid] = p_speed_cap
	march_cap[gid] = p_march_cap if p_march_cap >= 0.0 else p_speed_cap
	dest_x[gid] = x
	dest_z[gid] = z
	return gid


## Saca un miembro del grupo; si era el último, el grupo se disuelve.
func leave(gid: int) -> void:
	if gid <= 0 or gid >= member_count.size() or member_count[gid] <= 0:
		return
	member_count[gid] -= 1
	if member_count[gid] == 0:
		_free.append(gid)


## Número de grupos activos.
func active_count() -> int:
	return member_count.size() - 1 - _free.size()
