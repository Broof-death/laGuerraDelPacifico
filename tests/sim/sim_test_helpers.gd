class_name SimTestHelpers
extends RefCounted
## Utilidades compartidas por las pruebas de sim/.


## GameData en memoria con una unidad (speed 5 m/s, visión 200 m) y un edificio inmóvil.
## def_index 0 = unidad, 1 = edificio.
static func make_game_data() -> GameData:
	var res := ResourceDef.new()
	res.id = &"recurso_test"
	var unit := UnitDef.new()
	unit.id = &"unidad_test"
	unit.speed = 5.0
	unit.vision_range = 200.0
	unit.max_hp = 100
	unit.cost = {res: 10}
	var building := BuildingDef.new()
	building.id = &"edificio_test"
	building.max_hp = 1000
	var fac := FactionDef.new()
	fac.id = &"faccion_test"
	fac.units = [unit]
	fac.buildings = [building]
	var gd := GameData.new()
	gd.units = [unit]
	gd.buildings = [building]
	gd.resources = [res]
	gd.factions = [fac]
	var errors := gd.build_index()
	assert(errors.is_empty(), str(errors))
	return gd


static func make_sim(seed_value: int = 1) -> Simulation:
	return Simulation.new(make_game_data(), seed_value, Rect2(0.0, 0.0, 10000.0, 10000.0))


## Huella del estado completo de la simulación (para comparar determinismo).
static func state_hash(sim: Simulation) -> int:
	var st := sim.store
	var parts: Array = [sim.tick, st.count, st.next_id()]
	for s: int in st.count:
		parts.append_array([st.id[s], st.def_index[s], st.owner[s], st.action[s], st.move_group[s],
			st.target_id[s], st.cell[s], st.pos_x[s], st.pos_z[s], st.heading[s], st.vel_x[s], st.vel_z[s], st.hp[s]])
	return hash(parts)


## GameData con una unidad de tierra (def 0, 5 m/s), un buque (def 1, dominio SEA, 10 m/s) y un
## edificio (def 2). Para las pruebas de rutas (T-013).
static func make_naval_game_data() -> GameData:
	var res := ResourceDef.new()
	res.id = &"recurso_test"
	var unit := UnitDef.new()
	unit.id = &"unidad_test"
	unit.speed = 5.0
	unit.vision_range = 200.0
	unit.max_hp = 100
	var ship := UnitDef.new()
	ship.id = &"buque_test"
	ship.domain = UnitDef.Domain.SEA
	ship.category = UnitDef.Category.SHIP
	ship.speed = 10.0
	ship.radius = 12.0
	ship.vision_range = 600.0
	ship.max_hp = 2000
	var building := BuildingDef.new()
	building.id = &"edificio_test"
	building.max_hp = 1000
	var fac := FactionDef.new()
	fac.id = &"faccion_test"
	fac.units = [unit, ship]
	fac.buildings = [building]
	var gd := GameData.new()
	gd.units = [unit, ship]
	gd.buildings = [building]
	gd.resources = [res]
	gd.factions = [fac]
	var errors := gd.build_index()
	assert(errors.is_empty(), str(errors))
	return gd


## Simulación sobre el mapa provisional de prueba (data/map/), con make_naval_game_data().
static func make_map_sim(seed_value: int = 1) -> Simulation:
	return Simulation.new(make_naval_game_data(), seed_value, Rect2(), LogicMap.load_shared())
