class_name TestOrders
extends CanvasLayer
## PROVISIONAL (T-017), hasta el HUD de T-030: un texto con los controles y el estado de la
## partida. Las órdenes de prueba M/N de T-017 se quitaron en T-007: ahora se selecciona y se
## ordena con SelectionController (client/selection/).
## Solo lee MatchClient, nunca la simulación.

var client: MatchClient
var game_data: GameData
var renderer: UnitBatchRenderer

var _label: Label
var _timer: float = 0.0


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
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	_label.text = _status_text()


func _status_text() -> String:
	var lines := PackedStringArray()
	lines.append("Partida local de prueba (T-017, T-007)")
	lines.append("Flechas / borde: mover cámara   Q / E: rotar   Rueda: zoom   Botón central: arrastrar")
	lines.append("Clic izq.: seleccionar (arrastrar: rectángulo; Shift: suma o quita; doble clic o Ctrl: mismo tipo)")
	lines.append("Clic der.: mover / atacar   A + clic: ataque en movimiento   S: alto   Shift: encolar   Esc: cancelar")
	lines.append("Ctrl + 1-9: guardar grupo   1-9: seleccionar grupo (doble toque: centrar)   Shift + 1-9: sumar")
	if client != null:
		var color := "rojo" if client.player_id == 1 else ("azul" if client.player_id == 2 else str(client.player_id))
		lines.append("Eres el jugador %d (%s). El bot (azul) mueve sus tropas cada pocos segundos." % [client.player_id, color])
		lines.append("Entidades conocidas: %d" % client.state.count)
	if renderer != null:
		var st := renderer.get_stats()
		lines.append("Visibles %d (completa %d, simple %d, impostor %d), vistas %d   %d FPS" % [
			st.visible, st.lod_full, st.lod_simple, st.lod_impostor, st.pooled_views, Engine.get_frames_per_second()])
	return "\n".join(lines)
