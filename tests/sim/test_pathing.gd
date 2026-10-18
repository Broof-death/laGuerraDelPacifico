extends GdUnitTestSuite
## Rutas por tierra y por mar (T-013): mapa lógico, HPA*, ajuste del destino, validación del
## terreno en el movimiento, determinismo y cola de 8 búsquedas por tick. Usa el mapa provisional
## de data/map/ (TestMapBuilder) y un mapa chico sintético para comparar el HPA* con un A* plano.

const LAND: int = Terrain.Layer.LAND
const SEA: int = Terrain.Layer.SEA
## Paso del muestreo denso de los segmentos (comprobación independiente del supercover).
const SAMPLE_STEP: float = 1.0

var _map: LogicMap


func before() -> void:
	_map = LogicMap.load_shared()


# --- Ayudas -------------------------------------------------------------------------------------

## true si todos los puntos de la ruta (desde el origen) y todos los segmentos, muestreados cada
## metro, están en celdas transitables para la capa. Si falla, informa dónde.
func _route_valid(map: LogicMap, layer: int, sx: float, sz: float, pts: PackedFloat64Array) -> bool:
	var px: float = sx
	var pz: float = sz
	for i: int in range(0, pts.size(), 2):
		var qx: float = pts[i]
		var qz: float = pts[i + 1]
		if not map.passable_at(layer, qx, qz):
			push_warning("punto de paso %d (%.1f, %.1f) intransitable" % [i / 2, qx, qz])
			return false
		var len: float = Vector2(qx - px, qz - pz).length()
		var n: int = maxi(1, ceili(len / SAMPLE_STEP))
		for k: int in n + 1:
			var t: float = float(k) / n
			if not map.passable_at(layer, lerpf(px, qx, t), lerpf(pz, qz, t)):
				push_warning("segmento %d pisa terreno prohibido en (%.1f, %.1f)" % [i / 2, lerpf(px, qx, t), lerpf(pz, qz, t)])
				return false
		px = qx
		pz = qz
	return true


func _spawn_block(sim: Simulation, owner: int, def_index: int, n: int, x0: float, z0: float, spacing: float = 3.0) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var cols: int = ceili(sqrt(float(n)))
	for i: int in n:
		ids.append(sim.spawn_entity(def_index, owner, x0 + (i % cols) * spacing, z0 + (i / cols) * spacing))
	return ids


## Avanza hasta que todas las entidades queden IDLE (o max_ticks) comprobando en CADA tick que
## ninguna pisa terreno prohibido para su capa. Devuelve los ticks usados, o -1 si alguna pisó.
func _run_checking_terrain(sim: Simulation, ids: PackedInt32Array, max_ticks: int) -> int:
	for t: int in max_ticks:
		sim.step()
		var moving: bool = false
		for e: int in ids:
			var s: int = sim.store.slot_of(e)
			var layer: int = sim.layer_by_def[sim.store.def_index[s]]
			if not sim.map.passable_at(layer, sim.store.pos_x[s], sim.store.pos_z[s]):
				push_warning("la entidad %d (capa %d) pisó (%.1f, %.1f) en el tick %d" % [e, layer, sim.store.pos_x[s], sim.store.pos_z[s], sim.tick])
				return -1
			if sim.store.action[s] != SimConstants.Action.IDLE:
				moving = true
		if not moving:
			return t + 1
	return max_ticks


# --- Mapa lógico -----------------------------------------------------------------------------------

func test_test_map_has_coast_bay_peninsula_and_obstacles() -> void:
	assert_object(_map).is_not_null()
	# Cerca de los ejércitos de prueba: tierra al oeste de x ≈ 250 y mar al este.
	assert_bool(_map.passable_at(LAND, 0.0, 0.0)).is_true()
	assert_bool(_map.passable_at(SEA, 400.0, 0.0)).is_true()
	assert_bool(_map.passable_at(LAND, 400.0, 0.0)).is_false()
	# Bahía: mar al oeste de la costa base; península: tierra al este.
	assert_bool(_map.passable_at(SEA, -100.0, -1500.0)).is_true()
	assert_bool(_map.passable_at(LAND, 1200.0, 1700.0)).is_true()
	# Cerro de prueba y quebrada infranqueables; el vado sí se cruza.
	assert_int(_map.kind_at(-650.0, 120.0)).is_equal(Terrain.Kind.IMPASSABLE)
	assert_bool(_map.passable_at(LAND, -3000.0, TestMapBuilder.ravine_z(-3000.0))).is_false()
	assert_int(_map.kind_at(TestMapBuilder.FORD_X, TestMapBuilder.ravine_z(TestMapBuilder.FORD_X))).is_equal(Terrain.Kind.FORD)
	# Fuera de la zona jugable.
	assert_int(_map.kind_at(-20000.0, 0.0)).is_equal(Terrain.Kind.OUT)
	# Altura: el cerro sobresale, el mar profundo está a -20 m.
	assert_float(_map.height_at(-650.0, 120.0)).is_greater(40.0)
	assert_float(_map.height_at(10000.0, 0.0)).is_equal_approx(-20.0, 0.01)


func test_sparse_storage_and_memory() -> void:
	var mem: Dictionary = _map.memory_bytes()
	var loaded: int = mem["sectors_loaded"]
	assert_int(loaded).is_greater(0)
	assert_int(loaded).is_less(48)  # los 48 sectores jugables no tienen todos datos
	# 192 KB por sector con datos (ADR-009 §6) más las tablas de los uniformes.
	assert_int(mem["grid"]).is_equal(loaded * MapSector.CELLS * 3 + 1024 * 5)
	print("MAP_MEMORY sectores con datos %d de 48, rejilla %.2f MB, grafos HPA* %.2f MB (tierra %d nodos, mar %d nodos)" % [
		loaded, mem["grid"] / 1048576.0, mem["graphs"] / 1048576.0,
		_map.graph(LAND).node_count(), _map.graph(SEA).node_count()])


func test_segment_passable_supercover_corner() -> void:
	# Dos celdas de tierra en diagonal con agua en las otras dos: el segmento que pasa por la
	# esquina común no se acepta.
	var m := LogicMap.create_uniform(Terrain.Kind.DEEP_SEA)
	m.set_cell(4100, 4100, Terrain.Kind.LAND)
	m.set_cell(4101, 4101, Terrain.Kind.LAND)
	var a := Vector2(MapGrid.terrain_center(4100), MapGrid.terrain_center(4100))
	var b := Vector2(MapGrid.terrain_center(4101), MapGrid.terrain_center(4101))
	assert_bool(m.segment_passable(LAND, a.x, a.y, b.x, b.y)).is_false()
	m.set_cell(4101, 4100, Terrain.Kind.LAND)
	m.set_cell(4100, 4101, Terrain.Kind.LAND)
	assert_bool(m.segment_passable(LAND, a.x, a.y, b.x, b.y)).is_true()


# --- Rutas en las dos capas ------------------------------------------------------------------------

func test_land_route_around_hill_is_valid() -> void:
	var finder := PathFinder.new(_map)
	var res := finder.find(LAND, 0.0, 120.0, -1000.0, 120.0)
	assert_bool(res.ok).is_true()
	assert_bool(res.adjusted).is_false()
	assert_bool(_route_valid(_map, LAND, 0.0, 120.0, res.points)).is_true()
	# Rodea el cerro: más larga que la recta, pero no mucho más.
	var length := res.length_from(0.0, 120.0)
	assert_float(length).is_greater(1000.0)
	assert_float(length).is_less(1300.0)
	assert_float(res.points[res.points.size() - 2]).is_equal(-1000.0)


func test_long_land_route_crosses_ravine_by_valid_terrain() -> void:
	var finder := PathFinder.new(_map)
	var a := TestMapBuilder.LAND_NORTH
	var b := TestMapBuilder.LAND_SOUTH
	var res := finder.find(LAND, a.x, a.y, b.x, b.y)
	assert_bool(res.ok).is_true()
	assert_int(res.kind).is_equal(PathFinder.Kind.HPA)
	assert_bool(_route_valid(_map, LAND, a.x, a.y, res.points)).is_true()
	assert_float(res.length_from(a.x, a.y)).is_greater(28000.0)


func test_sea_route_port_to_port_is_valid() -> void:
	var finder := PathFinder.new(_map)
	var a := TestMapBuilder.PORT_NORTH
	var b := TestMapBuilder.PORT_SOUTH
	var res := finder.find(SEA, a.x, a.y, b.x, b.y)
	assert_bool(res.ok).is_true()
	assert_int(res.kind).is_equal(PathFinder.Kind.HPA)
	assert_bool(_route_valid(_map, SEA, a.x, a.y, res.points)).is_true()
	# Rodea la península (punta en x ≈ 1750).
	var max_x: float = -INF
	for i: int in range(0, res.points.size(), 2):
		max_x = maxf(max_x, res.points[i])
	assert_float(max_x).is_greater(1700.0)
	assert_float(res.length_from(a.x, a.y)).is_greater(29000.0)


func test_sea_route_around_peninsula_is_valid() -> void:
	var finder := PathFinder.new(_map)
	var res := finder.find(SEA, 500.0, 1200.0, 500.0, 2300.0)
	assert_bool(res.ok).is_true()
	assert_bool(_route_valid(_map, SEA, 500.0, 1200.0, res.points)).is_true()
	assert_float(res.length_from(500.0, 1200.0)).is_greater(2500.0)


# --- Destino inválido ---------------------------------------------------------------------------------

func test_troops_to_sea_are_adjusted_to_nearest_land() -> void:
	var finder := PathFinder.new(_map)
	var res := finder.find(LAND, 0.0, 0.0, 400.0, 0.0)
	assert_bool(res.ok).is_true()
	assert_bool(res.adjusted).is_true()
	assert_bool(_map.passable_at(LAND, res.goal.x, res.goal.y)).is_true()
	# El punto válido más cercano: en la costa (x ≈ 250), a la altura pedida.
	assert_float(res.goal.x).is_between(230.0, 251.0)
	assert_float(absf(res.goal.y)).is_less(16.0)
	assert_bool(_route_valid(_map, LAND, 0.0, 0.0, res.points)).is_true()


func test_ship_to_land_is_adjusted_to_nearest_water() -> void:
	var finder := PathFinder.new(_map)
	var res := finder.find(SEA, 600.0, 0.0, 100.0, 0.0)
	assert_bool(res.ok).is_true()
	assert_bool(res.adjusted).is_true()
	assert_bool(_map.passable_at(SEA, res.goal.x, res.goal.y)).is_true()
	assert_float(res.goal.x).is_between(250.0, 270.0)
	assert_bool(_route_valid(_map, SEA, 600.0, 0.0, res.points)).is_true()


func test_ship_far_inland_is_rejected() -> void:
	var finder := PathFinder.new(_map)
	var res := finder.find(SEA, 600.0, 0.0, -5000.0, 0.0)
	assert_bool(res.ok).is_false()
	assert_int(res.reason).is_equal(Command.Reject.UNREACHABLE)


func test_unreachable_order_is_rejected_to_the_player() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ship := sim.spawn_entity(1, 1, 600.0, 0.0)
	assert_int(sim.submit_command(1, Command.make_move(7, PackedInt32Array([ship]), Vector2(-5000.0, 0.0)))).is_equal(Command.Reject.OK)
	# Buscar la celda válida más cercana sin encontrarla recorre 64 anillos: con el presupuesto
	# de trabajo por tick (T-018) puede llevar varios ticks.
	var rej: Array[PackedInt32Array] = []
	for t: int in 40:
		sim.step()
		rej = sim.queue.drain_rejections()
		if not rej.is_empty():
			break
	assert_int(rej.size()).is_equal(1)
	assert_array(Array(rej[0])).is_equal([1, 7, Command.Reject.UNREACHABLE])
	sim.step()
	var s := sim.store.slot_of(ship)
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
	assert_float(sim.store.pos_x[s]).is_equal(600.0)
	assert_int(sim.routes.active_count()).is_equal(0)


# --- Movimiento: tropas nunca al mar, buques nunca a tierra ---------------------------------------

func test_troops_go_around_the_bay_without_touching_water() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ids := _spawn_block(sim, 1, 0, 12, -110.0, -900.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(-100.0, -2100.0)))
	var ticks := _run_checking_terrain(sim, ids, 20 * 900)
	assert_int(ticks).is_greater(0)
	# Llegaron (o quedaron cerca de su puesto).
	for e: int in ids:
		var s := sim.store.slot_of(e)
		assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
		assert_float(Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(Vector2(-100.0, -2100.0))).is_less(40.0)


func test_ships_go_around_the_peninsula_without_touching_land() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ids := _spawn_block(sim, 1, 1, 8, 480.0, 1180.0, 25.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(500.0, 2300.0)))
	var ticks := _run_checking_terrain(sim, ids, 20 * 900)
	assert_int(ticks).is_greater(0)
	for e: int in ids:
		var s := sim.store.slot_of(e)
		assert_float(Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(Vector2(500.0, 2300.0))).is_less(120.0)


func test_mixed_order_splits_into_land_and_sea_routes() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var troops := _spawn_block(sim, 1, 0, 4, 100.0, 0.0)
	var ships := _spawn_block(sim, 1, 1, 2, 500.0, 0.0, 40.0)
	var all := troops.duplicate()
	all.append_array(ships)
	# Orden al mar: los buques van, las tropas se quedan en la costa.
	sim.submit_command(1, Command.make_move(1, all, Vector2(700.0, 0.0)))
	var ticks := _run_checking_terrain(sim, all, 20 * 200)
	assert_int(ticks).is_greater(0)
	for e: int in troops:
		var s := sim.store.slot_of(e)
		assert_float(sim.store.pos_x[s]).is_between(200.0, 256.0)
	for e: int in ships:
		var s := sim.store.slot_of(e)
		assert_float(sim.store.pos_x[s]).is_greater(650.0)


func test_movement_blocks_a_step_into_water_even_without_route() -> void:
	# Validación en el movimiento, no solo en el destino: una unidad con un objetivo inmediato en
	# el mar (puesto a mano) se detiene en la costa.
	var sim := SimTestHelpers.make_map_sim()
	var e := sim.spawn_entity(0, 1, 230.0, 0.0)
	var s := sim.store.slot_of(e)
	sim.store.action[s] = SimConstants.Action.MOVE
	sim.store.dest_x[s] = 600.0
	sim.store.wp_x[s] = 600.0
	sim.store.dest_z[s] = 0.0
	sim.store.wp_z[s] = 0.0
	for t: int in 200:
		sim.step()
		assert_bool(sim.map.passable_at(LAND, sim.store.pos_x[s], sim.store.pos_z[s])).is_true()
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
	# La última celda de tierra es [240, 256); la siguiente ya es mar.
	assert_float(sim.store.pos_x[s]).is_less(256.0)


# --- Determinismo y cola -----------------------------------------------------------------------------

func test_paths_are_deterministic() -> void:
	var a := PathFinder.new(_map)
	var b := PathFinder.new(_map)
	var cases: Array[PackedFloat64Array] = [
		PackedFloat64Array([LAND, 0.0, 120.0, -1000.0, 120.0]),
		PackedFloat64Array([LAND, TestMapBuilder.LAND_NORTH.x, TestMapBuilder.LAND_NORTH.y, TestMapBuilder.LAND_SOUTH.x, TestMapBuilder.LAND_SOUTH.y]),
		PackedFloat64Array([SEA, TestMapBuilder.PORT_NORTH.x, TestMapBuilder.PORT_NORTH.y, TestMapBuilder.PORT_SOUTH.x, TestMapBuilder.PORT_SOUTH.y]),
		PackedFloat64Array([SEA, 600.0, 0.0, 100.0, 0.0]),
	]
	for c: PackedFloat64Array in cases:
		var ra := a.find(int(c[0]), c[1], c[2], c[3], c[4])
		var rb := b.find(int(c[0]), c[1], c[2], c[3], c[4])
		# Repetida en la misma instancia (con cachés ya llenas) también da lo mismo.
		var rc := a.find(int(c[0]), c[1], c[2], c[3], c[4])
		assert_array(Array(ra.points)).is_equal(Array(rb.points))
		assert_array(Array(ra.points)).is_equal(Array(rc.points))


func test_simulation_with_routes_is_deterministic() -> void:
	var hashes := PackedInt64Array()
	for run: int in 2:
		var sim := SimTestHelpers.make_map_sim(3)
		var troops := _spawn_block(sim, 1, 0, 20, -60.0, 60.0)
		var ships := _spawn_block(sim, 2, 1, 6, 400.0, -100.0, 30.0)
		sim.submit_command(1, Command.make_move(1, troops, Vector2(-1000.0, 130.0)))
		sim.submit_command(2, Command.make_move(1, ships, Vector2(500.0, 2300.0)))
		for t: int in 20 * 60:
			sim.step()
		hashes.append(SimTestHelpers.state_hash(sim))
	assert_int(hashes[0]).is_equal(hashes[1])


func test_at_most_8_searches_per_tick() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ids := PackedInt32Array()
	for i: int in 20:
		ids.append(sim.spawn_entity(0, 1, -200.0 + i * 5.0, 300.0))
	# 20 órdenes de una unidad (20 rutas) con destinos detrás del cerro (búsqueda real).
	for i: int in 20:
		assert_int(sim.submit_command(1, Command.make_move(i + 1, PackedInt32Array([ids[i]]), Vector2(-1000.0, 100.0 + i * 4.0)), 0)).is_equal(Command.Reject.OK)
	var done: int = 0
	for t: int in 200:
		sim.step()
		# Como mucho 8 búsquedas terminadas por tick y el trabajo dentro del presupuesto (más el
		# exceso de un paso atómico, que se descuenta del tick siguiente).
		assert_int(sim.routes.last_searches).is_less_equal(RouteStore.MAX_SEARCHES_PER_TICK)
		done += sim.routes.last_searches
		# Las que esperan siguen quietas.
		for e: int in ids:
			var s := sim.store.slot_of(e)
			if sim.store.route[s] != 0 and sim.routes.status[sim.store.route[s]] == RouteStore.Status.PENDING:
				assert_float(sim.store.vel_x[s]).is_equal(0.0)
				assert_float(sim.store.pos_x[s]).is_equal(-200.0 + ids.find(e) * 5.0)
		if sim.routes.pending_count() == 0:
			break
	assert_int(done).is_equal(20)
	assert_int(sim.routes.pending_count()).is_equal(0)


func test_max_8_searches_even_with_spare_budget() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ids := PackedInt32Array()
	for i: int in 20:
		ids.append(sim.spawn_entity(0, 1, -200.0 + i * 5.0, 300.0))
	# Destinos en línea recta (búsquedas muy baratas): el tope de 8 por tick manda.
	for i: int in 20:
		sim.submit_command(1, Command.make_move(i + 1, PackedInt32Array([ids[i]]), Vector2(-200.0 + i * 5.0, 360.0)), 0)
	sim.step()
	assert_int(sim.routes.last_searches).is_equal(8)
	sim.step()
	assert_int(sim.routes.last_searches).is_equal(8)
	sim.step()
	assert_int(sim.routes.last_searches).is_equal(4)
	assert_int(sim.routes.pending_count()).is_equal(0)


func test_one_route_per_group_not_per_unit() -> void:
	var sim := SimTestHelpers.make_map_sim()
	var ids := _spawn_block(sim, 1, 0, 30, -60.0, 60.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(-1000.0, 130.0)))
	for t: int in 20:
		sim.step()
		if sim.routes.pending_count() == 0:
			break
	assert_int(sim.routes.active_count()).is_equal(1)
	assert_int(sim.routes.total_searches).is_equal(1)
	assert_int(sim.groups.active_count()).is_equal(1)


# --- HPA* frente a A* plano en un mapa chico ------------------------------------------------------

## Mapa de 3 x 3 clusters (96 x 96 celdas) con muros con huecos, manchas y un bolsón cerrado;
## el resto del mundo es OUT.
func _small_map() -> LogicMap:
	var m := LogicMap.create_uniform(Terrain.Kind.OUT)
	var ox: int = 4096
	var oz: int = 4096
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for z: int in 96:
		for x: int in 96:
			var kind: int = Terrain.Kind.LAND
			# Muro vertical en x = 40 con dos huecos; muro horizontal en z = 60 con un hueco.
			if x == 40 and not (z >= 10 and z < 13) and not (z >= 70 and z < 72):
				kind = Terrain.Kind.IMPASSABLE
			if z == 60 and x > 40 and not (x >= 80 and x < 84):
				kind = Terrain.Kind.IMPASSABLE
			# Bolsón cerrado (anillo) alrededor de (20, 80).
			if maxi(absi(x - 20), absi(z - 80)) == 6:
				kind = Terrain.Kind.IMPASSABLE
			# Vado (más caro) en una franja.
			if x >= 60 and x < 64 and z < 60:
				kind = Terrain.Kind.FORD
			m.set_cell(ox + x, oz + z, kind)
	# Manchas al azar.
	for i: int in 40:
		var cx: int = rng.randi_range(0, 95)
		var cz: int = rng.randi_range(0, 95)
		for dz: int in range(-2, 3):
			for dx: int in range(-2, 3):
				if cx + dx >= 0 and cx + dx < 96 and cz + dz >= 0 and cz + dz < 96 and dx * dx + dz * dz <= 4:
					m.set_cell(ox + cx + dx, oz + cz + dz, Terrain.Kind.IMPASSABLE)
	var rect := Rect2i(ox / 32, oz / 32, 3, 3)
	m.set_graph(LAND, PathGraphBuilder.build(m, LAND, rect))
	return m


func test_hpa_is_coherent_with_flat_astar() -> void:
	var m := _small_map()
	var finder := PathFinder.new(m)
	var costs := m.region_costs(LAND, 4096, 4096, 96, 96)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var compared: int = 0
	var unreachable: int = 0
	var worst_ratio: float = 0.0
	var sum_ratio: float = 0.0
	for i: int in 300:
		var a := Vector2i(rng.randi_range(0, 95), rng.randi_range(0, 95))
		var b := Vector2i(rng.randi_range(0, 95), rng.randi_range(0, 95))
		if costs[a.y * 96 + a.x] <= 0.0 or costs[b.y * 96 + b.x] <= 0.0:
			continue
		var flat := GridSearch.astar(costs, 96, 96, a.y * 96 + a.x, b.y * 96 + b.x, Terrain.MIN_COST[LAND])
		var sx: float = MapGrid.terrain_center(4096 + a.x)
		var sz: float = MapGrid.terrain_center(4096 + a.y)
		var tx: float = MapGrid.terrain_center(4096 + b.x)
		var tz: float = MapGrid.terrain_center(4096 + b.y)
		# Misma decisión de alcanzabilidad: sin ajuste, A* plano y componentes coinciden.
		var same_comp: bool = finder.component_of(LAND, 4096 + a.x, 4096 + a.y) == finder.component_of(LAND, 4096 + b.x, 4096 + b.y)
		assert_bool(same_comp).is_equal(not flat.is_empty())
		if flat.is_empty():
			unreachable += 1
			continue
		var res := finder.find(LAND, sx, sz, tx, tz)
		assert_bool(res.ok).is_true()
		assert_bool(res.adjusted).is_false()
		assert_bool(_route_valid(m, LAND, sx, sz, res.points)).is_true()
		# Costo de la ruta plana (óptima en la rejilla) frente al largo de la del HPA*.
		var flat_len: float = 0.0
		for k: int in range(1, flat.size()):
			var p := Vector2(flat[k - 1] % 96, flat[k - 1] / 96)
			var q := Vector2(flat[k] % 96, flat[k] / 96)
			flat_len += p.distance_to(q) * MapGrid.TERRAIN_CELL
		var hpa_len := res.length_from(sx, sz)
		if flat_len > 0.0:
			var ratio: float = hpa_len / flat_len
			worst_ratio = maxf(worst_ratio, ratio)
			sum_ratio += ratio
			compared += 1
	print("HPA_VS_ASTAR %d rutas comparadas, %d inalcanzables; largo HPA*/A* plano: media %.3f, peor %.3f" % [
		compared, unreachable, sum_ratio / maxi(compared, 1), worst_ratio])
	assert_int(compared).is_greater(100)
	assert_int(unreachable).is_greater(0)
	# El HPA* suavizado no es óptimo, pero queda cerca del A* plano.
	assert_float(sum_ratio / compared).is_less(1.08)
	assert_float(worst_ratio).is_less(1.35)


# --- Rendimiento -----------------------------------------------------------------------------------

func _time_search(finder: PathFinder, layer: int, a: Vector2, b: Vector2, reps: int) -> Array:
	var times := PackedInt64Array()
	var res: PathFinder.Result
	for i: int in reps:
		var t0 := Time.get_ticks_usec()
		res = finder.find(layer, a.x, a.y, b.x, b.y)
		times.append(Time.get_ticks_usec() - t0)
	times.sort()
	return [times[times.size() / 2], times[times.size() - 1], res]


func test_search_performance() -> void:
	var finder := PathFinder.new(_map)
	# Corta: dentro de un cluster de 512 m, rodeando la esquina del cerro.
	var short := _time_search(finder, LAND, Vector2(-800.0, 200.0), Vector2(-560.0, 260.0), 15)
	# Media: ~2 km rodeando la bahía.
	var medium := _time_search(finder, LAND, Vector2(-100.0, -700.0), Vector2(-800.0, -2400.0), 15)
	# Larga por tierra: de norte a sur (~28 km, quebrada y cerros).
	var long_land := _time_search(finder, LAND, TestMapBuilder.LAND_NORTH, TestMapBuilder.LAND_SOUTH, 7)
	# Larga por mar: puerto a puerto (~29 km, península e islas).
	var long_sea := _time_search(finder, SEA, TestMapBuilder.PORT_NORTH, TestMapBuilder.PORT_SOUTH, 7)
	var rows := [["corta", short, Vector2(-800.0, 200.0)], ["media", medium, Vector2(-100.0, -700.0)],
			["larga tierra", long_land, TestMapBuilder.LAND_NORTH], ["larga mar", long_sea, TestMapBuilder.PORT_NORTH]]
	for row: Array in rows:
		var r: PathFinder.Result = row[1][2]
		var start: Vector2 = row[2]
		print("PATH_PERF %s: mediana %.2f ms, máx %.2f ms, %s, %.0f m, %d puntos, %d nodos abstractos, %d celdas locales" % [
			row[0], row[1][0] / 1000.0, row[1][1] / 1000.0, PathFinder.Kind.keys()[r.kind], r.length_from(start.x, start.y),
			r.points.size() / 2, r.abstract_expanded, r.local_expanded])
		assert_bool(r.ok).is_true()
	assert_int(short[2].kind).is_equal(PathFinder.Kind.LOCAL)
	assert_int(medium[2].kind).is_equal(PathFinder.Kind.HPA)
	# Una búsqueda larga (~30 km) debe caber holgadamente en un tick (build de depuración).
	assert_int(long_sea[0]).is_less(20000)
	assert_int(long_land[0]).is_less(20000)
	assert_int(medium[0]).is_less(5000)
