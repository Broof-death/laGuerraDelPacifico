extends GdUnitTestSuite
## Movimiento de tropas en tierra (T-018): formaciones, evitación local, terreno con empuje,
## régimen de marcha, giro, cola de órdenes con Shift y determinismo.

const LAND: int = Terrain.Layer.LAND


# --- Ayudas -------------------------------------------------------------------------------------

## GameData con: def 0 = infantería (3,5 m/s, marcha 10, radio 0,5, giro 360°/s), def 1 =
## caballería (7 m/s, marcha 14, radio 0,8), def 2 = edificio.
func _game_data() -> GameData:
	var res := ResourceDef.new()
	res.id = &"recurso_mov"
	var inf := UnitDef.new()
	inf.id = &"infanteria_mov"
	inf.speed = 3.5
	inf.march_speed = 10.0
	inf.radius = 0.5
	inf.turn_rate = 360.0
	inf.vision_range = 60.0
	inf.max_hp = 60
	var cab := UnitDef.new()
	cab.id = &"caballeria_mov"
	cab.category = UnitDef.Category.CAVALRY
	cab.speed = 7.0
	cab.march_speed = 14.0
	cab.radius = 0.8
	cab.turn_rate = 270.0
	cab.vision_range = 100.0
	cab.max_hp = 80
	var building := BuildingDef.new()
	building.id = &"edificio_mov"
	building.max_hp = 1000
	var fac := FactionDef.new()
	fac.id = &"faccion_mov"
	fac.units = [inf, cab]
	fac.buildings = [building]
	var gd := GameData.new()
	gd.units = [inf, cab]
	gd.buildings = [building]
	gd.resources = [res]
	gd.factions = [fac]
	var errors := gd.build_index()
	assert(errors.is_empty(), str(errors))
	return gd


func _sim(with_map: bool = false) -> Simulation:
	if with_map:
		return Simulation.new(_game_data(), 1, Rect2(), LogicMap.load_shared())
	return Simulation.new(_game_data(), 1, Rect2(0.0, 0.0, 10000.0, 10000.0))


func _block(sim: Simulation, owner: int, def_index: int, n: int, x0: float, z0: float, spacing: float, heading: float = 0.0) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var cols: int = ceili(sqrt(float(n)))
	for i: int in n:
		ids.append(sim.spawn_entity(def_index, owner, x0 + (i % cols) * spacing, z0 + (i / cols) * spacing, heading))
	return ids


## Avanza hasta que todas las entidades estén IDLE (o max_ticks). Devuelve los ticks usados o -1.
func _run_until_idle(sim: Simulation, ids: PackedInt32Array, max_ticks: int) -> int:
	for t: int in max_ticks:
		sim.step()
		var moving: bool = false
		for e: int in ids:
			if sim.store.action[sim.store.slot_of(e)] != SimConstants.Action.IDLE:
				moving = true
				break
		if not moving:
			return t + 1
	return -1


## Mayor solape (m) entre dos entidades de la lista (fuerza bruta: solo para pruebas).
func _worst_overlap(sim: Simulation, ids: PackedInt32Array) -> float:
	var worst: float = 0.0
	for i: int in ids.size():
		var a := sim.store.slot_of(ids[i])
		for j: int in range(i + 1, ids.size()):
			var b := sim.store.slot_of(ids[j])
			var d := Vector2(sim.store.pos_x[a] - sim.store.pos_x[b], sim.store.pos_z[a] - sim.store.pos_z[b]).length()
			var rr: float = sim.radius_by_def[sim.store.def_index[a]] + sim.radius_by_def[sim.store.def_index[b]]
			worst = maxf(worst, rr - d)
	return worst


# --- Formación ----------------------------------------------------------------------------------

func test_formation_layout_rows_columns_and_spacing() -> void:
	var offs := FormationLayout.offsets(10, 2.0, Vector2(1.0, 0.0))
	# 10 unidades: 5 columnas x 2 filas, la primera fila hacia +X (el frente).
	assert_int(FormationLayout.columns(10)).is_equal(5)
	for i: int in 5:
		assert_float(offs[i].x).is_equal_approx(1.0, 0.0001)
		assert_float(offs[i + 5].x).is_equal_approx(-1.0, 0.0001)
	# Puestos separados por al menos el hueco.
	for i: int in offs.size():
		for j: int in range(i + 1, offs.size()):
			assert_float(offs[i].distance_to(offs[j])).is_greater_equal(2.0 - 0.0001)
	# La última fila incompleta va centrada.
	var odd := FormationLayout.offsets(7, 2.0, Vector2(0.0, 1.0))
	var cols: int = FormationLayout.columns(7)
	var sum_lateral: float = 0.0
	for i: int in range(cols, 7):
		sum_lateral += odd[i].x
	assert_float(sum_lateral).is_equal_approx(0.0, 0.0001)
	assert_float(FormationLayout.spacing_for(0.4)).is_equal_approx(1.0, 0.0001)
	assert_float(FormationLayout.spacing_for(1.0)).is_equal_approx(2.5, 0.0001)


func test_formation_assignment_keeps_front_units_in_front() -> void:
	# Bloque que avanza hacia +X: las unidades con mayor x van a la primera fila.
	var pos := PackedVector2Array()
	for i: int in 12:
		pos.append(Vector2(float(i % 4) * 3.0, float(i / 4) * 3.0))
	var slots := FormationLayout.assign(pos, Vector2(1.0, 0.0))
	var cols: int = FormationLayout.columns(12)
	# Cada puesto se usa una vez.
	var used := {}
	for s: int in slots:
		used[s] = true
	assert_int(used.size()).is_equal(12)
	# Las de la primera fila (puestos 0..cols-1) son las de mayor x.
	for i: int in 12:
		if slots[i] < cols:
			assert_float(pos[i].x).is_greater_equal(6.0)
	# Determinista: igual con la misma entrada.
	assert_array(Array(FormationLayout.assign(pos, Vector2(1.0, 0.0)))).is_equal(Array(slots))


func test_group_arrives_in_formation_without_overlap() -> void:
	var sim := _sim()
	# 30 de infantería apretadas (1,2 m entre centros, radio 0,5) mirando a +X.
	var ids := _block(sim, 1, 0, 30, 1000.0, 1000.0, 1.2, PI / 2.0)
	var target := Vector2(1150.0, 1010.0)
	sim.submit_command(1, Command.make_move(1, ids, target))
	var ticks := _run_until_idle(sim, ids, 20 * 60)
	assert_int(ticks).is_greater(0)
	# Nadie encimado (holgura de 1 cm del empuje).
	assert_float(_worst_overlap(sim, ids)).is_less_equal(0.02)
	# Todas en su puesto de la formación (o a menos de la holgura de llegada).
	var spacing := FormationLayout.spacing_for(0.5)
	var center := Vector2.ZERO
	for e: int in ids:
		var s := sim.store.slot_of(e)
		var p := Vector2(sim.store.pos_x[s], sim.store.pos_z[s])
		var d := Vector2(sim.store.dest_x[s], sim.store.dest_z[s])
		assert_float(p.distance_to(d)).is_less_equal(MovementSystem.ARRIVE_SLACK + 1.0)
		center += p
	center /= ids.size()
	# El bloque queda centrado en el destino y con el tamaño de la formación.
	assert_float(center.distance_to(target)).is_less(spacing)
	var cols: int = FormationLayout.columns(30)
	for e: int in ids:
		var s := sim.store.slot_of(e)
		assert_float(Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(target)).is_less(cols * spacing)


func test_fast_units_wait_for_the_slowest() -> void:
	var sim := _sim()
	var ids := _block(sim, 1, 0, 6, 1000.0, 1000.0, 3.0, PI / 2.0)
	ids.append_array(_block(sim, 1, 1, 6, 1000.0, 1020.0, 3.0, PI / 2.0))
	ids = Command.normalize_ids(ids)
	# ATTACK_MOVE (siempre táctico): todos a la velocidad de la infantería (3,5 m/s).
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1100.0, 1010.0), true))
	var max_speed: float = 0.0
	for t: int in 200:
		sim.step()
		for e: int in ids:
			var s := sim.store.slot_of(e)
			max_speed = maxf(max_speed, Vector2(sim.store.vel_x[s], sim.store.vel_z[s]).length())
	assert_float(max_speed).is_less_equal(3.5 + 0.001)
	assert_float(max_speed).is_greater(3.4)


# --- Evitación ----------------------------------------------------------------------------------

func test_avoidance_separates_overlapping_units() -> void:
	var sim := _sim()
	# 40 unidades amontonadas (0,2 m entre centros con radio 0,5) y quietas; dos en el mismo punto.
	var ids := _block(sim, 1, 0, 40, 2000.0, 2000.0, 0.2)
	ids.append(sim.spawn_entity(0, 2, 2000.0, 2000.0))
	assert_float(_worst_overlap(sim, ids)).is_greater(0.9)
	for t: int in 20 * 20:
		sim.step()
	assert_float(_worst_overlap(sim, ids)).is_less_equal(0.02)


func test_column_crossing_idle_block_ends_without_overlap() -> void:
	var sim := _sim()
	# Bloque quieto de otro jugador justo en el camino de una columna en movimiento.
	var idle := _block(sim, 2, 0, 25, 1100.0, 990.0, 1.1)
	var column := _block(sim, 1, 0, 12, 1000.0, 990.0, 1.5, PI / 2.0)
	sim.submit_command(1, Command.make_move(1, column, Vector2(1200.0, 993.0)))
	var all := idle.duplicate()
	all.append_array(column)
	var ticks := _run_until_idle(sim, column, 20 * 90)
	assert_int(ticks).is_greater(0)
	for t: int in 40:
		sim.step()
	assert_float(_worst_overlap(sim, all)).is_less_equal(0.02)
	# La columna llegó al otro lado.
	for e: int in column:
		assert_float(sim.store.pos_x[sim.store.slot_of(e)]).is_greater(1180.0)


func test_push_never_moves_troops_into_water() -> void:
	var sim := _sim(true)
	# Última celda de tierra antes del mar en z = 0 (la costa del mapa provisional).
	var x: float = 0.0
	while sim.map.passable_at(LAND, x + 4.0, 0.0):
		x += 4.0
	assert_bool(sim.map.passable_at(LAND, x, 0.0)).is_true()
	assert_bool(sim.map.passable_at(LAND, x + 16.0, 0.0)).is_false()
	# 60 unidades encimadas contra el agua: el empuje las abriría hacia el mar.
	var ids := PackedInt32Array()
	for i: int in 60:
		ids.append(sim.spawn_entity(0, 1 + i % 2, x - 0.5 + (i % 3) * 0.1, (i / 3) * 0.1))
	var pushed: bool = false
	for t: int in 20 * 15:
		sim.step()
		for e: int in ids:
			var s := sim.store.slot_of(e)
			assert_bool(sim.map.passable_at(LAND, sim.store.pos_x[s], sim.store.pos_z[s])).is_true()
		pushed = pushed or sim.avoidance.last_overlaps > 0
	assert_bool(pushed).is_true()
	# Igual se separaron (hacia tierra).
	assert_float(_worst_overlap(sim, ids)).is_less(0.3)


func test_avoidance_cost_is_not_quadratic() -> void:
	# Con 2000 unidades separadas en formación, los pares revisados crecen lineal con n.
	var sim := _sim()
	_block(sim, 1, 0, 2000, 100.0, 100.0, 1.25)
	sim.step()
	var pairs_2000: int = 0
	for t: int in SimConstants.SLOW_PHASES:
		sim.step()
		pairs_2000 += sim.avoidance.last_pairs
	assert_int(sim.avoidance.last_overlaps).is_equal(0)
	# Unas pocas decenas de pares por unidad como mucho (fuerza bruta serían 2 millones).
	assert_int(pairs_2000).is_less(2000 * 10)


# --- Velocidades y giro -------------------------------------------------------------------------

func test_long_move_uses_march_speed_with_ramp() -> void:
	var sim := _sim()
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(2000.0, 1000.0)))
	sim.step()
	var s := sim.store.slot_of(ids[0])
	# Arranca a la táctica y sube a la de marcha en ~1 s.
	assert_float(sim.store.speed_cur[s]).is_less(4.0)
	for t: int in 25:
		sim.step()
	assert_float(sim.store.speed_cur[s]).is_equal_approx(10.0, 0.001)
	assert_float(sim.store.vel_x[s]).is_equal_approx(10.0, 0.01)


func test_short_move_and_attack_move_stay_tactical() -> void:
	var sim := _sim()
	var a := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	var b := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1100.0, PI / 2.0)])
	sim.submit_command(1, Command.make_move(1, a, Vector2(1150.0, 1000.0)))  # 150 m < 200 m
	sim.submit_command(1, Command.make_move(2, b, Vector2(2000.0, 1100.0), true))  # ATTACK_MOVE
	for t: int in 30:
		sim.step()
	assert_float(sim.store.speed_cur[sim.store.slot_of(a[0])]).is_equal_approx(3.5, 0.001)
	assert_float(sim.store.speed_cur[sim.store.slot_of(b[0])]).is_equal_approx(3.5, 0.001)


func test_enemy_nearby_drops_march_to_tactical() -> void:
	var sim := _sim()
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(3000.0, 1000.0)))
	for t: int in 30:
		sim.step()
	var s := sim.store.slot_of(ids[0])
	assert_float(sim.store.speed_cur[s]).is_equal_approx(10.0, 0.001)
	# Aparece un enemigo a 40 m por delante (dentro de su visión de 60 m y de los 150 m).
	sim.spawn_entity(0, 2, sim.store.pos_x[s] + 40.0, 1005.0)
	for t: int in 30:
		sim.step()
	s = sim.store.slot_of(ids[0])
	assert_float(sim.store.speed_cur[s]).is_equal_approx(3.5, 0.001)


func test_unit_turns_before_advancing() -> void:
	var sim := _sim()
	# Mira a +Z y el destino está hacia -Z (180°): con 360°/s tarda 0,5 s en girar.
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, 0.0)])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1000.0, 900.0)))
	var s := sim.store.slot_of(ids[0])
	for t: int in 6:
		sim.step()
		assert_float(sim.store.pos_z[s]).is_equal(1000.0)
		assert_float(sim.store.vel_z[s]).is_equal(0.0)
	for t: int in 10:
		sim.step()
	assert_float(sim.store.pos_z[s]).is_less(1000.0)
	assert_float(absf(wrapf(sim.store.heading[s] - PI, -PI, PI))).is_less(0.05)


# --- Cola de órdenes (Shift) ----------------------------------------------------------------------

func test_queued_move_runs_after_the_current_one() -> void:
	var sim := _sim()
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1050.0, 1000.0)))
	var q := Command.make_move(2, ids, Vector2(1050.0, 1050.0))
	q.queued = true
	sim.submit_command(1, q)
	sim.step()
	sim.step()
	assert_int(sim.orders.queue_of(ids[0]).size()).is_equal(1)
	var s := sim.store.slot_of(ids[0])
	# Primero va al primer destino (sin desviarse hacia el segundo).
	var reached_first: bool = false
	for t: int in 20 * 60:
		sim.step()
		if Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(Vector2(1050.0, 1000.0)) < 0.5:
			reached_first = true
		if sim.store.action[s] == SimConstants.Action.IDLE and not sim.orders.has_queue(ids[0]):
			break
	assert_bool(reached_first).is_true()
	assert_float(Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(Vector2(1050.0, 1050.0))).is_less(0.5)
	assert_int(sim.orders.active_orders()).is_equal(0)


func test_queued_order_on_idle_unit_applies_now() -> void:
	var sim := _sim()
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	var q := Command.make_move(1, ids, Vector2(1050.0, 1000.0))
	q.queued = true
	sim.submit_command(1, q)
	sim.step()
	assert_bool(sim.orders.has_queue(ids[0])).is_false()
	assert_int(sim.store.action[sim.store.slot_of(ids[0])]).is_equal(SimConstants.Action.MOVE)


func test_order_without_shift_clears_the_queue() -> void:
	var sim := _sim()
	var ids := PackedInt32Array([sim.spawn_entity(0, 1, 1000.0, 1000.0, PI / 2.0)])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1100.0, 1000.0)))
	for i: int in 3:
		var q := Command.make_move(2 + i, ids, Vector2(1100.0, 1100.0 + i * 10.0))
		q.queued = true
		sim.submit_command(1, q)
	sim.step()
	assert_int(sim.orders.queue_of(ids[0]).size()).is_equal(3)
	# STOP sin Shift: se detiene y vacía la cola.
	sim.submit_command(1, Command.make_stop(10, ids))
	sim.step()
	assert_bool(sim.orders.has_queue(ids[0])).is_false()
	assert_int(sim.orders.active_orders()).is_equal(0)
	for t: int in 40:
		sim.step()
	assert_int(sim.store.action[sim.store.slot_of(ids[0])]).is_equal(SimConstants.Action.IDLE)
	# MOVE sin Shift también.
	sim.submit_command(1, Command.make_move(11, ids, Vector2(1100.0, 1000.0)))
	var q2 := Command.make_move(12, ids, Vector2(900.0, 1000.0))
	q2.queued = true
	sim.submit_command(1, q2)
	sim.step()
	assert_int(sim.orders.queue_of(ids[0]).size()).is_equal(1)
	sim.submit_command(1, Command.make_move(13, ids, Vector2(1000.0, 1200.0)))
	sim.step()
	assert_bool(sim.orders.has_queue(ids[0])).is_false()


func test_queued_stop_and_group_regroups_at_waypoint() -> void:
	var sim := _sim()
	var ids := _block(sim, 1, 0, 12, 1000.0, 1000.0, 1.5, PI / 2.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1100.0, 1000.0)))
	var q := Command.make_move(2, ids, Vector2(1100.0, 1100.0))
	q.queued = true
	sim.submit_command(1, q)
	var stop := Command.make_stop(3, ids)
	stop.queued = true
	sim.submit_command(1, stop)
	sim.step()
	for e: int in ids:
		assert_int(sim.orders.queue_of(e).size()).is_equal(2)
	# Al llegar al primer punto, el grupo arranca junto hacia el segundo: UNA ruta compartida.
	var second_routes := {}
	for t: int in 20 * 120:
		sim.step()
		for e: int in ids:
			var s := sim.store.slot_of(e)
			if sim.store.route[s] != 0 and sim.routes.goal_z[sim.store.route[s]] == 1100.0:
				second_routes[sim.store.route[s]] = true
		if _all_idle_without_queue(sim, ids):
			break
	assert_int(second_routes.size()).is_equal(1)
	assert_bool(_all_idle_without_queue(sim, ids)).is_true()
	for e: int in ids:
		var s := sim.store.slot_of(e)
		assert_float(Vector2(sim.store.pos_x[s], sim.store.pos_z[s]).distance_to(Vector2(1100.0, 1100.0))).is_less(15.0)
	assert_int(sim.orders.active_orders()).is_equal(0)


func _all_idle_without_queue(sim: Simulation, ids: PackedInt32Array) -> bool:
	for e: int in ids:
		if sim.store.action[sim.store.slot_of(e)] != SimConstants.Action.IDLE or sim.orders.has_queue(e):
			return false
	return true


func test_dead_unit_leaves_its_queue() -> void:
	var sim := _sim()
	var ids := _block(sim, 1, 0, 2, 1000.0, 1000.0, 3.0, PI / 2.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1100.0, 1000.0)))
	var q := Command.make_move(2, ids, Vector2(1100.0, 1100.0))
	q.queued = true
	sim.submit_command(1, q)
	sim.step()
	assert_int(sim.orders.holders[sim.orders.head(ids[0])]).is_equal(2)
	sim.remove_entity(ids[1])
	assert_int(sim.orders.holders[sim.orders.head(ids[0])]).is_equal(1)
	sim.remove_entity(ids[0])
	assert_int(sim.orders.active_orders()).is_equal(0)


# --- Determinismo -------------------------------------------------------------------------------

func test_movement_avoidance_and_queue_are_deterministic() -> void:
	var hashes := PackedInt64Array()
	for run: int in 2:
		var sim := _sim(true)
		var a := _block(sim, 1, 0, 40, -300.0, 0.0, 1.0)
		var b := _block(sim, 2, 1, 20, -250.0, 30.0, 1.6)
		sim.submit_command(1, Command.make_move(1, a, Vector2(-200.0, 20.0)))
		var q := Command.make_move(2, a, Vector2(-900.0, 300.0))
		q.queued = true
		sim.submit_command(1, q)
		sim.submit_command(2, Command.make_move(1, b, Vector2(-320.0, 0.0), true))
		for t: int in 20 * 40:
			sim.step()
		var h := SimTestHelpers.state_hash(sim)
		hashes.append(hash([h, sim.store.speed_cur.slice(0, sim.store.count), sim.store.stuck.slice(0, sim.store.count)]))
	assert_int(hashes[0]).is_equal(hashes[1])
