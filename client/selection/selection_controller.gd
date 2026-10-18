class_name SelectionController
extends Node
## Selección y órdenes del jugador (T-007). Solo cliente: lee ClientState y envía Command por
## MatchClient (el mismo camino en un jugador y en red; ADR-006). No usa colisionadores: la
## selección proyecta las posiciones del estado del cliente (SelectionQuery + ScreenProjector) y
## el destino en el suelo corta el rayo de la cámara con el plano y = 0 (hasta que exista
## TerrainView, ADR-010).
##
## Controles (acciones del InputMap):
##   select (clic izq.)            una entidad (la más cercana al cursor); arrastrar = rectángulo
##   select_add (Shift)            con select: suma o quita; con órdenes: las encola (queued)
##   select_same_type (Ctrl)       con select: las del mismo tipo en pantalla (también doble clic)
##   command (clic der.)           suelo = MOVE, enemigo = ATTACK
##   order_attack_move (A)         arma el ataque en movimiento; el siguiente clic izq. lo da
##   order_stop (S)                STOP
##   order_cancel (Esc)            desarma A o, si no, vacía la selección
##   control_group_1..9            selecciona el grupo; doble toque = centrar la cámara
##   control_group_assign (Ctrl)   con un número: asigna el grupo; Shift + número: lo suma
## Las entidades ajenas se pueden inspeccionar (clic) pero no reciben órdenes.

signal order_issued(type: Command.Type, count: int)

const DRAG_THRESHOLD_PX: float = 6.0
const MESSAGE_TIME: float = 3.0
const PRUNE_INTERVAL: float = 0.25

var client: MatchClient
var game_data: GameData
var camera: RtsCamera
var renderer: UnitBatchRenderer
var query: SelectionQuery
var selection := UnitSelection.new()
var groups := ControlGroups.new()
var limiter := OrderBuilder.RateLimiter.new()
var markers: SelectionMarkers
var hud: SelectionHud
## true después de A: el próximo clic izquierdo da ATTACK_MOVE.
var attack_move_armed: bool = false
## Proyector fijo (pruebas); null = el de la cámara activa.
var projector_override: ScreenProjector

var _pressing: bool = false
var _dragging: bool = false
var _press_pos := Vector2.ZERO
var _press_double: bool = false
var _message: String = ""
var _message_timer: float = 0.0
var _prune_timer: float = 0.0
var _info_dirty: bool = true


func setup(p_client: MatchClient, p_game_data: GameData, p_camera: RtsCamera, p_renderer: UnitBatchRenderer) -> void:
	client = p_client
	game_data = p_game_data
	camera = p_camera
	renderer = p_renderer
	query = SelectionQuery.from_game_data(game_data)
	if renderer != null:
		renderer.selection = selection
	selection.changed.connect(func() -> void: _info_dirty = true)
	client.command_rejected.connect(_on_command_rejected)


func _ready() -> void:
	# Después de Match (que interpola el estado) y antes del renderizador (100).
	process_priority = 90
	markers = SelectionMarkers.new()
	markers.name = "Marcadores"
	add_child(markers)
	hud = SelectionHud.new()
	hud.name = "HudSeleccion"
	add_child(hud)


func my_player() -> int:
	return client.player_id if client != null else 0


func state() -> ClientState:
	return client.state


# --- Entrada --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if client == null or not client.is_in_match():
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if event.is_action_pressed("select"):
			if attack_move_armed:
				attack_move_armed = false
				order_at(mb.position, _queue_mod(event), true)
			else:
				_pressing = true
				_dragging = false
				_press_pos = mb.position
				_press_double = mb.double_click
			get_viewport().set_input_as_handled()
		elif event.is_action_released("select") and _pressing:
			_pressing = false
			if _dragging:
				_dragging = false
				hud.set_drag_rect(Rect2())
				drag_select(Rect2(_press_pos, mb.position - _press_pos), _add_mod(event))
			else:
				click_select(mb.position, _add_mod(event), _press_double or _type_mod(event))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("command"):
			if attack_move_armed:
				attack_move_armed = false
				_set_message("Ataque en movimiento cancelado")
			else:
				order_at(mb.position, _queue_mod(event), false)
			get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _pressing and (_dragging or mm.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX):
			_dragging = true
			hud.set_drag_rect(Rect2(_press_pos, mm.position - _press_pos))
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	for n: int in range(ControlGroups.FIRST, ControlGroups.LAST + 1):
		if event.is_action_pressed("control_group_%d" % n):
			_on_group_key(n, _assign_mod(event), _add_mod(event))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("order_stop"):
		stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("order_attack_move"):
		if selection.can_order():
			attack_move_armed = true
			_set_message("Ataque en movimiento: clic izquierdo en el destino (Esc cancela)")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("order_cancel"):
		if attack_move_armed:
			attack_move_armed = false
			_set_message("Ataque en movimiento cancelado")
		else:
			selection.clear()
		get_viewport().set_input_as_handled()


func _add_mod(event: InputEvent) -> bool:
	var e := event as InputEventWithModifiers
	return Input.is_action_pressed("select_add") or (e != null and e.shift_pressed)


func _queue_mod(event: InputEvent) -> bool:
	return _add_mod(event)


func _type_mod(event: InputEvent) -> bool:
	var e := event as InputEventWithModifiers
	return Input.is_action_pressed("select_same_type") or (e != null and e.ctrl_pressed)


func _assign_mod(event: InputEvent) -> bool:
	var e := event as InputEventWithModifiers
	return Input.is_action_pressed("control_group_assign") or (e != null and e.ctrl_pressed)


# --- Selección ------------------------------------------------------------------

## Clic en `pos`: entidad propia (Shift suma o quita), mismo tipo en pantalla (`same_type`), o
## entidad ajena para inspeccionar. En el vacío y sin Shift, vacía la selección.
func click_select(pos: Vector2, add: bool, same_type: bool) -> void:
	var proj := _projector()
	if proj == null:
		return
	var st := state()
	var s: int = query.pick(st, proj, pos)
	if s < 0:
		if not add:
			selection.clear()
		return
	var id: int = st.ids[s]
	if st.owner[s] != my_player():
		if not add:
			selection.inspect(id)
		return
	if same_type:
		var ids := query.same_type_on_screen(st, proj, st.def_index[s], my_player())
		selection.apply(ids, UnitSelection.Mode.ADD if add else UnitSelection.Mode.REPLACE)
	else:
		selection.apply(PackedInt32Array([id]), UnitSelection.Mode.TOGGLE if add else UnitSelection.Mode.REPLACE)


## Rectángulo de pantalla: las entidades propias dentro (Shift suma o quita).
func drag_select(rect: Rect2, add: bool) -> void:
	var proj := _projector()
	if proj == null:
		return
	var ids := query.in_rect(state(), proj, rect, my_player())
	if ids.is_empty() and add:
		return
	selection.apply(ids, UnitSelection.Mode.TOGGLE if add else UnitSelection.Mode.REPLACE)


func _on_group_key(n: int, assign: bool, add: bool) -> void:
	if assign:
		var ids := selection.ids() if selection.can_order() else PackedInt32Array()
		groups.assign(n, ids)
		_set_message("Grupo %d: %d unidades" % [n, ids.size()] if not ids.is_empty() else "Grupo %d borrado" % n)
		return
	var members := groups.members(n, state())
	if members.is_empty():
		return
	if add:
		selection.apply(members, UnitSelection.Mode.ADD)
		return
	selection.apply(members, UnitSelection.Mode.REPLACE)
	if groups.register_recall(n, Time.get_ticks_msec()) and camera != null:
		var c: Variant = ControlGroups.centroid(members, state())
		if c != null:
			camera.focus_on(Vector3(c.x, 0.0, c.y))


# --- Órdenes --------------------------------------------------------------------

## Orden en el punto de pantalla `pos`: sobre una entidad enemiga, ATTACK; si no, MOVE (o
## ATTACK_MOVE con `attack_move`) al punto del suelo. `queued` = Shift.
func order_at(pos: Vector2, queued: bool, attack_move: bool) -> void:
	if not selection.can_order():
		return
	var proj := _projector()
	if proj == null:
		return
	var st := state()
	var s: int = query.pick(st, proj, pos)
	if s >= 0 and _is_enemy(st.owner[s]):
		var target: int = st.ids[s]
		var where := Vector2(st.render_x[s], st.render_z[s])
		_issue(OrderBuilder.attack(selection.ids(), target, queued), where, SelectionMarkers.COLOR_ATTACK,
				query.radius_of(st.def_index[s]) * 1.5 + 1.0, "Atacar")
		return
	var hit: Variant = proj.ground_point(pos)
	if hit == null:
		return
	var p: Vector3 = hit
	var dest := Vector2(p.x, p.z)
	var color: Color = SelectionMarkers.COLOR_ATTACK_MOVE if attack_move else SelectionMarkers.COLOR_MOVE
	_issue(OrderBuilder.move(selection.ids(), dest, attack_move, queued), dest, color, 3.0,
			"Ataque en movimiento" if attack_move else "Mover")


func stop() -> void:
	if not selection.can_order():
		return
	var cmds := OrderBuilder.stop(selection.ids())
	if not limiter.try_consume(cmds.size(), Time.get_ticks_msec()):
		_set_message("Demasiadas órdenes seguidas")
		return
	for cmd: Command in cmds:
		client.send_command(cmd)
	order_issued.emit(Command.Type.STOP, selection.size())
	_set_message("Alto")


func _issue(cmds: Array[Command], where: Vector2, color: Color, radius: float, label: String) -> void:
	if cmds.is_empty():
		return
	if not limiter.try_consume(cmds.size(), Time.get_ticks_msec()):
		_set_message("Demasiadas órdenes seguidas")
		return
	var last_seq: int = 0
	var sent: int = 0
	for cmd: Command in cmds:
		var seq: int = client.send_command(cmd)
		if seq > 0:
			last_seq = seq
			sent += cmd.entity_ids.size()
	if last_seq == 0:
		return
	markers.show_destination(where, color, last_seq, radius)
	order_issued.emit(cmds[0].type, sent)
	var extra: String = " (encolada)" if cmds[0].queued else ""
	var trimmed: int = OrderBuilder.trimmed_count(selection.size())
	if trimmed > 0:
		extra += " (%d sin orden: tope por orden)" % trimmed
	_set_message("%s: %d unidades%s" % [label, sent, extra])


func _is_enemy(owner_id: int) -> bool:
	return owner_id != my_player() and owner_id != SimConstants.NEUTRAL_PLAYER


func _on_command_rejected(seq: int, reason: int) -> void:
	markers.reject(seq)
	_set_message("Orden rechazada: %s" % Command.Reject.keys()[reason])


# --- Por frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if client == null:
		return
	var st := state()
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = PRUNE_INTERVAL
		selection.prune(st)
	markers.update_rings(st, selection, query)
	markers.update_destinations(delta, client.last_confirmed_seq())
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""
			_info_dirty = true
	if _info_dirty:
		_info_dirty = false
		var text := SelectionHud.describe(selection, st, game_data, my_player())
		if attack_move_armed:
			text = (text + "\n" if not text.is_empty() else "") + "[A] elige el destino"
		if not _message.is_empty():
			text = (text + "\n" if not text.is_empty() else "") + _message
		hud.set_info(text)


func _set_message(text: String) -> void:
	_message = text
	_message_timer = MESSAGE_TIME
	_info_dirty = true


func _projector() -> ScreenProjector:
	if projector_override != null:
		return projector_override
	var cam := get_viewport().get_camera_3d()
	return ScreenProjector.from_camera(cam) if cam != null else null
