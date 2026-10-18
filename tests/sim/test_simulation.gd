extends GdUnitTestSuite
## Simulation: validación de comandos, aplicación en el tick siguiente, registro, movimiento,
## grupos de movimiento, adquisición escalonada, determinismo y tick fijo.

const DT: float = SimConstants.TICK_DT


func _spawn_line(sim: Simulation, owner: int, n: int, x0: float, z0: float, def_index: int = 0) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for i: int in n:
		ids.append(sim.spawn_entity(def_index, owner, x0 + i * 3.0, z0))
	return ids


# --- Validación ---------------------------------------------------------------

func test_valid_move_is_accepted() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 3, 100.0, 100.0)
	assert_int(sim.submit_command(1, Command.make_move(1, ids, Vector2(200, 200)))).is_equal(Command.Reject.OK)
	assert_int(sim.queue.pending_count()).is_equal(1)


func test_rejects_foreign_units() -> void:
	var sim := SimTestHelpers.make_sim()
	var mine := _spawn_line(sim, 1, 2, 100.0, 100.0)
	var theirs := _spawn_line(sim, 2, 2, 300.0, 100.0)
	var mixed := PackedInt32Array([mine[0], theirs[0]])
	assert_int(sim.submit_command(1, Command.make_move(1, mixed, Vector2(50, 50)))).is_equal(Command.Reject.NOT_OWNER)
	assert_int(sim.queue.pending_count()).is_equal(0)
	var rej := sim.queue.drain_rejections()
	assert_int(rej.size()).is_equal(1)
	assert_array(rej[0]).is_equal(PackedInt32Array([1, 1, Command.Reject.NOT_OWNER]))
	assert_int(sim.queue.drain_rejections().size()).is_equal(0)


func test_rejects_unknown_and_dead_entities() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 2, 100.0, 100.0)
	assert_int(sim.submit_command(1, Command.make_move(1, PackedInt32Array([999]), Vector2(1, 1)))).is_equal(Command.Reject.UNKNOWN_ENTITY)
	sim.remove_entity(ids[1])
	assert_int(sim.submit_command(1, Command.make_move(2, ids, Vector2(1, 1)))).is_equal(Command.Reject.UNKNOWN_ENTITY)


func test_rejects_structural_errors() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 3, 100.0, 100.0)
	# Jugador inválido (0 = neutral, 16 fuera de rango).
	assert_int(sim.submit_command(0, Command.make_move(1, ids, Vector2(1, 1)))).is_equal(Command.Reject.INVALID_PLAYER)
	assert_int(sim.submit_command(16, Command.make_move(1, ids, Vector2(1, 1)))).is_equal(Command.Reject.INVALID_PLAYER)
	# Sin entidades.
	assert_int(sim.submit_command(1, Command.make_move(1, PackedInt32Array(), Vector2(1, 1)))).is_equal(Command.Reject.NO_ENTITIES)
	# Ids desordenados o repetidos (sin normalizar).
	var cmd := Command.new()
	cmd.type = Command.Type.MOVE
	cmd.entity_ids = PackedInt32Array([ids[1], ids[0]])
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.UNSORTED_IDS)
	cmd.entity_ids = PackedInt32Array([ids[0], ids[0]])
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.UNSORTED_IDS)
	# Destino fuera del mapa o no finito.
	assert_int(sim.submit_command(1, Command.make_move(1, ids, Vector2(-1, 5)))).is_equal(Command.Reject.TARGET_OUT_OF_BOUNDS)
	assert_int(sim.submit_command(1, Command.make_move(1, ids, Vector2(5, 20000)))).is_equal(Command.Reject.TARGET_OUT_OF_BOUNDS)
	assert_int(sim.submit_command(1, Command.make_move(1, ids, Vector2(NAN, 5)))).is_equal(Command.Reject.TARGET_OUT_OF_BOUNDS)
	# Tipo desconocido o sin implementar.
	cmd = Command.new()
	cmd.entity_ids = ids
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.UNKNOWN_TYPE)
	cmd.type = Command.Type.GATHER
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.UNSUPPORTED_TYPE)
	assert_int(sim.submit_command(1, null)).is_equal(Command.Reject.UNKNOWN_TYPE)
	assert_int(sim.queue.pending_count()).is_equal(0)


func test_rejects_more_than_512_ids() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, SimConstants.MAX_IDS_PER_COMMAND + 1, 10.0, 10.0)
	assert_int(sim.submit_command(1, Command.make_move(1, ids, Vector2(5, 5)))).is_equal(Command.Reject.TOO_MANY_ENTITIES)
	ids.resize(SimConstants.MAX_IDS_PER_COMMAND)
	assert_int(sim.submit_command(1, Command.make_move(2, ids, Vector2(5, 5)))).is_equal(Command.Reject.OK)


func test_rate_limit_30_per_second() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	var other := _spawn_line(sim, 2, 1, 200.0, 100.0)
	for i: int in SimConstants.RATE_LIMIT_COMMANDS_PER_SEC:
		assert_int(sim.submit_command(1, Command.make_stop(i, ids))).is_equal(Command.Reject.OK)
	assert_int(sim.submit_command(1, Command.make_stop(99, ids))).is_equal(Command.Reject.RATE_LIMITED)
	# El límite es por jugador.
	assert_int(sim.submit_command(2, Command.make_stop(1, other))).is_equal(Command.Reject.OK)
	# Pasado un segundo de simulación se renueva.
	for i: int in SimConstants.TICK_RATE:
		sim.step()
	assert_int(sim.submit_command(1, Command.make_stop(100, ids))).is_equal(Command.Reject.OK)


# --- Aplicación y registro -----------------------------------------------------

func test_command_applies_on_next_tick_and_is_logged() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	var s := sim.store.slot_of(ids[0])
	sim.submit_command(1, Command.make_move(5, ids, Vector2(200, 100)))
	# Antes de step() no cambia nada.
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
	sim.step()
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.MOVE)
	assert_float(sim.store.pos_x[s]).is_equal_approx(100.0 + 5.0 * DT, 0.0001)
	var log := sim.queue.get_log()
	assert_int(log.size()).is_equal(1)
	assert_int(log[0].tick).is_equal(0)
	assert_int(log[0].player_id).is_equal(1)
	assert_int(log[0].command.seq).is_equal(5)
	assert_int(sim.tick).is_equal(1)


func test_entity_dead_before_tick_is_ignored() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 2, 100.0, 100.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(200, 100)))
	sim.remove_entity(ids[0])
	sim.step()
	assert_int(sim.store.action[sim.store.slot_of(ids[1])]).is_equal(SimConstants.Action.MOVE)


func test_log_limit() -> void:
	var sim := SimTestHelpers.make_sim()
	sim.queue.max_log_entries = 3
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	for i: int in 5:
		sim.submit_command(1, Command.make_stop(i, ids))
		sim.step()
	var log := sim.queue.get_log()
	assert_int(log.size()).is_equal(3)
	assert_int(log[0].command.seq).is_equal(2)
	assert_int(log[2].tick).is_equal(4)


# --- Movimiento ---------------------------------------------------------------

func test_linear_move_reaches_target_at_speed() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	var s := sim.store.slot_of(ids[0])
	# 30 m en +z a 5 m/s = 6 s = 120 ticks.
	sim.submit_command(1, Command.make_move(1, ids, Vector2(100, 130)))
	for i: int in 60:
		sim.step()
	assert_float(sim.store.pos_z[s]).is_equal_approx(115.0, 0.001)
	assert_float(sim.store.pos_x[s]).is_equal_approx(100.0, 0.001)
	assert_float(sim.store.vel_z[s]).is_equal_approx(5.0, 0.001)
	assert_float(sim.store.heading[s]).is_equal_approx(0.0, 0.0001)
	for i: int in 60:
		sim.step()
	assert_float(sim.store.pos_z[s]).is_equal_approx(130.0, 0.001)
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
	assert_float(sim.store.vel_z[s]).is_equal(0.0)


func test_heading_points_to_target() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(200, 100)))
	sim.step()
	assert_float(sim.store.heading[0]).is_equal_approx(PI / 2.0, 0.0001)


func test_stop_halts_movement() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 1, 100.0, 100.0)
	var s := sim.store.slot_of(ids[0])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(100, 200)))
	for i: int in 10:
		sim.step()
	var z_at_stop: float = sim.store.pos_z[s]
	sim.submit_command(1, Command.make_stop(2, ids))
	for i: int in 10:
		sim.step()
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.IDLE)
	assert_float(sim.store.pos_z[s]).is_equal_approx(z_at_stop, 0.0001)


func test_buildings_do_not_move() -> void:
	var sim := SimTestHelpers.make_sim()
	var b := sim.spawn_entity(1, 1, 100.0, 100.0)
	assert_int(sim.submit_command(1, Command.make_move(1, PackedInt32Array([b]), Vector2(200, 200)))).is_equal(Command.Reject.OK)
	sim.step()
	assert_int(sim.store.action[sim.store.slot_of(b)]).is_equal(SimConstants.Action.IDLE)
	assert_float(sim.store.pos_x[sim.store.slot_of(b)]).is_equal(100.0)


# --- Grupos de movimiento -----------------------------------------------------

func test_small_move_has_no_group() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, SimConstants.MOVE_GROUP_MIN_UNITS - 1, 100.0, 100.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(500, 500)))
	sim.step()
	assert_int(sim.groups.active_count()).is_equal(0)


func test_move_with_8_creates_one_group_in_formation() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 12, 100.0, 100.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(150, 300), true))
	sim.step()
	assert_int(sim.groups.active_count()).is_equal(1)
	var gid: int = sim.store.move_group[sim.store.slot_of(ids[0])]
	assert_int(gid).is_not_equal(0)
	# Todos en el mismo grupo, con destinos distintos alrededor del destino del grupo.
	var dests := {}
	for e: int in ids:
		var s := sim.store.slot_of(e)
		assert_int(sim.store.move_group[s]).is_equal(gid)
		dests[Vector2(sim.store.dest_x[s], sim.store.dest_z[s])] = true
		assert_float(Vector2(sim.store.dest_x[s], sim.store.dest_z[s]).distance_to(Vector2(150, 300))).is_less(30.0)
	assert_int(dests.size()).is_equal(12)
	# Al llegar todos, el grupo se disuelve.
	for i: int in 20 * 60:
		sim.step()
	assert_int(sim.groups.active_count()).is_equal(0)
	for e: int in ids:
		assert_int(sim.store.move_group[sim.store.slot_of(e)]).is_equal(0)


func test_new_order_and_death_release_group() -> void:
	var sim := SimTestHelpers.make_sim()
	var ids := _spawn_line(sim, 1, 10, 100.0, 100.0)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(900, 900)))
	sim.step()
	assert_int(sim.groups.active_count()).is_equal(1)
	sim.remove_entity(ids[0])
	var rest := ids.slice(1)
	sim.submit_command(1, Command.make_stop(2, rest))
	sim.step()
	assert_int(sim.groups.active_count()).is_equal(0)


# --- Adquisición de objetivos (5 Hz escalonada) -------------------------------

func test_acquisition_finds_nearest_enemy_within_four_ticks() -> void:
	var sim := SimTestHelpers.make_sim()
	var a := sim.spawn_entity(0, 1, 1000.0, 1000.0)
	var near := sim.spawn_entity(0, 2, 1050.0, 1000.0)
	sim.spawn_entity(0, 2, 1150.0, 1000.0)          # más lejos
	sim.spawn_entity(0, 1, 999.0, 1000.0)           # aliado
	var far := sim.spawn_entity(0, 3, 1500.0, 1000.0) # fuera de visión (200 m)
	sim.spawn_entity(0, SimConstants.NEUTRAL_PLAYER, 1002.0, 1000.0)
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	assert_int(sim.store.target_id[sim.store.slot_of(a)]).is_equal(near)
	assert_int(sim.store.target_id[sim.store.slot_of(near)]).is_equal(a)
	assert_int(sim.store.target_id[sim.store.slot_of(far)]).is_equal(0)


func _brute_nearest(st: EntityStore, s: int, r: float) -> int:
	var best := 0
	var best_d2 := r * r
	for o: int in st.count:
		if st.owner[o] == st.owner[s]:
			continue
		var dx: float = st.pos_x[o] - st.pos_x[s]
		var dz: float = st.pos_z[o] - st.pos_z[s]
		var d2 := dx * dx + dz * dz
		if d2 < best_d2 or (d2 == best_d2 and best != 0 and st.id[o] < best):
			best_d2 = d2
			best = st.id[o]
	return best


func test_acquisition_matches_brute_force_when_sparse() -> void:
	# Con pocos enemigos por celda (menos de CANDIDATES_PER_CELL) el resultado es exacto.
	var sim := SimTestHelpers.make_sim(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 120:
		sim.spawn_entity(0, rng.randi_range(1, 3), rng.randf_range(2000.0, 3500.0), rng.randf_range(2000.0, 3500.0))
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	var st := sim.store
	for s: int in st.count:
		assert_int(st.target_id[s]).is_equal(_brute_nearest(st, s, 200.0))


func test_acquisition_dense_always_finds_an_enemy_in_range() -> void:
	# Con celdas muy densas el resultado es aproximado, pero si hay un enemigo en rango siempre
	# se elige uno, y siempre es un enemigo en rango.
	var sim := SimTestHelpers.make_sim(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i: int in 1500:
		sim.spawn_entity(0, rng.randi_range(1, 4), rng.randf_range(3000.0, 3300.0), rng.randf_range(3000.0, 3300.0))
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	var st := sim.store
	for s: int in st.count:
		var t: int = st.target_id[s]
		if _brute_nearest(st, s, 200.0) == 0:
			assert_int(t).is_equal(0)
			continue
		assert_int(t).is_not_equal(0)
		var o := st.slot_of(t)
		assert_int(st.owner[o]).is_not_equal(st.owner[s])
		assert_float(Vector2(st.pos_x[o] - st.pos_x[s], st.pos_z[o] - st.pos_z[s]).length()).is_less_equal(200.0)


func test_acquisition_keeps_valid_target_and_reacquires() -> void:
	var sim := SimTestHelpers.make_sim()
	var a := sim.spawn_entity(0, 1, 1000.0, 1000.0)
	var e1 := sim.spawn_entity(0, 2, 1100.0, 1000.0)
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	assert_int(sim.store.target_id[sim.store.slot_of(a)]).is_equal(e1)
	# Aparece uno más cerca: se conserva el objetivo válido.
	var e2 := sim.spawn_entity(0, 2, 1010.0, 1000.0)
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	assert_int(sim.store.target_id[sim.store.slot_of(a)]).is_equal(e1)
	# El objetivo muere: se elige el siguiente.
	sim.remove_entity(e1)
	for i: int in SimConstants.SLOW_PHASES:
		sim.step()
	assert_int(sim.store.target_id[sim.store.slot_of(a)]).is_equal(e2)
	# El objetivo sale de la visión: queda sin objetivo.
	sim.submit_command(2, Command.make_move(1, PackedInt32Array([e2]), Vector2(1000.0, 1250.0)))
	for i: int in 20 * 60:
		sim.step()
	assert_int(sim.store.target_id[sim.store.slot_of(a)]).is_equal(0)



# --- Determinismo y tick fijo --------------------------------------------------

func _run_scenario(seed_value: int) -> int:
	var sim := SimTestHelpers.make_sim(seed_value)
	var a := _spawn_line(sim, 1, 40, 1000.0, 1000.0)
	var b := _spawn_line(sim, 2, 40, 1000.0, 1400.0)
	sim.submit_command(1, Command.make_move(1, a, Vector2(1100, 1500), true))
	sim.submit_command(2, Command.make_move(1, b.slice(0, 5), Vector2(1000, 900)))
	for i: int in 50:
		sim.step()
	sim.remove_entity(a[3])
	sim.submit_command(2, Command.make_stop(2, b.slice(0, 2)))
	for i: int in 50:
		sim.step()
	return SimTestHelpers.state_hash(sim)


func test_step_is_deterministic() -> void:
	assert_int(_run_scenario(5)).is_equal(_run_scenario(5))


func test_step_does_not_need_scene_tree() -> void:
	# La simulación es un RefCounted sin nodos: se crea y avanza sin escena.
	var sim := SimTestHelpers.make_sim()
	assert_bool(sim is RefCounted).is_true()
	sim.step()
	assert_int(sim.tick).is_equal(1)


func test_tick_accumulator_is_independent_of_fps() -> void:
	# 1 s a 60 FPS y a 15 FPS da los mismos 20 ticks.
	for fps: float in [60.0, 15.0, 144.0]:
		var acc := TickAccumulator.new()
		var ticks := 0
		for f: int in int(fps):
			ticks += acc.advance(1.0 / fps)
		assert_int(ticks).is_between(19, 20)
		assert_int(acc.dropped_ticks).is_equal(0)


func test_tick_accumulator_caps_ticks_per_frame() -> void:
	var acc := TickAccumulator.new()
	# Un frame de 1 s: solo 3 ticks, el resto se descarta.
	assert_int(acc.advance(1.0)).is_equal(SimConstants.MAX_TICKS_PER_FRAME)
	assert_int(acc.dropped_ticks).is_equal(20 - SimConstants.MAX_TICKS_PER_FRAME)
	acc.time_scale = 0.0
	assert_int(acc.advance(1.0)).is_equal(0)


# --- ATTACK provisional (T-007) -------------------------------------------------

func test_attack_moves_towards_target_until_combat_exists() -> void:
	var sim := SimTestHelpers.make_sim()
	var mine := _spawn_line(sim, 1, 2, 100.0, 100.0)
	var theirs := _spawn_line(sim, 2, 1, 160.0, 100.0)
	var cmd := Command.new()
	cmd.type = Command.Type.ATTACK
	cmd.seq = 1
	cmd.entity_ids = mine
	cmd.target_id = theirs[0]
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.OK)
	sim.step()
	var s: int = sim.store.slot_of(mine[0])
	assert_int(sim.store.action[s]).is_equal(SimConstants.Action.MOVE)
	assert_float(sim.store.dest_x[s]).is_equal_approx(160.0, 0.01)
	# Objetivo inexistente.
	cmd.target_id = 999
	assert_int(sim.submit_command(1, cmd)).is_equal(Command.Reject.UNKNOWN_ENTITY)
