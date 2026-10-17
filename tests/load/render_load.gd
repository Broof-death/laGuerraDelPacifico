extends Node
## Prueba de carga del render del cliente (ADR-006 puntos 7 y 10, ADR-010 punto 5; T-017, la
## reutiliza T-039). Necesita ventana (no headless) y mide con la sincronización vertical apagada.
##
## Uso (desde la raíz del proyecto):
##   godot --path . res://tests/load/render_load.tscn -- --units=2000
##   ... -- --units=3000 --seconds=15 --zoom=0.5 --window=1920x1080
##   ... -- --units=2000 --mode=full     (partida local real: MatchServer + MatchClient + bots)
##
## Modo "synthetic" (por defecto): un SyntheticClientState con `units` entidades de 6 jugadores
## (infantería, caballería, artillería, un edificio y dos buques por jugador) en 18 regimientos
## que avanzan y retroceden sin parar sobre el escenario de prueba; mide solo el cliente.
## Modo "full": la simulación y la red local de verdad (6 jugadores x units/6 unidades de
## spawn_test_armies, con órdenes MOVE cada 4 s); el cliente es el jugador 1 y ve lo que su
## visión permite, así que mide el modo de un jugador completo en un mismo proceso.
## La cámara RTS queda a zoom medio sobre el centro y gira despacio (8°/s).
##
## Métricas (Performance y reloj propio): FPS medio, frame p50/p95/p99/máx, draw calls y
## primitivas por frame, objetos, VRAM, tiempo del renderizador por lotes y, en "full", del
## servidor. Salida JSON en la consola (línea "RENDER_RESULT {...}") y en user://load/.
## Umbrales (PC de referencia, ADR-006 punto 7): <= 2000 unidades: >= 60 FPS de media y p99
## <= 22 ms; <= 3000: >= 45 FPS. Más de 3000: sin umbral (margen). Sale con 0 si cumple, 1 si no.

const WARMUP_SECONDS: float = 2.0
const YAW_SPEED_DEG: float = 8.0
const PLAYERS: int = 6

var units: int = 2000
var seconds: float = 10.0
var mode: String = "synthetic"
var zoom: float = 0.5
var window_size := Vector2i(1920, 1080)

var _data: GameData
var _state: ClientState
var _synth: SyntheticClientState
var _renderer: UnitBatchRenderer
var _camera: RtsCamera
var _server: MatchServer
var _client: MatchClient
var _order_timer: float = 1.0
var _rng := RandomNumberGenerator.new()

# Regimientos sintéticos: por slot, base, dirección de avance, amplitud y fase.
var _base_x := PackedFloat32Array()
var _base_z := PackedFloat32Array()
var _dir_x := PackedFloat32Array()
var _dir_z := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _speed := PackedFloat32Array()

var _t: float = 0.0
var _last_usec: int = 0
var _frame_us := PackedInt64Array()
var _draw_calls := PackedInt64Array()
var _primitives := PackedInt64Array()
var _objects := PackedInt64Array()
var _renderer_us := PackedInt64Array()
var _server_us := PackedInt64Array()
var _visible := PackedInt64Array()
var _measure_start_usec: int = 0
var _yaw: float = 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"units":
				units = maxi(1, kv[1].to_int())
			"seconds":
				seconds = maxf(1.0, kv[1].to_float())
			"mode":
				mode = kv[1]
			"zoom":
				zoom = clampf(kv[1].to_float(), 0.0, 1.0)
			"window":
				var wh := kv[1].split("x")
				if wh.size() == 2:
					window_size = Vector2i(wh[0].to_int(), wh[1].to_int())
	DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_rng.seed = 7
	_data = load(GameData.DEFAULT_PATH)
	var errors := _data.build_index()
	if not errors.is_empty():
		push_error(str(errors))
		get_tree().quit(2)
		return
	var world: Node3D = load("res://client/world/battlefield.tscn").instantiate()
	add_child(world)
	_camera = world.get_node("RtsCamera")
	_camera.edge_scroll_enabled = false
	_camera.set_zoom(zoom, true)
	_camera.focus_on(Vector3.ZERO, true)
	if mode == "full":
		_start_full()
	else:
		mode = "synthetic"
		_start_synthetic()
	_renderer = UnitBatchRenderer.new()
	_renderer.auto_update = false
	add_child(_renderer)
	_renderer.setup(_state, ViewCatalog.new(_data))
	print("render_load: %d unidades, modo %s, %.0f s (+%.0f s de calentamiento)" % [units, mode, seconds, WARMUP_SECONDS])


func _start_synthetic() -> void:
	_synth = SyntheticClientState.new()
	_state = _synth
	var inf: int = _data.index_of(&"infanteria_prueba")
	var cab: int = _data.index_of(&"caballeria_prueba")
	var art: int = _data.index_of(&"artilleria_prueba")
	var buq: int = _data.index_of(&"buque_prueba")
	var edif: int = _data.index_of(&"edificio_prueba")
	var id: int = 1
	# Edificios y buques fijos por jugador; el resto, tropas en 3 regimientos por jugador.
	var extras: int = 0
	for p: int in PLAYERS:
		var owner: int = p + 1
		if edif >= 0 and id <= units:
			_add(id, edif, owner, -150.0 + p * 60.0, -100.0, 0.0, 0.0, 0.0, 0.0)
			id += 1
			extras += 1
		if buq >= 0:
			for k: int in 2:
				if id > units:
					break
				_add(id, buq, owner, 330.0 + k * 120.0, -250.0 + p * 100.0, 0.0, 1.0, 120.0, 0.03)
				id += 1
				extras += 1
	var troops: int = units - extras
	var regiments: int = PLAYERS * 3
	for r: int in regiments:
		var owner: int = r % PLAYERS + 1
		var count: int = troops / regiments + (1 if r < troops % regiments else 0)
		var cols: int = maxi(1, ceili(sqrt(float(count))))
		var rx: float = -125.0 + (r % 6) * 42.0
		var rz: float = -60.0 + (r / 6) * 42.0
		var face: float = 0.0 if (r / 6) % 2 == 0 else PI
		for i: int in count:
			var d: int = inf
			var k: float = float(i) / count
			if k > 0.92 and art >= 0:
				d = art
			elif k > 0.78 and cab >= 0:
				d = cab
			var x: float = rx + (i % cols) * 2.0
			var z: float = rz + (i / cols) * 2.0
			_add(id, d, owner, x, z, face, cos(face), 12.0, 0.25)
			id += 1


# Agrega una entidad sintética que va y viene sobre su dirección (dir_z = cos del rumbo).
func _add(id: int, d: int, owner: int, x: float, z: float, heading: float, dir_z: float, amp: float, speed: float) -> void:
	_synth.add_entity(id, d, owner, x, z, heading)
	_base_x.append(x)
	_base_z.append(z)
	_dir_x.append(sin(heading))
	_dir_z.append(dir_z)
	_amp.append(amp)
	_phase.append(_rng.randf() * TAU)
	_speed.append(speed)


func _start_full() -> void:
	var sim := Simulation.new(_data, 1)
	_server = MatchServer.new(sim)
	_server.allow_time_scale = true
	_server.spawn_test_armies(PLAYERS, ceili(float(units) / PLAYERS), 120.0)
	var net := LocalNetwork.new()
	_server.add_transport(net.create_server())
	_client = MatchClient.new(net.create_client(), _data.catalog_hash())
	_state = _client.state


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_t += delta
	_yaw += deg_to_rad(YAW_SPEED_DEG) * delta
	_camera.set_yaw(_yaw, true)
	var srv_us: int = 0
	if mode == "full":
		var t0: int = Time.get_ticks_usec()
		_server.update(delta)
		_client.update(delta)
		srv_us = Time.get_ticks_usec() - t0
		_bot_orders(delta)
	else:
		_move_synthetic()
	_renderer.refresh()
	if _t >= WARMUP_SECONDS:
		if _measure_start_usec == 0:
			_measure_start_usec = now
		elif _last_usec > 0:
			_frame_us.append(now - _last_usec)
			_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			_objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
			_renderer_us.append(_renderer.last_update_usec)
			_server_us.append(srv_us)
			_visible.append(_renderer.stat_visible)
		if _t >= WARMUP_SECONDS + seconds:
			_finish(now)
	_last_usec = now


func _move_synthetic() -> void:
	var st := _synth
	var rx := st.render_x
	var rz := st.render_z
	var rh := st.render_heading
	var t: float = _t
	for s: int in st.count:
		var a: float = _amp[s]
		if a <= 0.0:
			continue
		var w: float = _speed[s]
		var ph: float = _phase[s] + t * w
		var off: float = a * sin(ph)
		rx[s] = _base_x[s] + _dir_x[s] * off
		rz[s] = _base_z[s] + _dir_z[s] * off
		# Mira hacia donde avanza (cambia de sentido en cada extremo).
		rh[s] = atan2(_dir_x[s], _dir_z[s]) if cos(ph) >= 0.0 else atan2(-_dir_x[s], -_dir_z[s])
	st.render_x = rx
	st.render_z = rz
	st.render_heading = rh


func _bot_orders(delta: float) -> void:
	_order_timer -= delta
	if _order_timer > 0.0:
		return
	_order_timer = 4.0
	var sim := _server.sim
	var st := sim.store
	for owner: int in range(1, PLAYERS + 1):
		var ids := PackedInt32Array()
		for s: int in st.count:
			if st.owner[s] == owner:
				ids.append(st.id[s])
		var target := Vector2(_rng.randf_range(-150.0, 150.0), _rng.randf_range(-150.0, 150.0))
		for start: int in range(0, ids.size(), SimConstants.MAX_IDS_PER_COMMAND):
			sim.submit_command(owner, Command.make_move(0, ids.slice(start, start + SimConstants.MAX_IDS_PER_COMMAND), target))


func _finish(now: int) -> void:
	set_process(false)
	var elapsed: float = (now - _measure_start_usec) / 1e6
	var frames: int = _frame_us.size()
	var fps: float = frames / maxf(elapsed, 0.001)
	var sorted := _frame_us.duplicate()
	sorted.sort()
	var result := {
		"units": units,
		"mode": mode,
		"seconds": snappedf(elapsed, 0.01),
		"frames": frames,
		"fps_avg": snappedf(fps, 0.1),
		"frame_ms_p50": _pct_ms(sorted, 0.50),
		"frame_ms_p95": _pct_ms(sorted, 0.95),
		"frame_ms_p99": _pct_ms(sorted, 0.99),
		"frame_ms_max": _pct_ms(sorted, 1.0),
		"draw_calls_avg": _avg(_draw_calls),
		"draw_calls_max": _max(_draw_calls),
		"primitives_avg": _avg(_primitives),
		"primitives_max": _max(_primitives),
		"objects_avg": _avg(_objects),
		"renderer_ms_avg": snappedf(_avg(_renderer_us) / 1000.0, 0.01),
		"renderer_ms_p99": _pct_ms(_sorted(_renderer_us), 0.99),
		"server_ms_avg": snappedf(_avg(_server_us) / 1000.0, 0.01),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"entities_known": _state.count,
		"renderer": _renderer.get_stats(),
		"window": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"visible_avg": _avg(_visible),
		"gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"godot": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
	}
	var ok: bool = true
	var thresholds := ""
	if units <= 2000:
		ok = fps >= 60.0 and result.frame_ms_p99 <= 22.0
		thresholds = ">= 60 FPS y p99 <= 22 ms"
	elif units <= 3000:
		ok = fps >= 45.0
		thresholds = ">= 45 FPS"
	else:
		thresholds = "sin umbral (margen)"
	result["thresholds"] = thresholds
	result["pass"] = ok
	var json := JSON.stringify(result)
	print("RENDER_RESULT " + json)
	DirAccess.make_dir_recursive_absolute("user://load")
	var f := FileAccess.open("user://load/render_%d_%s.json" % [units, mode], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  "))
	get_tree().quit(0 if ok else 1)


func _sorted(a: PackedInt64Array) -> PackedInt64Array:
	var s := a.duplicate()
	s.sort()
	return s


func _pct_ms(sorted: PackedInt64Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var i: int = clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)
	return snappedf(sorted[i] / 1000.0, 0.01)


func _avg(a: PackedInt64Array) -> float:
	if a.is_empty():
		return 0.0
	var total: int = 0
	for v: int in a:
		total += v
	return snappedf(float(total) / a.size(), 0.1)


func _max(a: PackedInt64Array) -> int:
	var m: int = 0
	for v: int in a:
		m = maxi(m, v)
	return m
