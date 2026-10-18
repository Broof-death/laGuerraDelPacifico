extends Node
## Captura de comprobación de T-007 (necesita ventana). Abre la partida local (main/match.tscn),
## simula con eventos de entrada reales (Input.parse_input_event) un arrastre del ratón sobre parte
## de las tropas propias, da una orden de mover con clic derecho y guarda UNA captura con las
## unidades seleccionadas (anillos, etiquetas y barras), el marcador de destino y el panel.
##
##   godot --path . res://tests/sandbox/selection_capture.tscn -- --out=C:/ruta/captura.png
##   (opcional: --zoom=0.35 --yaw=0 --focus=x,z, igual que main/match.tscn)
## Imprime "CAPTURE ..." con el número de seleccionadas y sale con 0 si hubo selección.

const WAIT_BEFORE_DRAG: float = 2.5
const WAIT_AFTER_ORDER: float = 0.35

var _out: String = "user://selection_capture.png"
var _match: Node
var _t: float = 0.0
var _step: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_match = load("res://main/match.tscn").instantiate()
	add_child(_match)


func _process(delta: float) -> void:
	_t += delta
	var sel: SelectionController = _match.get("selection")
	if sel == null:
		return
	if _step == 0:
		var cam := sel.camera
		if cam != null:
			cam.edge_scroll_enabled = false  # el cursor real no debe mover la cámara
		_step = 1
	elif _step == 1 and _t >= WAIT_BEFORE_DRAG:
		_drag_over_own_units(sel)
		_step = 2
	elif _step == 2:
		# Orden de mover: clic derecho a un lado de las seleccionadas.
		var size := get_viewport().get_visible_rect().size
		_click(MOUSE_BUTTON_RIGHT, Vector2(size.x * 0.72, size.y * 0.62))
		_t = 0.0
		_step = 3
	elif _step == 3 and _t >= WAIT_AFTER_ORDER:
		_step = 4
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_out)
		var n: int = sel.selection.size()
		print("CAPTURE %s (err %d): %d seleccionadas, %d anillos" % [_out, err, n, sel.markers.ring_count()])
		get_tree().quit(0 if n > 0 and err == OK else 1)


## Arrastra un rectángulo que cubre la mitad izquierda de las tropas propias visibles.
func _drag_over_own_units(sel: SelectionController) -> void:
	var cam := get_viewport().get_camera_3d()
	var proj := ScreenProjector.from_camera(cam)
	var st := sel.state()
	var box := Rect2()
	var first := true
	for s: int in st.count:
		if st.owner[s] != sel.my_player():
			continue
		var sp := proj.project(Vector3(st.render_x[s], 1.0, st.render_z[s]))
		if sp.z <= 0.0 or sp.x < 0 or sp.y < 0 or sp.x > proj.size.x or sp.y > proj.size.y:
			continue
		var p := Vector2(sp.x, sp.y)
		if first:
			box = Rect2(p, Vector2.ZERO)
			first = false
		else:
			box = box.expand(p)
	if first:
		print("CAPTURE: no hay tropas propias en pantalla")
		return
	var a := box.position - Vector2(20, 20)
	var b := Vector2(box.position.x + box.size.x * 0.55, box.end.y + 20)
	_button(MOUSE_BUTTON_LEFT, a, true)
	for i: int in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.position = _to_window(a.lerp(b, i / 8.0))
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
	_button(MOUSE_BUTTON_LEFT, b, false)


func _click(button: MouseButton, pos: Vector2) -> void:
	_button(button, pos, true)
	_button(button, pos, false)


func _button(button: MouseButton, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = _to_window(pos)
	e.global_position = e.position
	Input.parse_input_event(e)


## Los eventos simulados van en coordenadas de la ventana; el estirado (canvas_items) los pasa a
## las del viewport, que son las que usa la selección.
func _to_window(viewport_pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * viewport_pos
