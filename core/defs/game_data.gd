class_name GameData
extends Resource
## Catálogo único de definiciones (ADR-007), en data/game_data.tres.
## def_index: posición en el catálogo, primero `units` y después `buildings`, en el orden de los
## arrays. Es el mismo en servidor y cliente (viaja en los snapshots, ADR-006): cambiar el orden
## rompe la compatibilidad en red.

const DEFAULT_PATH: String = "res://data/game_data.tres"

@export var factions: Array[FactionDef] = []
@export var units: Array[UnitDef] = []
@export var buildings: Array[BuildingDef] = []
@export var resources: Array[ResourceDef] = []

var _defs: Array[EntityDef] = []
var _index_by_id: Dictionary[StringName, int] = {}
var _built: bool = false


## Construye los índices y valida el catálogo. Devuelve la lista de errores (vacía si es válido).
## Si hay errores la partida no debe arrancar.
func build_index() -> PackedStringArray:
	var errors := PackedStringArray()
	_defs.clear()
	_index_by_id.clear()
	for u: UnitDef in units:
		_defs.append(u)
	for b: BuildingDef in buildings:
		_defs.append(b)
	if _defs.size() > SimConstants.MAX_DEF_INDEX + 1:
		errors.append("GameData: hay %d definiciones; el máximo es %d." % [_defs.size(), SimConstants.MAX_DEF_INDEX + 1])

	var seen_ids: Dictionary[StringName, bool] = {}
	for i: int in _defs.size():
		var def: EntityDef = _defs[i]
		if def == null:
			errors.append("GameData: la definición %d es nula." % i)
			continue
		_check_id(def.id, "definición %d" % i, seen_ids, errors)
		_index_by_id[def.id] = i
		_check_costs(def.id, def.cost, errors)
		if def.max_hp <= 0:
			errors.append("GameData: '%s' tiene max_hp <= 0." % def.id)
	for r: ResourceDef in resources:
		if r == null:
			errors.append("GameData: hay un recurso nulo.")
			continue
		_check_id(r.id, "recurso", seen_ids, errors)
	for f: FactionDef in factions:
		if f == null:
			errors.append("GameData: hay una facción nula.")
			continue
		_check_id(f.id, "facción", seen_ids, errors)
		_check_costs(f.id, f.start_resources, errors)
		for u: UnitDef in f.units + f.start_units:
			if u == null or not units.has(u):
				errors.append("GameData: la facción '%s' usa una unidad que no está en el catálogo." % f.id)
		for b: BuildingDef in f.buildings:
			if b == null or not buildings.has(b):
				errors.append("GameData: la facción '%s' usa un edificio que no está en el catálogo." % f.id)
		if f.start_building != null and not buildings.has(f.start_building):
			errors.append("GameData: el edificio inicial de '%s' no está en el catálogo." % f.id)
	_built = errors.is_empty()
	return errors


func is_built() -> bool:
	return _built


func def_count() -> int:
	return _defs.size()


## Huella del catálogo (ids y tipos en orden de def_index, y recursos y facciones). Servidor y
## cliente deben tener la misma: el orden de los arrays es parte del protocolo de red (ADR-007).
## Se compara al conectarse (HELLO). Requiere build_index().
func catalog_hash() -> int:
	var parts := PackedStringArray()
	for def: EntityDef in _defs:
		parts.append("%s:%s" % [def.id, "U" if def is UnitDef else "B"])
	for r: ResourceDef in resources:
		parts.append("R:%s" % (r.id if r != null else &""))
	for f: FactionDef in factions:
		parts.append("F:%s" % (f.id if f != null else &""))
	return "|".join(parts).hash() & 0xFFFFFFFF


## Definición por def_index, o null si no existe.
func get_def(def_index: int) -> EntityDef:
	if def_index < 0 or def_index >= _defs.size():
		return null
	return _defs[def_index]


## def_index de un id, o -1 si no existe.
func index_of(id: StringName) -> int:
	return _index_by_id.get(id, -1)


func _check_id(id: StringName, what: String, seen: Dictionary[StringName, bool], errors: PackedStringArray) -> void:
	if id == &"":
		errors.append("GameData: %s sin id." % what)
	elif seen.has(id):
		errors.append("GameData: id repetido '%s'." % id)
	else:
		seen[id] = true


func _check_costs(owner_id: StringName, costs: Dictionary[ResourceDef, int], errors: PackedStringArray) -> void:
	for r: ResourceDef in costs:
		if costs[r] < 0:
			errors.append("GameData: '%s' tiene un costo negativo." % owner_id)
		if not resources.has(r):
			errors.append("GameData: '%s' usa un recurso que no está en el catálogo." % owner_id)
