extends GdUnitTestSuite
## SnapshotCodec, SnapshotSender (servidor) y SnapshotReceiver (cliente): cuantización, ida y
## vuelta, delta contra ack, acks perdidos, REMOVED, reenvío completo, tope de 4 KB, paquetes de
## 1200 B y pérdida de paquetes. El invariante clave: cuando el cliente completa un snapshot, su
## estado es idéntico, bit a bit, al que el servidor guardó para ese tick.

const HALF_STEP: float = 0.0625
## Error máximo de la predicción del cliente: umbral del dead reckoning + medio paso.
const DR_BOUND: float = SnapshotCodec.DR_THRESHOLD_M + HALF_STEP + 0.001


# --- Ayudas ------------------------------------------------------------------------------------

func _sim_with_block(owner: int, n: int, x0: float, z0: float, sim: Simulation = null) -> Simulation:
	var s := sim if sim != null else SimTestHelpers.make_sim()
	var cols: int = ceili(sqrt(float(n)))
	for i: int in n:
		s.spawn_entity(0, owner, x0 + (i % cols) * 2.0, z0 + (i / cols) * 2.0, 0.3)
	return s


func _capture(sim: Simulation) -> SnapshotWorld:
	sim.grid.rebuild(sim.store)
	var w := SnapshotWorld.new()
	w.capture(sim)
	return w


## Entrega `packets` al receptor (salvo los índices de `drop`) y devuelve el tick completado (o -1).
func _deliver(rx: SnapshotReceiver, packets: Array[PackedByteArray], drop: PackedInt32Array = PackedInt32Array()) -> int:
	var done: int = -1
	for i: int in packets.size():
		if drop.has(i):
			continue
		rx.receive(packets[i])
		if rx.completed_tick >= 0:
			done = rx.completed_tick
	return done


func _assert_same_state(a: SnapshotState, b: SnapshotState) -> void:
	assert_array(a.ids).is_equal(b.ids)
	assert_array(a.words).is_equal(b.words)
	assert_array(a.prog).is_equal(b.prog)


## Máximo error (m) entre la posición que predice el estado `st` (de tick `tick`) para ese mismo
## tick y la posición real de la simulación.
func _max_prediction_error(st: SnapshotState, tick: int, sim: Simulation) -> float:
	var worst: float = 0.0
	for i: int in st.size():
		var s := sim.store.slot_of(st.ids[i])
		if s < 0:
			continue
		var w: int = st.words[i]
		var v: int = st.vel[i]
		var dt: int = tick - st.ref[i]
		var x := MapGrid.dequantize(SnapshotCodec.predict_q(SnapshotCodec.word_qx(w), SnapshotCodec.vel_x8(v), dt))
		var z := MapGrid.dequantize(SnapshotCodec.predict_q(SnapshotCodec.word_qz(w), SnapshotCodec.vel_z8(v), dt))
		worst = maxf(worst, Vector2(x - sim.store.pos_x[s], z - sim.store.pos_z[s]).length())
	return worst


func _step(sim: Simulation, n: int) -> void:
	for i: int in n:
		sim.step()


# --- Cuantización ------------------------------------------------------------------------------

func test_position_quantization_error_is_half_step_at_corners() -> void:
	for x: float in [-65536.0, -65535.9, -1234.567, -0.01, 0.0, 0.06, 777.777, 65535.9, 65535.99]:
		var q := MapGrid.quantize(x)
		assert_int(q).is_between(0, MapGrid.QUANT_MAX)
		assert_float(absf(MapGrid.dequantize(q) - x)).is_less_equal(HALF_STEP)
	assert_float(MapGrid.QUANT_STEP).is_equal(MapGrid.MAP_SIZE / (1 << MapGrid.QUANT_BITS))


func test_heading_hp_and_word() -> void:
	for h: float in [-PI, -1.0, 0.0, 0.5, 3.0, PI - 0.001]:
		var back := SnapshotCodec.dequantize_heading(SnapshotCodec.quantize_heading(h))
		assert_float(absf(angle_difference(h, back))).is_less_equal(PI / 256.0 + 0.0001)
	assert_int(SnapshotCodec.quantize_hp(100.0, 100.0)).is_equal(255)
	assert_int(SnapshotCodec.quantize_hp(0.0, 100.0)).is_equal(0)
	assert_int(SnapshotCodec.quantize_hp(0.01, 1000.0)).is_equal(1)  # viva: nunca 0
	assert_float(absf(SnapshotCodec.dequantize_hp(SnapshotCodec.quantize_hp(37.0, 100.0)) - 0.37)).is_less_equal(1.0 / 510.0)
	var w := SnapshotCodec.pack_word(MapGrid.QUANT_MAX, 12345, 200, 17, 15)
	assert_int(SnapshotCodec.word_qx(w)).is_equal(MapGrid.QUANT_MAX)
	assert_int(SnapshotCodec.word_qz(w)).is_equal(12345)
	assert_int(SnapshotCodec.word_heading8(w)).is_equal(200)
	assert_int(SnapshotCodec.word_hp8(w)).is_equal(17)
	assert_int(SnapshotCodec.word_action(w)).is_equal(15)
	assert_bool(w > 0).is_true()


# --- Ida y vuelta y delta ------------------------------------------------------------------------

func test_full_snapshot_roundtrip() -> void:
	var sim := _sim_with_block(1, 30, 1000.0, 1000.0)
	_sim_with_block(2, 20, 1100.0, 1000.0, sim)
	_step(sim, 2)
	var world := _capture(sim)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var packets := tx.build(world, 42)
	assert_int(packets.size()).is_equal(1)
	var hdr := SnapshotCodec.read_header(packets[0])
	assert_int(hdr[1]).is_equal(SnapshotCodec.NO_BASE)
	assert_int(_deliver(rx, packets)).is_equal(world.tick)
	assert_int(rx.last_seq).is_equal(42)
	_assert_same_state(rx.get_state(world.tick), tx.get_state(world.tick))
	assert_int(rx.get_state(world.tick).size()).is_equal(50)
	# Lo que dibuja el cliente: posiciones con error <= medio paso.
	var cs := ClientState.new()
	var rx2 := SnapshotReceiver.new()
	cs.apply_part(rx2.receive(packets[0]))
	assert_int(cs.count).is_equal(50)
	for s: int in sim.store.count:
		var cslot := cs.slot_of(sim.store.id[s])
		assert_int(cslot).is_greater_equal(0)
		var smp := cs.latest_sample(cslot)
		assert_float(absf(smp.x - sim.store.pos_x[s])).is_less_equal(HALF_STEP + 0.001)
		assert_float(absf(smp.y - sim.store.pos_z[s])).is_less_equal(HALF_STEP + 0.001)
		assert_int(cs.owner[cslot]).is_equal(sim.store.owner[s])
		assert_int(cs.def_index[cslot]).is_equal(sim.store.def_index[s])


func test_delta_roundtrip_with_movement() -> void:
	var sim := _sim_with_block(1, 40, 2000.0, 2000.0)
	var ids := PackedInt32Array()
	for s: int in sim.store.count:
		ids.append(sim.store.id[s])
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var w0 := _capture(sim)
	var p0 := tx.build(w0, 0)
	var full_bytes: int = 0
	for p: PackedByteArray in p0:
		full_bytes += p.size()
	var done := _deliver(rx, p0)
	tx.on_ack(done, sim.tick)
	assert_int(tx.base_tick).is_equal(w0.tick)
	# Sin cambios: el delta solo lleva la cabecera.
	_step(sim, 2)
	var p1 := tx.build(_capture(sim), 0)
	assert_int(p1.size()).is_equal(1)
	assert_int(p1[0].size()).is_equal(SnapshotCodec.HEADER_BYTES)
	tx.on_ack(_deliver(rx, p1), sim.tick)
	# En movimiento: delta de 8 bits por eje, mucho más chico que el completo.
	sim.submit_command(1, Command.make_move(1, ids, Vector2(2100.0, 2050.0)))
	for k: int in 5:
		_step(sim, 2)
		var world := _capture(sim)
		var pk := tx.build(world, 1)
		var bytes: int = 0
		for p: PackedByteArray in pk:
			bytes += p.size()
		assert_int(bytes).is_less(full_bytes)
		var t := _deliver(rx, pk)
		assert_int(t).is_equal(world.tick)
		_assert_same_state(rx.get_state(t), tx.get_state(t))
		tx.on_ack(t, sim.tick)
	# Dead reckoning: lo que predice el cliente queda dentro del umbral (+ medio paso).
	assert_float(_max_prediction_error(rx.get_state(rx.latest_complete_tick), rx.latest_complete_tick, sim)).is_less_equal(DR_BOUND)


func test_lost_acks_keep_old_base_and_stay_exact() -> void:
	var sim := _sim_with_block(1, 30, 3000.0, 3000.0)
	var ids := PackedInt32Array()
	for s: int in sim.store.count:
		ids.append(sim.store.id[s])
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var w0 := _capture(sim)
	tx.on_ack(_deliver(rx, tx.build(w0, 0)), sim.tick)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(3050.0, 3000.0)))
	# Cuatro snapshots sin que lleguen los acks: todos son delta contra w0.
	for k: int in 4:
		_step(sim, 2)
		var world := _capture(sim)
		var pk := tx.build(world, 0)
		assert_int(SnapshotCodec.read_header(pk[0])[1]).is_equal(w0.tick)
		var t := _deliver(rx, pk)
		_assert_same_state(rx.get_state(t), tx.get_state(t))
	# Llega un ack viejo y otro más nuevo: la base avanza al más nuevo y no retrocede.
	tx.on_ack(rx.latest_complete_tick, sim.tick)
	var newest := tx.base_tick
	tx.on_ack(w0.tick, sim.tick)
	assert_int(tx.base_tick).is_equal(newest)


func test_removed_repeats_until_acked() -> void:
	var sim := _sim_with_block(1, 10, 1000.0, 1000.0)
	var victim: int = sim.store.id[3]
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var cs := ClientState.new()
	var w0 := _capture(sim)
	for p: PackedByteArray in tx.build(w0, 0):
		cs.apply_part(rx.receive(p))
	tx.on_ack(rx.completed_tick, sim.tick)
	assert_int(cs.slot_of(victim)).is_greater_equal(0)
	sim.remove_entity(victim)
	# Dos snapshots perdidos: REMOVED se repite en ambos.
	for k: int in 2:
		_step(sim, 2)
		var pk := tx.build(_capture(sim), 0)
		var part := SnapshotCodec.decode_part(pk[0], tx.get_state(tx.base_tick))
		assert_array(part.removed_ids).contains([victim])
		assert_int(part.removed_reasons[0]).is_equal(SnapshotCodec.RemoveReason.DIED)
	# Este sí llega y se confirma.
	_step(sim, 2)
	for p: PackedByteArray in tx.build(_capture(sim), 0):
		cs.apply_part(rx.receive(p))
	assert_int(cs.slot_of(victim)).is_equal(-1)
	tx.on_ack(rx.completed_tick, sim.tick)
	_step(sim, 2)
	var after := SnapshotCodec.decode_part(tx.build(_capture(sim), 0)[0], tx.get_state(tx.base_tick))
	assert_int(after.removed_ids.size()).is_equal(0)
	assert_int(rx.get_state(rx.latest_complete_tick).index_of(victim)).is_equal(-1)


func test_interest_and_out_of_view() -> void:
	var sim := _sim_with_block(1, 5, 1000.0, 1000.0)
	_sim_with_block(2, 5, 1100.0, 1000.0, sim)   # cerca: se ve
	_sim_with_block(3, 5, 6000.0, 6000.0, sim)   # lejos: no se ve
	var near_id: int = sim.store.id[5]
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	var st := rx.get_state(rx.latest_complete_tick)
	assert_int(st.size()).is_equal(10)
	for s: int in sim.store.count:
		if sim.store.owner[s] == 3:
			assert_int(st.index_of(sim.store.id[s])).is_equal(-1)
	# La unidad cercana del jugador 2 se aleja: sale de la vista con motivo OUT_OF_VIEW.
	var s2 := sim.store.slot_of(near_id)
	sim.store.pos_x[s2] = 8000.0
	sim.store.pos_z[s2] = 1000.0
	_step(sim, 2)
	var part := SnapshotCodec.decode_part(tx.build(_capture(sim), 0)[0], tx.get_state(tx.base_tick))
	assert_array(part.removed_ids).is_equal(PackedInt32Array([near_id]))
	assert_int(part.removed_reasons[0]).is_equal(SnapshotCodec.RemoveReason.OUT_OF_VIEW)


func test_full_resend_after_one_second_without_ack() -> void:
	var sim := _sim_with_block(1, 10, 1000.0, 1000.0)
	_step(sim, 2)
	var tx := SnapshotSender.new(1, sim.tick)
	var rx := SnapshotReceiver.new()
	tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	assert_int(tx.base_tick).is_greater_equal(0)
	# 1 s de snapshots sin ack: la base todavía vale.
	for k: int in SimConstants.TICK_RATE / 2:
		_step(sim, 2)
		var pk := tx.build(_capture(sim), 0)
		if sim.tick - tx.base_tick <= SnapshotSender.ACK_TIMEOUT_TICKS:
			assert_int(SnapshotCodec.read_header(pk[0])[1]).is_not_equal(SnapshotCodec.NO_BASE)
	_step(sim, 2)
	var full := tx.build(_capture(sim), 0)
	assert_int(SnapshotCodec.read_header(full[0])[1]).is_equal(SnapshotCodec.NO_BASE)
	assert_int(tx.full_resets).is_equal(1)
	# El cliente lo decodifica sin base y queda con todo.
	var t := _deliver(rx, full)
	assert_int(rx.get_state(t).size()).is_equal(10)


# --- Tope, paquetes y pérdida ------------------------------------------------------------------

func test_cap_4kb_packets_1200_and_parts_decode_alone() -> void:
	var sim := _sim_with_block(1, 1500, 1000.0, 1000.0)
	_sim_with_block(2, 1500, 1040.0, 1000.0, sim)
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var known: int = 0
	var rounds: int = 0
	while known < 3000 and rounds < 20:
		_step(sim, 2)
		var world := _capture(sim)
		var pk := tx.build(world, 0)
		var total: int = 0
		var base := tx.get_state(tx.base_tick) if tx.base_tick >= 0 else SnapshotState.new()
		for p: PackedByteArray in pk:
			assert_int(p.size()).is_less_equal(SnapshotCodec.MAX_PACKET_BYTES)
			total += p.size()
			# Cada parte se decodifica sola, sin las demás.
			assert_object(SnapshotCodec.decode_part(p, base)).is_not_null()
		assert_int(total).is_less_equal(SnapshotCodec.MAX_SNAPSHOT_BYTES)
		var t := _deliver(rx, pk)
		_assert_same_state(rx.get_state(t), tx.get_state(t))
		tx.on_ack(t, sim.tick)
		known = rx.get_state(t).size()
		rounds += 1
		if rounds == 1:
			assert_int(tx.last_deferred).is_greater(0)
			assert_int(pk.size()).is_greater(1)
	# 3000 apariciones de ~11 B con tope de 4 KB: unos 9 snapshots.
	assert_int(known).is_equal(3000)
	assert_int(rounds).is_less_equal(12)


func test_combat_entities_get_priority_and_nobody_starves() -> void:
	var sim := _sim_with_block(1, 1200, 1000.0, 1000.0)
	_sim_with_block(2, 1200, 1100.0, 1000.0, sim)
	var all := PackedInt32Array()
	for s: int in sim.store.count:
		all.append(sim.store.id[s])
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	for k: int in 12:  # aprender todo el estado
		_step(sim, 2)
		tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	assert_int(rx.get_state(rx.latest_complete_tick).size()).is_equal(2400)
	# Todos se mueven (más de lo que entra en 4 KB). Los del jugador 1 cerca del 2 pasan a combate.
	for start: int in range(0, 1200, 512):
		sim.submit_command(1, Command.make_move(1, all.slice(start, mini(start + 512, 1200)), Vector2(1500, 1500)))
	for start: int in range(1200, 2400, 512):
		sim.submit_command(2, Command.make_move(2, all.slice(start, mini(start + 512, 2400)), Vector2(600, 600)))
	var max_age: int = 0
	for k: int in 30:
		_step(sim, 2)
		var t := _deliver(rx, tx.build(_capture(sim), 0))
		_assert_same_state(rx.get_state(t), tx.get_state(t))
		tx.on_ack(t, sim.tick)
		if k > 10:
			max_age = maxi(max_age, tx.last_max_combat_age)
	# Con el tope, las entidades en combate no esperan más de ~5 snapshots.
	assert_int(max_age).is_less_equal(6)  # <= 300 ms


func test_packet_loss_never_breaks_the_state() -> void:
	var sim := _sim_with_block(1, 800, 1000.0, 1000.0)
	_sim_with_block(2, 800, 1060.0, 1000.0, sim)
	var all := PackedInt32Array()
	for s: int in sim.store.count:
		all.append(sim.store.id[s])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var cs := ClientState.new()
	var completed: int = 0
	for k: int in 80:
		if k % 10 == 0:
			var a := rng.randi_range(0, 1500)
			sim.submit_command(1 if all[a] <= 800 else 2, Command.make_move(k, all.slice(a, a + 1), Vector2(rng.randf_range(800, 1300), rng.randf_range(800, 1300))))
			for start: int in range(0, 800, 512):
				sim.submit_command(1, Command.make_move(k, all.slice(start, mini(start + 512, 800)), Vector2(rng.randf_range(900, 1200), rng.randf_range(900, 1200))))
		if k == 40:
			for i: int in 50:
				sim.remove_entity(all[i * 7])
		_step(sim, 2)
		var pk := tx.build(_capture(sim), 0)
		for p: PackedByteArray in pk:
			if rng.randf() < 0.2:
				continue  # 20 % de pérdida en los snapshots
			var part := rx.receive(p)
			if part != null:
				cs.apply_part(part)
			if rx.completed_tick >= 0:
				completed += 1
				_assert_same_state(rx.get_state(rx.completed_tick), tx.get_state(rx.completed_tick))
				if rng.randf() >= 0.2:  # 20 % de pérdida en los acks
					tx.on_ack(rx.completed_tick, sim.tick)
	assert_int(completed).is_greater(20)
	assert_int(rx.parts_rejected).is_equal(0)
	# Después de unos snapshots sin pérdida, el cliente conoce exactamente lo que ve.
	for k: int in 10:
		_step(sim, 2)
		for p: PackedByteArray in tx.build(_capture(sim), 0):
			var part := rx.receive(p)
			if part != null:
				cs.apply_part(part)
		tx.on_ack(rx.latest_complete_tick, sim.tick)
	var st := rx.get_state(rx.latest_complete_tick)
	assert_int(st.size()).is_equal(sim.store.count)
	assert_int(cs.count).is_equal(sim.store.count)


func test_malformed_parts_are_rejected() -> void:
	var sim := _sim_with_block(1, 20, 1000.0, 1000.0)
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var pk := tx.build(_capture(sim), 0)
	var bad := pk[0].duplicate()
	bad.resize(bad.size() - 4)
	assert_object(SnapshotCodec.decode_part(bad, SnapshotState.new())).is_null()
	var rx := SnapshotReceiver.new()
	assert_object(rx.receive(bad)).is_null()
	assert_int(rx.parts_rejected).is_equal(1)
	# Un delta cuya base el cliente no tiene se descarta (sin romper nada).
	tx.on_ack(sim.tick, sim.tick)
	_step(sim, 2)
	var delta := tx.build(_capture(sim), 0)
	assert_object(rx.receive(delta[0])).is_null()
	assert_int(rx.parts_without_base).is_equal(1)


# --- Dead reckoning ----------------------------------------------------------------------------

func test_velocity_roundtrip() -> void:
	for v: float in [-15.0, -5.0, -0.06, 0.0, 0.07, 1.4, 5.0, 15.875]:
		var q := SnapshotCodec.quantize_vel(v)
		var packed := SnapshotCodec.pack_vel(q, -q)
		assert_int(SnapshotCodec.vel_x8(packed)).is_equal(q)
		assert_int(SnapshotCodec.vel_z8(packed)).is_equal(-q)
		assert_float(absf(q * SnapshotCodec.VEL_STEP - v)).is_less_equal(SnapshotCodec.VEL_STEP / 2.0 + 0.001)
	# predict_q: 5 m/s durante 20 ticks (1 s) = 5 m = 40 pasos, en los dos sentidos.
	assert_int(SnapshotCodec.predict_q(1000, SnapshotCodec.quantize_vel(5.0), 20)).is_equal(1040)
	assert_int(SnapshotCodec.predict_q(1000, SnapshotCodec.quantize_vel(-5.0), 20)).is_equal(960)
	# Por el códec: la velocidad de la simulación llega al cliente.
	var sim := _sim_with_block(1, 4, 1000.0, 1000.0)
	var ids := PackedInt32Array()
	for s: int in sim.store.count:
		ids.append(sim.store.id[s])
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1200.0, 1000.0)))
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var cs := ClientState.new()
	for p: PackedByteArray in tx.build(_capture(sim), 0):
		cs.apply_part(rx.receive(p))
	var st := rx.get_state(rx.latest_complete_tick)
	for i: int in st.size():
		var s := sim.store.slot_of(st.ids[i])
		assert_float(absf(SnapshotCodec.vel_x8(st.vel[i]) * SnapshotCodec.VEL_STEP - sim.store.vel_x[s])).is_less_equal(0.0626)
		assert_float(absf(SnapshotCodec.vel_z8(st.vel[i]) * SnapshotCodec.VEL_STEP - sim.store.vel_z[s])).is_less_equal(0.0626)
	# El cliente extrapola: 1 s después predice ~5 m más adelante.
	var c0 := cs.slot_of(ids[0])
	var p0 := cs.predicted(c0, rx.latest_complete_tick)
	var p1 := cs.predicted(c0, rx.latest_complete_tick + 20)
	assert_float(p1.x - p0.x).is_between(4.5, 5.5)


func test_straight_line_sends_little_and_error_stays_bounded() -> void:
	var sim := _sim_with_block(1, 50, 1000.0, 1000.0)
	var ids := PackedInt32Array()
	for s: int in sim.store.count:
		ids.append(sim.store.id[s])
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	sim.submit_command(1, Command.make_move(1, ids, Vector2(1400.0, 1300.0)))
	var records: int = 0
	var snaps: int = 0
	for k: int in 100:  # 10 s en línea recta
		_step(sim, 2)
		var t := _deliver(rx, tx.build(_capture(sim), 0))
		tx.on_ack(t, sim.tick)
		assert_float(_max_prediction_error(rx.get_state(t), t, sim)).is_less_equal(DR_BOUND)
		if k >= 5:
			records += tx.last_records
			snaps += 1
	# En régimen, cada unidad se reancla como mucho cada ~1 s (error de cuantización de la
	# velocidad), no en cada snapshot: menos de 0,15 registros por unidad y snapshot.
	assert_float(float(records) / (snaps * 50)).is_less(0.15)


func test_direction_change_forces_send() -> void:
	var sim := _sim_with_block(1, 1, 1000.0, 1000.0)
	var id: int = sim.store.id[0]
	sim.submit_command(1, Command.make_move(1, PackedInt32Array([id]), Vector2(1100.0, 1000.0)))
	_step(sim, 2)
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	for k: int in 6:
		_step(sim, 2)
		tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	# En línea recta y ya anclada: no se envía.
	_step(sim, 2)
	tx.on_ack(_deliver(rx, tx.build(_capture(sim), 0)), sim.tick)
	assert_int(tx.last_records).is_equal(0)
	# Gira 90°: el siguiente snapshot la reancla aunque el error todavía sea chico.
	sim.submit_command(1, Command.make_move(2, PackedInt32Array([id]), Vector2(sim.store.pos_x[0], 1200.0)))
	_step(sim, 2)
	var pk := tx.build(_capture(sim), 0)
	assert_int(tx.last_records).is_equal(1)
	var part := SnapshotCodec.decode_part(pk[0], tx.get_state(tx.base_tick))
	assert_int(part.rec_ref[0]).is_equal(sim.tick)
	assert_int(SnapshotCodec.vel_z8(part.rec_vel[0])).is_equal(SnapshotCodec.quantize_vel(5.0))
	# Y al detenerse también.
	tx.on_ack(_deliver(rx, pk), sim.tick)
	sim.submit_command(1, Command.make_stop(3, PackedInt32Array([id])))
	_step(sim, 2)
	tx.build(_capture(sim), 0)
	assert_int(tx.last_records).is_equal(1)


func test_no_divergence_with_20_percent_loss() -> void:
	var sim := _sim_with_block(1, 300, 1000.0, 1000.0)
	_sim_with_block(2, 300, 1050.0, 1000.0, sim)
	var all := PackedInt32Array()
	for s: int in sim.store.count:
		all.append(sim.store.id[s])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tx := SnapshotSender.new(1)
	var rx := SnapshotReceiver.new()
	var cs := ClientState.new()
	for k: int in 150:
		if k % 15 == 0:
			for start: int in range(0, 300, 100):
				sim.submit_command(1, Command.make_move(k, all.slice(start, start + 100), Vector2(rng.randf_range(800, 1300), rng.randf_range(800, 1300))))
				sim.submit_command(2, Command.make_move(k, all.slice(300 + start, 400 + start), Vector2(rng.randf_range(800, 1300), rng.randf_range(800, 1300))))
		_step(sim, 2)
		for p: PackedByteArray in tx.build(_capture(sim), 0):
			if rng.randf() < 0.2:
				continue
			var part := rx.receive(p)
			if part != null:
				cs.apply_part(part)
			if rx.completed_tick >= 0:
				_assert_same_state(rx.get_state(rx.completed_tick), tx.get_state(rx.completed_tick))
				if rng.randf() >= 0.2:
					tx.on_ack(rx.completed_tick, sim.tick)
	# Tras unos snapshots sin pérdida, la predicción del cliente vuelve a estar dentro del umbral.
	for k: int in 6:
		_step(sim, 2)
		for p: PackedByteArray in tx.build(_capture(sim), 0):
			var part := rx.receive(p)
			if part != null:
				cs.apply_part(part)
		tx.on_ack(rx.latest_complete_tick, sim.tick)
	var t := rx.latest_complete_tick
	assert_int(t).is_equal(sim.tick)
	assert_float(_max_prediction_error(rx.get_state(t), t, sim)).is_less_equal(DR_BOUND)
	for s: int in cs.count:
		var p := cs.predicted(s, t)
		var ss := sim.store.slot_of(cs.ids[s])
		assert_float(p.distance_to(Vector2(sim.store.pos_x[ss], sim.store.pos_z[ss]))).is_less_equal(DR_BOUND + 0.01)
