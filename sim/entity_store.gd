class_name EntityStore
extends RefCounted
## Estado de todas las entidades en arrays paralelos densos (SoA, ADR-006 punto 2).
## Un slot por entidad viva, en [0, count). No hay un objeto por entidad.
## Borrado por swap-remove: el último slot ocupa el hueco y se actualiza id_to_slot.
## Los ids son de 32 bits, correlativos desde 1 y nunca se reutilizan (0 = ninguna).
##
## Los arrays tienen tamaño `capacity` (>= count); solo los primeros `count` slots son válidos.
## Los sistemas pueden tomar una referencia local (var px := store.pos_x) para recorrerlos rápido:
## en Godot 4 los Packed*Array se comparten por referencia.

const _INITIAL_CAPACITY: int = 256

var count: int = 0
var capacity: int = 0

# --- Enteros ---
var id: PackedInt32Array = PackedInt32Array()
var def_index: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
## SimConstants.Action
var action: PackedInt32Array = PackedInt32Array()
## Grupo de movimiento interno (0 = ninguno).
var move_group: PackedInt32Array = PackedInt32Array()
## Objetivo actual (id de entidad, 0 = ninguno).
var target_id: PackedInt32Array = PackedInt32Array()
## Celda de la SpatialGrid (la escribe SpatialGrid.rebuild).
var cell: PackedInt32Array = PackedInt32Array()

# --- Posición en metros (float64 por la precisión en 125 km) ---
var pos_x: PackedFloat64Array = PackedFloat64Array()
var pos_z: PackedFloat64Array = PackedFloat64Array()
## Destino del movimiento.
var dest_x: PackedFloat64Array = PackedFloat64Array()
var dest_z: PackedFloat64Array = PackedFloat64Array()

# --- Flotantes ---
## Rumbo en radianes alrededor de Y: atan2(dx, dz), 0 = hacia +Z.
var heading: PackedFloat32Array = PackedFloat32Array()
var vel_x: PackedFloat32Array = PackedFloat32Array()
var vel_z: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var cooldown: PackedFloat32Array = PackedFloat32Array()
var progress: PackedFloat32Array = PackedFloat32Array()

## id -> slot (-1 si la entidad no existe o murió). Índice 0 reservado (NO_ENTITY).
var id_to_slot: PackedInt32Array = PackedInt32Array([-1])
var _next_id: int = 1


func _init(initial_capacity: int = _INITIAL_CAPACITY) -> void:
	_grow(maxi(1, initial_capacity))


## Crea una entidad y devuelve su id. Solo la llama el servidor.
func spawn(p_def_index: int, p_owner: int, x: float, z: float, p_heading: float, p_hp: float) -> int:
	assert(_next_id <= SimConstants.MAX_ENTITY_ID, "EntityStore: se agotaron los ids de 32 bits")
	if count == capacity:
		_grow(capacity * 2)
	var new_id: int = _next_id
	_next_id += 1
	var s: int = count
	count += 1
	id[s] = new_id
	def_index[s] = p_def_index
	owner[s] = p_owner
	action[s] = SimConstants.Action.IDLE
	move_group[s] = 0
	target_id[s] = SimConstants.NO_ENTITY
	cell[s] = 0
	pos_x[s] = x
	pos_z[s] = z
	dest_x[s] = x
	dest_z[s] = z
	heading[s] = p_heading
	vel_x[s] = 0.0
	vel_z[s] = 0.0
	hp[s] = p_hp
	cooldown[s] = 0.0
	progress[s] = 0.0
	id_to_slot.append(s)
	return new_id


## Borra una entidad por swap-remove. Devuelve false si no existía.
## Ojo: cambia el slot de la última entidad; no llamar mientras un sistema recorre los slots.
func remove(entity_id: int) -> bool:
	var s: int = slot_of(entity_id)
	if s < 0:
		return false
	var last: int = count - 1
	if s != last:
		id[s] = id[last]
		def_index[s] = def_index[last]
		owner[s] = owner[last]
		action[s] = action[last]
		move_group[s] = move_group[last]
		target_id[s] = target_id[last]
		cell[s] = cell[last]
		pos_x[s] = pos_x[last]
		pos_z[s] = pos_z[last]
		dest_x[s] = dest_x[last]
		dest_z[s] = dest_z[last]
		heading[s] = heading[last]
		vel_x[s] = vel_x[last]
		vel_z[s] = vel_z[last]
		hp[s] = hp[last]
		cooldown[s] = cooldown[last]
		progress[s] = progress[last]
		id_to_slot[id[s]] = s
	id_to_slot[entity_id] = -1
	count = last
	return true


## Slot de una entidad viva, o -1.
func slot_of(entity_id: int) -> int:
	if entity_id <= SimConstants.NO_ENTITY or entity_id >= id_to_slot.size():
		return -1
	return id_to_slot[entity_id]


func is_alive(entity_id: int) -> bool:
	return slot_of(entity_id) >= 0


## Próximo id que se asignará (los ids nunca bajan).
func next_id() -> int:
	return _next_id


func _grow(new_capacity: int) -> void:
	capacity = new_capacity
	id.resize(new_capacity)
	def_index.resize(new_capacity)
	owner.resize(new_capacity)
	action.resize(new_capacity)
	move_group.resize(new_capacity)
	target_id.resize(new_capacity)
	cell.resize(new_capacity)
	pos_x.resize(new_capacity)
	pos_z.resize(new_capacity)
	dest_x.resize(new_capacity)
	dest_z.resize(new_capacity)
	heading.resize(new_capacity)
	vel_x.resize(new_capacity)
	vel_z.resize(new_capacity)
	hp.resize(new_capacity)
	cooldown.resize(new_capacity)
	progress.resize(new_capacity)
