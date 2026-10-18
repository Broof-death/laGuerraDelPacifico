extends GdUnitTestSuite
## SelectionController de punta a punta sin GPU (T-007): MatchServer y MatchClient reales por
## LocalTransport (el camino del modo de un jugador y del anfitrión) y un proyector sintético.
## Selección por rectángulo y por clic, inspección de ajenas, MOVE / ATTACK / STOP con lo que
## aplica el servidor, queued y grupos de control por eventos de teclado del InputMap.

const FRAME_MSEC: int = 50
const VIEW := Vector2(1600, 900)

var _net: LocalNetwork
var _server: MatchServer
var _client: MatchClient
var _ctl: SelectionController
var _rejections: Array[int] = []


func before_test() -> void:
	_net = LocalNetwork.new(3)
	_net.manual_clock = true
	_net.advance(10000)
	_server = MatchServer.new(SimTestHelpers.make_sim())
	_server.manual_msec = _net.now_msec()
	# Jugador 1 alrededor de (5060, 5000) y jugador 2 de (4940, 5000).
	_server.spawn_test_armies(2, 9, 60.0)
	_server.add_transport(_net.create_server())
	_client = MatchClient.new(_net.create_client(), _server.sim.game_data.catalog_hash())
	_client.command_rejected.connect(func(_seq: int, reason: int) -> void: _rejections.append(reason))
	_rejections.clear()
	_pump(20)
	_ctl = SelectionController.new()
	add_child(_ctl)
	_ctl.setup(_client, _server.sim.game_data, null, null)
	var eye := Vector3(5000, 160, 5160)
	var xf := Transform3D(Basis(), eye).looking_at(Vector3(5000, 0, 5000), Vector3.UP)
	_ctl.projector_override = ScreenProjector.from_params(xf, 50.0, 1.0, 4000.0, VIEW)


func after_test() -> void:
	_ctl.free()
	_client.close()
	_server.close()


func _pump(ticks: int) -> void:
	for i: int in ticks:
		_server.poll()
		_server.tick_once()
		_net.advance(FRAME_MSEC)
		_server.manual_msec = _net.now_msec()
		_client.update(FRAME_MSEC / 1000.0)


func _screen_of(id: int) -> Vector2:
	var st := _client.state
	var s: int = st.slot_of(id)
	var sp := _ctl.projector_override.project(Vector3(st.render_x[s], _ctl.query.height_of(st.def_index[s]), st.render_z[s]))
	return Vector2(sp.x, sp.y)


func _first_of(owner: int) -> int:
	var st := _client.state
	for s: int in st.count:
		if st.owner[s] == owner:
			return st.ids[s]
	return 0


func _key(code: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e


func test_client_sees_both_armies() -> void:
	assert_int(_client.player_id).is_equal(1)
	assert_int(_client.state.count).is_equal(18)


func test_drag_selects_own_and_move_reaches_server() -> void:
	_ctl.drag_select(Rect2(Vector2.ZERO, VIEW), false)
	assert_int(_ctl.selection.size()).is_equal(9)
	assert_bool(_ctl.selection.can_order()).is_true()
	_ctl.order_at(VIEW * Vector2(0.5, 0.8), false, false)
	_pump(3)
	assert_array(_rejections).is_empty()
	var store := _server.sim.store
	var s: int = store.slot_of(_ctl.selection.ids()[0])
	assert_int(store.action[s]).is_equal(SimConstants.Action.MOVE)
	var last: CommandQueue.LogEntry = _server.sim.queue.get_log().back()
	assert_int(last.command.type).is_equal(Command.Type.MOVE)
	assert_bool(last.command.queued).is_false()
	# El destino es el punto del suelo bajo el cursor (unos 5000, ~5040).
	assert_float(last.command.target_pos.x).is_equal_approx(5000.0, 1.0)
	assert_float(last.command.target_pos.y).is_greater(5000.0)


func test_queued_and_attack_move_and_stop() -> void:
	_ctl.drag_select(Rect2(Vector2.ZERO, VIEW), false)
	_ctl.order_at(VIEW * Vector2(0.5, 0.8), true, true)
	_pump(2)
	var last: CommandQueue.LogEntry = _server.sim.queue.get_log().back()
	assert_int(last.command.type).is_equal(Command.Type.ATTACK_MOVE)
	# Shift viaja como queued; la simulación todavía lo trata como una orden inmediata.
	assert_bool(last.command.queued).is_true()
	_ctl._unhandled_input(_key(KEY_S))
	_pump(2)
	last = _server.sim.queue.get_log().back()
	assert_int(last.command.type).is_equal(Command.Type.STOP)
	var store := _server.sim.store
	assert_int(store.action[store.slot_of(_ctl.selection.ids()[0])]).is_equal(SimConstants.Action.IDLE)


func test_right_click_on_enemy_attacks() -> void:
	_ctl.drag_select(Rect2(Vector2.ZERO, VIEW), false)
	var enemy: int = _first_of(2)
	_ctl.order_at(_screen_of(enemy), false, false)
	_pump(2)
	assert_array(_rejections).is_empty()
	var last: CommandQueue.LogEntry = _server.sim.queue.get_log().back()
	assert_int(last.command.type).is_equal(Command.Type.ATTACK)
	assert_int(last.command.target_id).is_equal(enemy)


func test_click_on_enemy_inspects_without_orders() -> void:
	var enemy: int = _first_of(2)
	_ctl.click_select(_screen_of(enemy), false, false)
	assert_bool(_ctl.selection.inspecting).is_true()
	assert_array(_ctl.selection.ids()).is_equal(PackedInt32Array([enemy]))
	var before: int = _server.sim.queue.get_log().size()
	_ctl.order_at(VIEW * 0.5, false, false)
	_ctl.stop()
	_pump(2)
	assert_int(_server.sim.queue.get_log().size()).is_equal(before)


func test_click_shift_toggles_and_same_type() -> void:
	var own: int = _first_of(1)
	_ctl.click_select(_screen_of(own), false, false)
	assert_array(_ctl.selection.ids()).is_equal(PackedInt32Array([own]))
	_ctl.click_select(_screen_of(own), true, false)
	assert_bool(_ctl.selection.is_empty()).is_true()
	# Ctrl / doble clic: todas las del mismo tipo en pantalla (las 9 propias).
	_ctl.click_select(_screen_of(own), false, true)
	assert_int(_ctl.selection.size()).is_equal(9)
	# Clic en el vacío sin Shift: vacía.
	_ctl.click_select(Vector2(5, 5), false, false)
	assert_bool(_ctl.selection.is_empty()).is_true()


func test_control_groups_with_keys() -> void:
	_ctl.drag_select(Rect2(Vector2.ZERO, VIEW), false)
	_ctl._unhandled_input(_key(KEY_3, true))
	assert_int(_ctl.groups.get_ids(3).size()).is_equal(9)
	_ctl._unhandled_input(_key(KEY_ESCAPE))
	assert_bool(_ctl.selection.is_empty()).is_true()
	_ctl._unhandled_input(_key(KEY_3))
	assert_int(_ctl.selection.size()).is_equal(9)
	# A arma el ataque en movimiento y Esc lo desarma sin vaciar la selección.
	_ctl._unhandled_input(_key(KEY_A))
	assert_bool(_ctl.attack_move_armed).is_true()
	_ctl._unhandled_input(_key(KEY_ESCAPE))
	assert_bool(_ctl.attack_move_armed).is_false()
	assert_int(_ctl.selection.size()).is_equal(9)
