extends Node
## Captura de comprobación de T-013 (necesita ventana). Abre la partida local (main/match.tscn)
## sobre el mapa provisional, ordena a las tropas de tierra del jugador 1 ir detrás del cerro de
## prueba (la recta lo atraviesa), adelanta la simulación y guarda UNA captura con la costa (que
## sale de la misma rejilla lógica que usan las rutas), el cerro, la ruta del grupo dibujada en
## amarillo y el grupo rodeando el cerro.
##
##   godot --path . res://tests/sandbox/route_capture.tscn -- --out=C:/ruta/captura.png
## Imprime "CAPTURE ..." y sale con 0 si la orden tuvo ruta y el grupo avanzó por ella.

const TARGET := Vector2(-1000.0, 150.0)
const WAIT_BEFORE_ORDER: float = 1.5
## Ticks extra por frame para adelantar la marcha (el grupo tarda ~2 min reales a 1x).
const FAST_TICKS_PER_FRAME: int = 12
## La captura se toma cuando el centro del grupo pasa al oeste de esta x (junto al cerro).
const CAPTURE_X: float = -560.0

var _out: String = "user://route_capture.png"
var _match: Node
var _t: float = 0.0
var _step: int = 0
var _ids := PackedInt32Array()
var _route: int = 0
var _frames: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_match = load("res://main/match.tscn").instantiate()
	add_child(_match)


func _process(delta: float) -> void:
	_t += delta
	var server: MatchServer = _match.get("server")
	var sel: SelectionController = _match.get("selection")
	if server == null or sel == null:
		return
	if _step == 0:
		if sel.camera != null:
			sel.camera.edge_scroll_enabled = false
			sel.camera.focus_on(Vector3(-330.0, 0.0, 60.0), true)
			sel.camera.set_zoom(0.84, true)
			sel.camera.set_yaw(0.0, true)
		_step = 1
	elif _step == 1 and _t >= WAIT_BEFORE_ORDER:
		_order(server)
		_step = 2
	elif _step == 2:
		var sim := server.sim
		if _route == 0 and not _ids.is_empty():
			var s0 := sim.store.slot_of(_ids[0])
			if s0 >= 0 and sim.routes.status[sim.store.route[s0]] == RouteStore.Status.READY:
				_route = sim.store.route[s0]
				_draw_route(sim, sim.routes.points[_route], Vector2(sim.routes.start_x[_route], sim.routes.start_z[_route]))
		for i: int in FAST_TICKS_PER_FRAME:
			server.tick_once()
		_frames += 1
		if _center(sim).x < CAPTURE_X or _frames > 3000:
			_step = 3
			_t = 0.0
	elif _step == 3 and _t >= 0.4:
		_step = 4
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_out)
		var c := _center(server.sim)
		print("CAPTURE %s (err %d): %d tropas, ruta %d con %d puntos, centro del grupo (%.0f, %.0f)" % [
			_out, err, _ids.size(), _route, server.sim.routes.point_count(_route) if _route != 0 else 0, c.x, c.y])
		get_tree().quit(0 if err == OK and _route != 0 and c.x < CAPTURE_X else 1)


## MOVE de todas las tropas de tierra del jugador 1 al otro lado del cerro (por la cola normal).
func _order(server: MatchServer) -> void:
	var sim := server.sim
	for s: int in sim.store.count:
		if sim.store.owner[s] == 1 and sim.speed_by_def[sim.store.def_index[s]] > 0.0 \
				and sim.layer_by_def[sim.store.def_index[s]] == Terrain.Layer.LAND:
			_ids.append(sim.store.id[s])
	_ids.sort()
	var r := sim.submit_command(1, Command.make_move(9000, _ids, TARGET))
	print("CAPTURE: orden a %s de %d tropas: %s" % [TARGET, _ids.size(), Command.Reject.keys()[r]])


func _center(sim: Simulation) -> Vector2:
	var c := Vector2.ZERO
	var n: int = 0
	for e: int in _ids:
		var s := sim.store.slot_of(e)
		if s >= 0:
			c += Vector2(sim.store.pos_x[s], sim.store.pos_z[s])
			n += 1
	return c / maxi(n, 1)


## Polilínea amarilla de la ruta, apenas sobre el suelo.
func _draw_route(sim: Simulation, pts: PackedFloat64Array, start: Vector2) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var prev := start
	for i: int in range(0, pts.size(), 2):
		var p := Vector2(pts[i], pts[i + 1])
		# Línea gruesa: varias pasadas desplazadas.
		for o: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			im.surface_add_vertex(Vector3(prev.x + o, 1.0, prev.y))
			im.surface_add_vertex(Vector3(p.x + o, 1.0, p.y))
			im.surface_add_vertex(Vector3(prev.x, 1.0, prev.y + o))
			im.surface_add_vertex(Vector3(p.x, 1.0, p.y + o))
		prev = p
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	print("CAPTURE: ruta desde %s: %s" % [start, pts])
