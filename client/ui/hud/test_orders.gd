class_name TestOrders
extends CanvasLayer
## PROVISIONAL (T-017), hasta que exista la selección (T-007): órdenes de prueba sin seleccionar y
## un texto con los controles y el estado de la partida.
##   M: todas las tropas de tierra propias van al punto del suelo bajo el cursor (MOVE).
##   N: todos los buques propios van al punto bajo el cursor (MOVE).
## El punto se calcula cortando el rayo de la cámara con el plano y = 0 (sin colisión, ADR-010).
## Solo usa MatchClient (por el Transport), nunca la simulación.

var client: MatchClient
var game_data: GameData
var renderer: UnitBatchRenderer

var _label: Label
var _timer: float = 0.0
var _last_order: String = ""


func setup(p_client: MatchClient, p_game_data: GameData, p_renderer: UnitBatchRenderer) -> void:
	client = p_client
	game_data = p_game_data
	renderer = p_renderer


func _ready() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(12, 12)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_M:
			_order_to_cursor(UnitDef.Domain.LAND)
			get_viewport().set_input_as_handled()
		KEY_N:
			_order_to_cursor(UnitDef.Domain.SEA)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	_label.text = _status_text()


## Punto del suelo (y = 0) bajo el cursor, o null si el rayo no lo corta.
func ground_under_cursor() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))


## Ids de las unidades propias de un dominio (tierra o mar), según ClientState.
func own_unit_ids(domain: UnitDef.Domain) -> PackedInt32Array:
	var out := PackedInt32Array()
	if client == null or game_data == null:
		return out
	var st := client.state
	for s: int in st.count:
		if st.owner[s] != client.player_id:
			continue
		var def := game_data.get_def(st.def_index[s]) as UnitDef
		if def != null and def.domain == domain:
			out.append(st.ids[s])
	return out


func _order_to_cursor(domain: UnitDef.Domain) -> void:
	var hit: Variant = ground_under_cursor()
	if hit == null or client == null or not client.is_in_match():
		return
	var p: Vector3 = hit
	var ids := own_unit_ids(domain)
	var sent: int = 0
	for start: int in range(0, ids.size(), SimConstants.MAX_IDS_PER_COMMAND):
		var chunk := ids.slice(start, mini(start + SimConstants.MAX_IDS_PER_COMMAND, ids.size()))
		if client.send_command(Command.make_move(0, chunk, Vector2(p.x, p.z))) > 0:
			sent += chunk.size()
	_last_order = "%s: %d unidades a (%.0f, %.0f)" % ["Tierra" if domain == UnitDef.Domain.LAND else "Buques", sent, p.x, p.z]


func _status_text() -> String:
	var lines := PackedStringArray()
	lines.append("Partida local de prueba (T-017)")
	lines.append("WASD / flechas / borde: mover cámara   Q / E: rotar   Rueda: zoom   Botón central: arrastrar")
	lines.append("M: tus tropas de tierra al cursor   N: tus buques al cursor")
	if client != null:
		var color := "rojo" if client.player_id == 1 else ("azul" if client.player_id == 2 else str(client.player_id))
		lines.append("Eres el jugador %d (%s). El bot (azul) mueve sus tropas cada pocos segundos." % [client.player_id, color])
		lines.append("Entidades conocidas: %d" % client.state.count)
	if renderer != null:
		var st := renderer.get_stats()
		lines.append("Visibles %d (completa %d, simple %d, impostor %d), vistas %d   %d FPS" % [
			st.visible, st.lod_full, st.lod_simple, st.lod_impostor, st.pooled_views, Engine.get_frames_per_second()])
	if not _last_order.is_empty():
		lines.append("Última orden: " + _last_order)
	return "\n".join(lines)
