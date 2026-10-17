extends GdUnitTestSuite
## GameData: índices def_index, validación y el catálogo de prueba de data/.


func test_test_catalog_loads_and_validates() -> void:
	var gd: GameData = load(GameData.DEFAULT_PATH)
	assert_object(gd).is_not_null()
	assert_array(gd.build_index()).is_empty()
	assert_int(gd.def_count()).is_greater_equal(1)
	var idx := gd.index_of(&"infanteria_prueba")
	assert_int(idx).is_equal(0)
	assert_bool(gd.get_def(idx) is UnitDef).is_true()


func test_units_then_buildings_order() -> void:
	var gd := SimTestHelpers.make_game_data()
	assert_int(gd.index_of(&"unidad_test")).is_equal(0)
	assert_int(gd.index_of(&"edificio_test")).is_equal(1)
	assert_int(gd.index_of(&"no_existe")).is_equal(-1)
	assert_object(gd.get_def(2)).is_null()


func test_duplicate_ids_fail() -> void:
	var gd := SimTestHelpers.make_game_data()
	var dup := UnitDef.new()
	dup.id = &"unidad_test"
	gd.units.append(dup)
	assert_array(gd.build_index()).is_not_empty()
	assert_bool(gd.is_built()).is_false()


func test_negative_cost_fails() -> void:
	var gd := SimTestHelpers.make_game_data()
	gd.units[0].cost[gd.resources[0]] = -1
	assert_array(gd.build_index()).is_not_empty()


func test_faction_unit_outside_catalog_fails() -> void:
	var gd := SimTestHelpers.make_game_data()
	var stray := UnitDef.new()
	stray.id = &"suelta"
	gd.factions[0].units.append(stray)
	assert_array(gd.build_index()).is_not_empty()


func test_simulation_copies_stat_tables() -> void:
	var sim := SimTestHelpers.make_sim()
	assert_float(sim.speed_by_def[0]).is_equal(5.0)
	assert_float(sim.speed_by_def[1]).is_equal(0.0)
	assert_float(sim.max_hp_by_def[1]).is_equal(1000.0)
	assert_float(sim.vision_by_def[0]).is_equal(200.0)
