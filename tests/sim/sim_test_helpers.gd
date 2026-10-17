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
	return Simulation.new(make_game_data(), seed_value, 10000.0)


## Huella del estado completo de la simulación (para comparar determinismo).
static func state_hash(sim: Simulation) -> int:
	var st := sim.store
	var parts: Array = [sim.tick, st.count, st.next_id()]
	for s: int in st.count:
		parts.append_array([st.id[s], st.def_index[s], st.owner[s], st.action[s], st.move_group[s],
			st.target_id[s], st.cell[s], st.pos_x[s], st.pos_z[s], st.heading[s], st.vel_x[s], st.vel_z[s], st.hp[s]])
	return hash(parts)
