extends GdUnitTestSuite
## Flujo completo MatchServer <-> MatchClient por LocalTransport (reloj manual): saludo, jugadores,
## comandos propios y ajenos, rechazos, límites, pausa, latencia, pérdida e interpolación.
## Es el mismo camino que el modo de un jugador y que el anfitrión (ADR-006 punto 9).

const FRAME_MSEC: int = 50

var _net: LocalNetwork
var _server: MatchServer
var _clients: Array[MatchClient] = []
var _rejections: Array[PackedInt32Array] = []


func before_test() -> void:
	_net = LocalNetwork.new(3)
	_net.manual_clock = true
	_net.advance(10000)
	var sim := SimTestHelpers.make_sim()
	_server = MatchServer.new(sim)
	_server.manual_msec = _net.now_msec()
	_server.spawn_test_armies(2, 10, 60.0)
	_server.add_transport(_net.create_server())
	_clients.clear()
	_rejections.clear()


func after_test() -> void:
	for c: MatchClient in _clients:
		c.close()
	_server.close()


func _add_client(catalog_hash: int = -1) -> MatchClient:
	var h: int = catalog_hash if catalog_hash >= 0 else _server.sim.game_data.catalog_hash()
	var c := MatchClient.new(_net.create_client(), h)
	var idx: int = _clients.size()
	c.command_rejected.connect(func(seq: int, reason: int) -> void: _rejections.append(PackedInt32Array([idx, seq, reason])))
	_clients.append(c)
	return c


## Avanza `ticks` ticks de 50 ms: red del servidor, tick, reloj y red de los clientes.
func _pump(ticks: int) -> void:
	for i: int in ticks:
		_server.poll()
		_server.tick_once()
		_net.advance(FRAME_MSEC)
		_server.manual_msec = _net.now_msec()
		for c: MatchClient in _clients:
			c.update(FRAME_MSEC / 1000.0)


func _ids_of(owner: int) -> PackedInt32Array:
	var st := _server.sim.store
	var out := PackedInt32Array()
	for s: int in st.count:
		if st.owner[s] == owner:
			out.append(st.id[s])
	out.sort()
	return out


func test_two_clients_join_and_see_the_same_match() -> void:
	var a := _add_client()
	var b := _add_client()
	_pump(10)
	assert_int(a.player_id).is_equal(1)
	assert_int(b.player_id).is_equal(2)
	assert_array(_server.connected_players()).contains_exactly_in_any_order([1, 2])
	assert_int(a.state.count).is_equal(20)
	assert_int(b.state.count).is_equal(20)
	assert_int(a.receiver.latest_complete_tick).is_greater(0)
	# Los snapshots se reparten: el jugador 1 en ticks impares y el 2 en pares (misma foto).
	assert_int(_server.get_conn(1).sender.snapshots_sent).is_greater_equal(4)


func test_client_moves_own_units_but_not_others() -> void:
	var a := _add_client()
	var b := _add_client()
	_pump(6)
	var mine := _ids_of(1)
	var theirs := _ids_of(2)
	var s_their := _server.sim.store.slot_of(theirs[0])
	var their_x := _server.sim.store.pos_x[s_their]
	var seq_ok := a.send_command(Command.make_move(0, mine, Vector2(5200.0, 5000.0)))
	var seq_bad := a.send_command(Command.make_move(0, theirs, Vector2(4000.0, 4000.0)))
	assert_int(seq_ok).is_greater(0)
	_pump(30)
	# Rechazo del comando ajeno, con su seq.
	assert_array(_rejections).contains([PackedInt32Array([0, seq_bad, Command.Reject.NOT_OWNER])])
	assert_float(_server.sim.store.pos_x[s_their]).is_equal(their_x)
	# Las unidades propias avanzaron en el servidor y el otro cliente lo ve.
	var s_mine := _server.sim.store.slot_of(mine[0])
	var cb := b.state.slot_of(mine[0])
	assert_int(cb).is_greater_equal(0)
	var seen := b.state.predicted(cb, b.receiver.latest_tick)
	assert_float(absf(seen.x - _server.sim.store.pos_x[s_mine])).is_less(3.0)
	assert_int(a.last_confirmed_seq()).is_equal(seq_bad)


func test_refuses_wrong_catalog_and_full_match() -> void:
	_server.max_players = 1
	var refused: Array[int] = []
	var a := _add_client()
	var bad := _add_client(12345)
	bad.refused.connect(func(r: int) -> void: refused.append(r))
	_pump(4)
	var late := _add_client()
	late.refused.connect(func(r: int) -> void: refused.append(r))
	_pump(4)
	assert_int(a.player_id).is_equal(1)
	assert_int(bad.player_id).is_equal(0)
	assert_int(late.player_id).is_equal(0)
	assert_array(refused).contains_exactly([NetProtocol.Refuse.CATALOG_MISMATCH, NetProtocol.Refuse.MATCH_FULL])


func test_command_byte_limit_8kb_per_second() -> void:
	var a := _add_client()
	_pump(4)
	# Comandos grandes válidos (ids repetidos del propio ejército no sirven: deben ser propios y
	# crecientes). Con 10 unidades cada comando ocupa poco, así que se mandan muchos: el límite de
	# 30/s salta antes; para probar el de bytes se mandan paquetes crudos grandes.
	var mine := _ids_of(1)
	var big := CommandCodec.encode(Command.make_move(1, mine, Vector2(5000, 5000)))
	var filler := big.duplicate()
	# Paquete malformado de ~2 KB: cuenta para el límite de bytes y se rechaza como MALFORMED.
	filler.resize(2000)
	for i: int in 5:
		a.transport.send(Transport.SERVER_PEER, Transport.Channel.COMMANDS, filler)
	a.transport.send(Transport.SERVER_PEER, Transport.Channel.COMMANDS, big)
	_pump(2)
	var reasons := PackedInt32Array()
	for r: PackedInt32Array in _rejections:
		reasons.append(r[2])
	assert_int(reasons.count(Command.Reject.MALFORMED)).is_equal(5)
	assert_bool(reasons.has(Command.Reject.RATE_LIMITED)).is_true()
	# Pasado un segundo (real) se renueva.
	_rejections.clear()
	_net.advance(1000)
	_server.manual_msec = _net.now_msec()
	a.send_command(Command.make_move(0, mine, Vector2(5000, 5000)))
	_pump(2)
	assert_int(_rejections.size()).is_equal(0)


func test_pause_accepts_commands_and_applies_them_on_resume() -> void:
	_server.allow_time_scale = true
	var a := _add_client()
	_pump(4)
	var tick_before := _server.sim.tick
	_server.set_paused(true)
	assert_int(_server.update(1.0)).is_equal(0)
	var mine := _ids_of(1)
	# 40 órdenes en 2 s de pausa: la ventana de 30/s es de tiempo real y se renueva.
	for i: int in 40:
		a.send_command(Command.make_move(0, mine, Vector2(5000 + i, 5000)))
		if i == 20:
			_net.advance(1000)
			_server.manual_msec = _net.now_msec()
		_server.update(0.05)
		a.update(0.05)
	assert_int(_server.sim.tick).is_equal(tick_before)
	assert_int(_rejections.size()).is_equal(0)
	assert_int(_server.sim.queue.pending_count()).is_equal(40)
	_server.set_paused(false)
	assert_int(_server.update(0.06)).is_equal(1)
	assert_int(_server.sim.queue.pending_count()).is_equal(0)
	# Sin allow_time_scale (multijugador) la pausa no existe.
	_server.allow_time_scale = false
	_server.set_paused(true)
	assert_float(_server.accumulator.time_scale).is_equal(1.0)


func test_latency_and_loss_converge_and_interpolate() -> void:
	_net.latency_msec = 80
	_net.loss = 0.1
	var a := _add_client()
	var b := _add_client()
	_pump(10)
	var mine := _ids_of(1)
	a.send_command(Command.make_move(0, mine, Vector2(5085.0, 5000.0)))
	_pump(60)
	# Los snapshots siguen completándose y confirmándose pese a la pérdida.
	assert_int(b.receiver.snapshots_completed).is_greater(15)
	assert_int(_server.get_conn(2).sender.base_tick).is_greater(0)
	# Interpolación: el reloj de dibujo va ~200 ms (4 ticks) detrás del último snapshot.
	assert_float(b.render_tick).is_between(b.receiver.latest_tick - 6.0, b.receiver.latest_tick - 2.0)
	var cb := b.state.slot_of(mine[0])
	var s := _server.sim.store.slot_of(mine[0])
	# Lo dibujado está cerca de la posición real (5 m/s, ~200 ms de retraso + latencia).
	assert_float(absf(b.state.render_x[cb] - _server.sim.store.pos_x[s])).is_less(4.0)
	# Al detenerse todo, el cliente converge a la posición exacta (± cuantización).
	_net.loss = 0.0
	_pump(200)
	var smp := b.state.latest_sample(cb)
	assert_float(absf(smp.x - _server.sim.store.pos_x[s])).is_less_equal(0.19)
	assert_float(absf(b.state.render_x[cb] - _server.sim.store.pos_x[s])).is_less_equal(0.19)


func test_client_state_dead_reckoning_and_smooth_correction() -> void:
	var cs := ClientState.new()
	var p := SnapshotCodec.Part.new()
	p.rec_ids = PackedInt32Array([7])
	p.rec_appear = PackedByteArray([1])
	p.rec_def = PackedInt32Array([0])
	p.rec_owner = PackedInt32Array([1])
	p.rec_prog = PackedByteArray([0])
	var v5 := SnapshotCodec.pack_vel(SnapshotCodec.quantize_vel(5.0), 0)
	# Trayectoria A: x = 0 en el tick 10, 5 m/s hacia +x.
	p.tick = 10
	p.rec_ref = PackedInt32Array([10])
	p.rec_vel = PackedInt32Array([v5])
	p.rec_words = PackedInt64Array([SnapshotCodec.pack_word(MapGrid.quantize(0.0), MapGrid.quantize(0.0), 0, 255, 1)])
	cs.apply_part(p)
	cs.interpolate(12.0)  # extrapola: 2 ticks = 0,1 s = 0,5 m
	assert_float(cs.render_x[0]).is_equal_approx(0.5, 0.07)
	# Trayectoria B: reanclada en el tick 14 en x = 1,5 (A predecía 1,0: error de 0,5 m).
	p.tick = 14
	p.rec_appear = PackedByteArray([0])
	p.rec_ref = PackedInt32Array([14])
	p.rec_words = PackedInt64Array([SnapshotCodec.pack_word(MapGrid.quantize(1.5), MapGrid.quantize(0.0), 0, 255, 1)])
	cs.apply_part(p)
	cs.interpolate(13.0)  # todavía en A
	assert_float(cs.render_x[0]).is_equal_approx(0.75, 0.07)
	cs.interpolate(14.0)  # pasa a B sin saltar: queda entre A (1,0) y B (1,5)
	assert_float(cs.render_x[0]).is_greater(1.0)
	assert_float(cs.render_x[0]).is_less(1.45)
	cs.interpolate(60.0)  # la corrección se desvaneció: 1,5 + 5 m/s * 2,3 s
	assert_float(cs.render_x[0]).is_equal_approx(13.0, 0.08)
	assert_float(cs.predicted(0, 60.0).x).is_equal_approx(13.0, 0.08)
	cs.remove(7)
	assert_int(cs.count).is_equal(0)


func test_command_log_and_queue_are_bounded() -> void:
	assert_int(_server.sim.queue.max_log_entries).is_greater(0)
	assert_int(CommandQueue.MAX_PENDING).is_greater(0)


func test_full_resend_after_outage_leaves_no_ghosts() -> void:
	# Más entidades de las que entran en un snapshot: el reenvío completo se reparte en varios.
	_server.spawn_test_armies(2, 800, 60.0)
	var a := _add_client()
	_pump(80)
	var total: int = _server.sim.store.count
	assert_int(a.state.count).is_equal(total)
	var sender := _server.get_conn(1).sender
	assert_bool(sender.last_synced).is_true()
	# Corte de 1,5 s en el canal unreliable (snapshots y acks): baja y salida de visión en medio.
	_net.loss = 1.0
	_pump(6)
	var enemies := _ids_of(2)
	var dead: int = enemies[0]
	var gone: int = enemies[1]
	_server.sim.remove_entity(dead)
	var sg := _server.sim.store.slot_of(gone)
	_server.sim.store.pos_x[sg] = 9500.0
	_server.sim.store.pos_z[sg] = 9500.0
	_pump(30)
	assert_int(sender.full_resets).is_greater_equal(1)
	# Durante el corte, el cliente todavía las tiene.
	assert_int(a.state.slot_of(dead)).is_greater_equal(0)
	assert_int(a.state.slot_of(gone)).is_greater_equal(0)
	_net.loss = 0.0
	_pump(80)
	assert_bool(sender.last_synced).is_true()
	assert_int(a.state.slot_of(dead)).is_equal(-1)
	assert_int(a.state.slot_of(gone)).is_equal(-1)
	assert_int(a.ghosts_removed).is_greater_equal(2)
	assert_int(a.state.count).is_equal(total - 2)
	var st := a.receiver.get_state(a.receiver.latest_complete_tick)
	assert_int(st.size()).is_equal(total - 2)
	for s: int in a.state.count:
		assert_int(st.index_of(a.state.ids[s])).is_greater_equal(0)
