extends GdUnitTestSuite
## Selección y órdenes del cliente sin GPU (T-007): proyección con una cámara sintética, selección
## por rectángulo y por clic, Shift para sumar o quitar, grupos de control, armado de comandos
## (bloques de 512 ids, queued) y el costo de la selección por rectángulo con 2000 unidades.

const VIEW := Vector2(1920, 1080)
const ME: int = 1
const ENEMY: int = 2


## Cámara a 120 m de altura y 120 m al sur (+z) del origen, mirando al origen.
func _proj() -> ScreenProjector:
	var eye := Vector3(0, 120, 120)
	var xf := Transform3D(Basis(), eye).looking_at(Vector3.ZERO, Vector3.UP)
	return ScreenProjector.from_params(xf, 50.0, 1.0, 4000.0, VIEW)


## Tablas fijas: def 0 = infantería (unidad), def 1 = caballería (unidad), def 2 = edificio.
func _query() -> SelectionQuery:
	var q := SelectionQuery.new()
	q.height_by_def = PackedFloat32Array([1.0, 1.2, 3.0])
	q.radius_by_def = PackedFloat32Array([0.5, 1.0, 6.0])
	q.mobile_by_def = PackedByteArray([1, 1, 0])
	return q


func _state() -> SyntheticClientState:
	return SyntheticClientState.new()


# --- Proyección ---------------------------------------------------------------------

func test_projects_look_target_to_screen_center() -> void:
	var p := _proj()
	var sp := p.project(Vector3.ZERO)
	assert_float(sp.x).is_equal_approx(VIEW.x * 0.5, 0.5)
	assert_float(sp.y).is_equal_approx(VIEW.y * 0.5, 0.5)
	assert_float(sp.z).is_greater(0.0)
	# Más a la derecha (+x) en el mundo = más a la derecha en pantalla; más al norte (-z) = más arriba.
	assert_float(p.project(Vector3(10, 0, 0)).x).is_greater(sp.x)
	assert_float(p.project(Vector3(0, 0, -10)).y).is_less(sp.y)
	# Detrás de la cámara.
	assert_float(p.project(Vector3(0, 120, 400)).z).is_less_equal(0.0)


func test_ground_point_inverts_projection() -> void:
	var p := _proj()
	for world: Vector3 in [Vector3.ZERO, Vector3(35, 0, -20), Vector3(-60, 0, 40)]:
		var sp := p.project(world)
		var hit: Variant = p.ground_point(Vector2(sp.x, sp.y))
		assert_bool(hit != null).is_true()
		assert_vector(hit as Vector3).is_equal_approx(world, Vector3(0.05, 0.05, 0.05))
	# Mirando por encima del horizonte, el rayo no corta el suelo.
	var xf := Transform3D(Basis(), Vector3(0, 50, 0)).looking_at(Vector3(0, 80, -100), Vector3.UP)
	var up := ScreenProjector.from_params(xf, 50.0, 1.0, 4000.0, VIEW)
	assert_bool(up.ground_point(VIEW * 0.5) == null).is_true()


func test_matches_camera3d_unproject_position() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(VIEW)
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 1.0
	cam.far = 4000.0
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis(), Vector3(10, 80, 90)).looking_at(Vector3(5, 0, -10), Vector3.UP)
	cam.current = true
	var p := ScreenProjector.from_camera(cam)
	for world: Vector3 in [Vector3(0, 0, 0), Vector3(30, 1, -40), Vector3(-25, 0, 10)]:
		var mine := p.project(world)
		var godot := cam.unproject_position(world)
		assert_vector(Vector2(mine.x, mine.y)).is_equal_approx(godot, Vector2(0.5, 0.5))
		var ray := cam.project_ray_normal(godot)
		assert_vector(p.ray_direction(godot)).is_equal_approx(ray, Vector3(0.001, 0.001, 0.001))


# --- Rectángulo y clic --------------------------------------------------------------

func test_rect_selects_only_own_units_inside() -> void:
	var st := _state()
	var p := _proj()
	var q := _query()
	# Fila de propias en z = 0, de x = -40 a 40; una enemiga en medio.
	for i: int in 9:
		st.add_entity(i + 1, 0, ME, -40.0 + i * 10.0, 0.0)
	st.add_entity(100, 0, ENEMY, 0.0, 2.0)
	# Rectángulo que cubre de x = -15 a 15 en el suelo.
	var a := p.project(Vector3(-15, 1, -5))
	var b := p.project(Vector3(15, 1, 5))
	var rect := Rect2(Vector2(a.x, a.y), Vector2(b.x - a.x, b.y - a.y))
	var ids := q.in_rect(st, p, rect, ME)
	ids.sort()
	assert_array(ids).is_equal(PackedInt32Array([4, 5, 6]))
	# Un rectángulo dibujado al revés (de abajo a la derecha hacia arriba a la izquierda) es igual.
	var rev := Rect2(rect.end, -rect.size)
	var ids2 := q.in_rect(st, p, rev, ME)
	ids2.sort()
	assert_array(ids2).is_equal(ids)
	# Detrás de la cámara no entra aunque el rectángulo sea toda la pantalla.
	st.add_entity(200, 0, ME, 0.0, 400.0)
	var everything := q.in_rect(st, p, Rect2(Vector2.ZERO, VIEW), ME)
	assert_bool(everything.has(200)).is_false()
	assert_int(everything.size()).is_equal(9)


func test_rect_prefers_units_over_buildings() -> void:
	var st := _state()
	var p := _proj()
	var q := _query()
	st.add_entity(1, 2, ME, 0.0, 0.0)
	st.add_entity(2, 0, ME, 5.0, 0.0)
	var all := Rect2(Vector2.ZERO, VIEW)
	assert_array(q.in_rect(st, p, all, ME)).is_equal(PackedInt32Array([2]))
	st.remove(2)
	assert_array(q.in_rect(st, p, all, ME)).is_equal(PackedInt32Array([1]))


func test_pick_nearest_within_radius() -> void:
	var st := _state()
	var p := _proj()
	var q := _query()
	st.add_entity(1, 0, ME, 0.0, 0.0)
	st.add_entity(2, 0, ENEMY, 4.0, 0.0)
	var s1 := p.project(Vector3(0, 1, 0))
	var s2 := p.project(Vector3(4, 1, 0))
	assert_int(st.ids[q.pick(st, p, Vector2(s1.x + 2, s1.y))]).is_equal(1)
	assert_int(st.ids[q.pick(st, p, Vector2(s2.x - 2, s2.y))]).is_equal(2)
	# Lejos de todo: nada.
	assert_int(q.pick(st, p, Vector2(s1.x, s1.y - 200))).is_equal(-1)
	# Un edificio grande se acierta lejos de su centro (radio proyectado > PICK_RADIUS_PX).
	st.add_entity(3, 2, ME, -40.0, 0.0)
	var s3 := p.project(Vector3(-40, 3, 0))
	var r_px: float = 6.0 * p.focal_px / s3.z
	assert_float(r_px).is_greater(SelectionQuery.PICK_RADIUS_PX)
	assert_int(st.ids[q.pick(st, p, Vector2(s3.x + r_px * 0.8, s3.y))]).is_equal(3)


func test_same_type_on_screen() -> void:
	var st := _state()
	var p := _proj()
	var q := _query()
	st.add_entity(1, 0, ME, 0.0, 0.0)
	st.add_entity(2, 0, ME, 10.0, 0.0)
	st.add_entity(3, 1, ME, 20.0, 0.0)
	st.add_entity(4, 0, ENEMY, 30.0, 0.0)
	st.add_entity(5, 0, ME, 0.0, 600.0)  # detrás de la cámara
	var ids := q.same_type_on_screen(st, p, 0, ME)
	ids.sort()
	assert_array(ids).is_equal(PackedInt32Array([1, 2]))


# --- Selección (Shift) ----------------------------------------------------------------

func test_shift_adds_then_removes() -> void:
	var sel := UnitSelection.new()
	sel.apply(PackedInt32Array([3, 1]), UnitSelection.Mode.REPLACE)
	assert_array(sel.ids()).is_equal(PackedInt32Array([1, 3]))
	# Shift con algunas nuevas: suma.
	sel.apply(PackedInt32Array([2, 3]), UnitSelection.Mode.TOGGLE)
	assert_array(sel.ids()).is_equal(PackedInt32Array([1, 2, 3]))
	# Shift con todas ya seleccionadas: quita.
	sel.apply(PackedInt32Array([2, 3]), UnitSelection.Mode.TOGGLE)
	assert_array(sel.ids()).is_equal(PackedInt32Array([1]))
	assert_bool(sel.is_selected(1)).is_true()
	assert_bool(sel.is_selected(3)).is_false()
	# Shift + clic sobre una: la alterna.
	sel.apply(PackedInt32Array([1]), UnitSelection.Mode.TOGGLE)
	assert_bool(sel.is_empty()).is_true()
	assert_bool(sel.can_order()).is_false()


func test_inspect_foreign_cannot_order_and_own_selection_replaces_it() -> void:
	var sel := UnitSelection.new()
	sel.apply(PackedInt32Array([1, 2]), UnitSelection.Mode.REPLACE)
	assert_bool(sel.can_order()).is_true()
	sel.inspect(50)
	assert_bool(sel.inspecting).is_true()
	assert_bool(sel.can_order()).is_false()
	assert_array(sel.ids()).is_equal(PackedInt32Array([50]))
	# Sumar propias a una inspección la reemplaza.
	sel.apply(PackedInt32Array([7]), UnitSelection.Mode.TOGGLE)
	assert_bool(sel.inspecting).is_false()
	assert_array(sel.ids()).is_equal(PackedInt32Array([7]))


func test_prune_removes_dead() -> void:
	var st := _state()
	st.add_entity(1, 0, ME, 0, 0)
	st.add_entity(2, 0, ME, 5, 0)
	var sel := UnitSelection.new()
	sel.apply(PackedInt32Array([1, 2]), UnitSelection.Mode.REPLACE)
	st.remove(1)
	assert_int(sel.prune(st)).is_equal(1)
	assert_array(sel.ids()).is_equal(PackedInt32Array([2]))
	assert_bool(sel.is_selected(1)).is_false()


# --- Grupos de control ---------------------------------------------------------------

func test_control_groups_assign_recall_and_prune() -> void:
	var st := _state()
	for i: int in range(1, 6):
		st.add_entity(i, 0, ME, i * 10.0, 0.0)
	var g := ControlGroups.new()
	g.assign(1, PackedInt32Array([3, 1, 3, 2]))
	assert_array(g.get_ids(1)).is_equal(PackedInt32Array([1, 2, 3]))
	assert_array(g.members(2, st)).is_empty()
	st.remove(2)
	assert_array(g.members(1, st)).is_equal(PackedInt32Array([1, 3]))
	assert_array(g.get_ids(1)).is_equal(PackedInt32Array([1, 3]))
	# Reasignar reemplaza; vacío borra.
	g.assign(1, PackedInt32Array([5]))
	assert_array(g.get_ids(1)).is_equal(PackedInt32Array([5]))
	g.assign(1, PackedInt32Array())
	assert_array(g.get_ids(1)).is_empty()
	# Fuera de rango: no hace nada.
	g.assign(0, PackedInt32Array([1]))
	g.assign(10, PackedInt32Array([1]))
	assert_array(g.get_ids(0)).is_empty()
	# Centro del grupo.
	var c: Variant = ControlGroups.centroid(PackedInt32Array([1, 3]), st)
	assert_vector(c as Vector2).is_equal_approx(Vector2(20, 0), Vector2(0.01, 0.01))
	assert_bool(ControlGroups.centroid(PackedInt32Array([99]), st) == null).is_true()


func test_control_group_double_tap() -> void:
	var g := ControlGroups.new()
	assert_bool(g.register_recall(1, 1000)).is_false()
	assert_bool(g.register_recall(1, 1200)).is_true()
	# Un tercer toque empieza de nuevo.
	assert_bool(g.register_recall(1, 1300)).is_false()
	# Otro número o demasiado tarde: no es doble.
	assert_bool(g.register_recall(2, 1400)).is_false()
	assert_bool(g.register_recall(2, 1400 + ControlGroups.DOUBLE_TAP_MSEC + 1)).is_false()


# --- Armado de comandos ----------------------------------------------------------------

func _ids(n: int, start: int = 1) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in n:
		out.append(start + i * 2)
	return out


func test_move_splits_in_blocks_of_512() -> void:
	var ids := _ids(1100)
	ids.reverse()
	var cmds := OrderBuilder.move(ids, Vector2(10, -20), false, true)
	assert_int(cmds.size()).is_equal(3)
	assert_int(cmds[0].entity_ids.size()).is_equal(512)
	assert_int(cmds[1].entity_ids.size()).is_equal(512)
	assert_int(cmds[2].entity_ids.size()).is_equal(76)
	var seen: int = 0
	for cmd: Command in cmds:
		assert_int(cmd.type).is_equal(Command.Type.MOVE)
		assert_bool(cmd.queued).is_true()
		assert_vector(cmd.target_pos).is_equal(Vector2(10, -20))
		assert_bool(Command.ids_are_sorted(cmd.entity_ids)).is_true()
		# Cada bloque se puede codificar (<= 512 ids) y vuelve igual.
		cmd.seq = 7
		var back := CommandCodec.decode(CommandCodec.encode(cmd))
		assert_object(back).is_not_null()
		assert_array(back.entity_ids).is_equal(cmd.entity_ids)
		assert_bool(back.queued).is_true()
		seen += cmd.entity_ids.size()
	assert_int(seen).is_equal(1100)
	# Bloques sin solaparse y en orden.
	assert_bool(cmds[0].entity_ids[511] < cmds[1].entity_ids[0]).is_true()


func test_selection_of_500_fits_one_command() -> void:
	var cmds := OrderBuilder.move(_ids(500), Vector2.ZERO, true, false)
	assert_int(cmds.size()).is_equal(1)
	assert_int(cmds[0].type).is_equal(Command.Type.ATTACK_MOVE)
	assert_bool(cmds[0].queued).is_false()
	# ~1,5 B por id o menos con ids cercanos.
	assert_int(CommandCodec.encode(cmds[0]).size()).is_less(1000)


func test_orders_are_trimmed_beyond_max_commands() -> void:
	var n: int = SimConstants.MAX_IDS_PER_COMMAND * OrderBuilder.MAX_COMMANDS_PER_ORDER + 100
	var cmds := OrderBuilder.stop(_ids(n))
	assert_int(cmds.size()).is_equal(OrderBuilder.MAX_COMMANDS_PER_ORDER)
	assert_int(OrderBuilder.trimmed_count(n)).is_equal(100)
	assert_int(OrderBuilder.trimmed_count(500)).is_equal(0)
	assert_int(cmds[0].type).is_equal(Command.Type.STOP)
	assert_bool(cmds[0].queued).is_false()


func test_attack_carries_target_and_dedups_ids() -> void:
	var cmds := OrderBuilder.attack(PackedInt32Array([5, 3, 5, 0, 3]), 42, true)
	assert_int(cmds.size()).is_equal(1)
	assert_int(cmds[0].type).is_equal(Command.Type.ATTACK)
	assert_int(cmds[0].target_id).is_equal(42)
	assert_bool(cmds[0].queued).is_true()
	assert_array(cmds[0].entity_ids).is_equal(PackedInt32Array([3, 5]))
	var back := CommandCodec.decode(CommandCodec.encode(cmds[0]))
	assert_int(back.target_id).is_equal(42)
	assert_array(OrderBuilder.move(PackedInt32Array(), Vector2.ZERO, false, false)).is_empty()


func test_rate_limiter_30_per_second() -> void:
	var rl := OrderBuilder.RateLimiter.new()
	assert_bool(rl.try_consume(28, 1000)).is_true()
	# Una orden que no cabe entera no consume nada.
	assert_bool(rl.try_consume(3, 1500)).is_false()
	assert_bool(rl.try_consume(2, 1500)).is_true()
	assert_bool(rl.try_consume(1, 1999)).is_false()
	# A los 1000 ms se liberan los primeros 28.
	assert_bool(rl.try_consume(28, 2000)).is_true()


# --- Rendimiento --------------------------------------------------------------------

## ADR-006 / T-007: selección por rectángulo sobre 2000 unidades en < 2 ms.
func test_rect_selection_2000_units_under_2ms() -> void:
	var st := _state()
	var q := _query()
	# Cámara a zoom medio (como render_load): 150 m del foco, a 45°.
	var xf := Transform3D(Basis(), Vector3(0, 106, 106)).looking_at(Vector3.ZERO, Vector3.UP)
	var p := ScreenProjector.from_params(xf, 50.0, 1.0, 4000.0, VIEW)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 2000 entidades de 6 jugadores en un cuadrado de 400 m.
	for i: int in 2000:
		st.add_entity(i + 1, i % 3, 1 + i % 6, rng.randf_range(-200, 200), rng.randf_range(-200, 200))
	var rect := Rect2(Vector2(200, 150), Vector2(1500, 800))
	var times := PackedInt64Array()
	var got: int = 0
	for run: int in 31:
		var t0: int = Time.get_ticks_usec()
		got = q.in_rect(st, p, rect, ME).size()
		times.append(Time.get_ticks_usec() - t0)
	# Peor caso: las 2000 son del jugador (se proyectan todas).
	for s: int in st.count:
		st.owner[s] = ME
	var times_all := PackedInt64Array()
	var got_all: int = 0
	for run: int in 31:
		var t0: int = Time.get_ticks_usec()
		got_all = q.in_rect(st, p, rect, ME).size()
		times_all.append(Time.get_ticks_usec() - t0)
	times.sort()
	times_all.sort()
	print("SELECTION_PERF 2000 entidades. 6 jugadores: %d seleccionadas, mediana %d us, máx %d us. Todas propias: %d seleccionadas, mediana %d us, máx %d us" % [
		got, times[15], times[30], got_all, times_all[15], times_all[30]])
	assert_int(got_all).is_greater(got)
	assert_int(times_all[15]).is_less(2000)
