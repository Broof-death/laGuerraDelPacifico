extends Node
## Prueba de carga headless de la simulación y de la red (ADR-006 punto 10).
##
## Uso (desde la raíz del proyecto):
##   godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S1
##   godot --headless --path . res://tests/load/load_test.tscn -- --players=6 --units=500 --seconds=120 --seed=1
##
## Cada jugador empieza con N unidades en bloque sobre un círculo alrededor del centro del mapa.
## Los bots deciden a 2 Hz por la misma cola de comandos que un jugador: ATTACK_MOVE de todo el
## ejército al lado opuesto del círculo (los ejércitos se cruzan en el centro, una batalla grande)
## y, en cada decisión, una orden MOVE a un subconjunto de 16 unidades (micro).
##
## Los snapshots usan dead reckoning (enmienda de ADR-006): una vez por segundo se mide el error
## entre lo que predice cada fantasma y la posición real (dr_error_cm).
## La simulación corre dentro de un MatchServer (T-005) con un cliente "fantasma" por jugador
## (MatchClient sin interpolación) conectado por LocalTransport con 2 % de pérdida en el canal
## unreliable (snapshots y acks). Cada fantasma decodifica sus snapshots y confirma con ack.
## Mide el tiempo de cada tick completo (step() + armado de snapshots) y de cada sistema, con los
## ticks corriendo tan rápido como se pueda (no en tiempo real; el reloj de la red es manual y
## avanza 50 ms por tick). También mide bytes por snapshot, KB/s por jugador, antigüedad de las
## entidades en combate y el tiempo de decodificación de los fantasmas (fuera del tick).
## Salida JSON en la consola (línea "LOAD_RESULT {...}") y en user://load/. Código de salida 0 si
## cumple los umbrales del escenario, 1 si no.

## Sincronización inicial (desde el saludo hasta que todos los fantasmas conocen todo lo que ven,
## SnapshotSender.last_synced): umbral propio de T-005, no de ADR-006. Cota física: cada
## aparición ocupa ~12,4 B y el tope es de 4 KB por snapshot a 10 Hz, así que 3000 visibles
## necesitan >= 0,9 s y 4500, >= 1,4 s; el umbral deja margen para la pérdida y los acks.
## Umbrales de ADR-006 punto 10. battle_kbps, combat_age_ms y sync_ms < 0 = sin umbral.
const SCENARIOS: Dictionary = {
	"S1": {"players": 2, "units": 500, "p95_ms": 6.0, "p99_ms": -1.0, "battle_kbps": -1.0, "combat_age_ms": -1.0, "sync_ms": -1.0},
	"S2": {"players": 6, "units": 500, "p95_ms": 20.0, "p99_ms": 35.0, "battle_kbps": 25.0, "combat_age_ms": 300.0, "sync_ms": 2000.0},
	"S3": {"players": 6, "units": 750, "p95_ms": 35.0, "p99_ms": -1.0, "battle_kbps": -1.0, "combat_age_ms": 500.0, "sync_ms": 2500.0},
}
## Tope de bajada por jugador (ADR-006: 40 KB/s; con el tope de 4 KB a 10 Hz no se puede pasar).
const MAX_KBPS: float = 40.0
## Un segundo cuenta como "de batalla" si al menos esta fracción de entidades tiene objetivo.
const BATTLE_TARGET_FRACTION: float = 0.25
const BOT_DECISION_TICKS: int = SimConstants.TICK_RATE / 2  # 2 Hz
const START_RADIUS: float = 200.0
const MICRO_UNITS: int = 16
const WARMUP_TICKS: int = 20
## Las estadísticas por snapshot (bytes, antigüedad) empiezan a los 3 s: antes, cada fantasma
## recibe el estado inicial completo (apariciones de ~13 B con el tope de 4 KB: ~1,1 s con 3000
## entidades y ~1,6 s con 4500). Los KB/s por segundo sí incluyen esa sincronización.
const NET_WARMUP_TICKS: int = 60

var _sim: Simulation
var _server: MatchServer
var _net: LocalNetwork
var _ghosts: Array[MatchClient] = []
var _rng := RandomNumberGenerator.new()
var _armies: Array[PackedInt32Array] = []
var _bot_side: PackedInt32Array = PackedInt32Array()  # 0 = va hacia el lado opuesto, 1 = vuelve
var _seq: int = 0
var _commands_sent: int = 0
var _commands_rejected: int = 0
var _start_radius: float = START_RADIUS
# Error de la predicción (dead reckoning) de los fantasmas, medido una vez por segundo.
var _dr_err_cm := PackedInt64Array()
var _dr_checked: int = 0
var _dr_over: int = 0
## Ticks (los primeros 40) en que alguna entidad en combate llevaba más de 300 ms desactualizada.
var _late_ticks := PackedInt32Array()


func _ready() -> void:
	var args := _parse_args()
	var scenario: String = args.get("scenario", "")
	var preset: Dictionary = SCENARIOS.get(scenario, {})
	var players: int = int(args.get("players", preset.get("players", 2)))
	var units: int = int(args.get("units", preset.get("units", 500)))
	var seconds: float = float(args.get("seconds", 120.0))
	var seed_value: int = int(args.get("seed", 1))
	var deaths_per_sec: int = int(args.get("deaths_per_sec", 0))
	var loss: float = float(args.get("loss", 0.02))
	var ghosts_enabled: bool = args.get("ghosts", "1") != "0"
	_start_radius = float(args.get("radius", START_RADIUS))
	if scenario == "":
		scenario = "custom"

	var data: GameData = load(GameData.DEFAULT_PATH)
	var errors := data.build_index()
	if not errors.is_empty():
		push_error("GameData inválido: %s" % [errors])
		get_tree().quit(2)
		return

	_rng.seed = seed_value
	_sim = Simulation.new(data, seed_value)
	_sim.profiling = true
	_spawn_armies(players, units)
	_server = MatchServer.new(_sim)
	_server.profiling = true
	_net = LocalNetwork.new(seed_value)
	_net.manual_clock = true
	_net.loss = loss
	_server.manual_msec = _net.now_msec()
	_server.add_transport(_net.create_server())
	if ghosts_enabled:
		for p: int in players:
			var g := MatchClient.new(_net.create_client(), data.catalog_hash())
			g.interpolate_enabled = false
			_ghosts.append(g)
		# Saludo: cada fantasma recibe el player_id en orden de conexión (1..P = dueños de los ejércitos).
		for i: int in 3:
			_server.poll()
			for g: MatchClient in _ghosts:
				g.update(0.0)
		for p: int in players:
			if _ghosts[p].player_id != p + 1:
				push_error("El fantasma %d recibió el jugador %d" % [p, _ghosts[p].player_id])
				get_tree().quit(2)
				return

	var ticks: int = int(seconds * SimConstants.TICK_RATE)
	var tick_usec := PackedInt64Array()
	var snap_usec := PackedInt64Array()
	var ghost_usec := PackedInt64Array()
	var sys_usec: Array[PackedInt64Array] = []
	for i: int in Simulation.SystemId.COUNT:
		sys_usec.append(PackedInt64Array())
	var max_targets: int = 0
	# Por snapshot (de cada jugador): bytes, antigüedad máx. en combate (ticks) y aplazados.
	var snap_bytes := PackedInt64Array()
	var snap_age := PackedInt64Array()
	var snap_deferred := PackedInt64Array()
	var max_packet: int = 0
	var cap_cuts: int = 0
	# Por segundo y jugador: bytes enviados; y por segundo, si fue de batalla.
	var second_bytes: Array[PackedInt64Array] = []
	var battle_seconds := PackedByteArray()
	var cur_bytes := PackedInt64Array()
	cur_bytes.resize(players)
	var sent_before := PackedInt32Array()
	sent_before.resize(players)
	var sync_tick: int = -1

	var wall_start := Time.get_ticks_usec()
	for t: int in ticks:
		if t % BOT_DECISION_TICKS == 0:
			_bots_decide(players)
		_churn(players, deaths_per_sec, t)
		_server.poll()
		var t0 := Time.get_ticks_usec()
		_server.tick_once()
		var dt := Time.get_ticks_usec() - t0
		var measured: bool = t >= mini(WARMUP_TICKS, ticks / 10)
		if measured:
			tick_usec.append(dt)
			snap_usec.append(_server.last_snapshot_usec)
			for i: int in Simulation.SystemId.COUNT:
				sys_usec[i].append(_sim.last_system_usec[i])
		# Estadísticas de los snapshots armados en este tick.
		for p: int in players:
			var conn := _server.get_conn(p + 1)
			if conn == null or conn.sender.snapshots_sent == sent_before[p]:
				continue
			sent_before[p] = conn.sender.snapshots_sent
			cur_bytes[p] += conn.sender.last_bytes
			if t >= NET_WARMUP_TICKS:
				snap_bytes.append(conn.sender.last_bytes)
				snap_age.append(conn.sender.last_max_combat_age)
				if conn.sender.last_max_combat_age > 6 and _late_ticks.size() < 40:
					_late_ticks.append(t)
				snap_deferred.append(conn.sender.last_deferred)
				max_packet = maxi(max_packet, conn.sender.last_max_packet_bytes)
				cap_cuts += conn.sender.last_cap_cuts
		if sync_tick < 0 and not _ghosts.is_empty():
			var all_synced: bool = true
			for p: int in players:
				var conn := _server.get_conn(p + 1)
				all_synced = all_synced and conn.sender.snapshots_sent > 0 and conn.sender.last_synced
			if all_synced:
				sync_tick = t
		# Red y fantasmas (fuera del tiempo del tick).
		_net.advance(1000 / SimConstants.TICK_RATE)
		_server.manual_msec = _net.now_msec()
		var g0 := Time.get_ticks_usec()
		for g: MatchClient in _ghosts:
			g.update(SimConstants.TICK_DT)
		if measured and not _ghosts.is_empty():
			ghost_usec.append(Time.get_ticks_usec() - g0)
		if (t + 1) % SimConstants.TICK_RATE == 0:
			second_bytes.append(cur_bytes.duplicate())
			cur_bytes.fill(0)
			var with_target := _count_with_target()
			battle_seconds.append(1 if with_target >= _sim.store.count * BATTLE_TARGET_FRACTION else 0)
			max_targets = maxi(max_targets, with_target)
			if measured:
				_measure_dr_error()
	var wall_s: float = (Time.get_ticks_usec() - wall_start) / 1_000_000.0
	var net_result := _net_stats(players, snap_bytes, snap_age, snap_deferred, max_packet, cap_cuts,
			second_bytes, battle_seconds, ghost_usec, loss)
	if not _ghosts.is_empty():
		net_result["initial_sync_ms"] = (sync_tick + 1) * 1000 / SimConstants.TICK_RATE if sync_tick >= 0 else -1

	var result := {
		"scenario": scenario,
		"players": players,
		"units_per_player": units,
		"entities": _sim.store.count,
		"seconds_simulated": seconds,
		"ticks_measured": tick_usec.size(),
		"seed": seed_value,
		"deaths_per_sec": deaths_per_sec,
		"start_radius": _start_radius,
		"wall_seconds": snappedf(wall_s, 0.01),
		"tick_ms": _stats_ms(tick_usec),
		"snapshot_build_ms": _stats_ms(snap_usec),
		"systems_ms": {},
		"commands_sent": _commands_sent,
		"commands_rejected": _commands_rejected,
		"max_entities_with_target": max_targets,
		"static_memory_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"net": net_result,
		"machine": {
			"cpu": OS.get_processor_name(),
			"cores": OS.get_processor_count(),
			"os": OS.get_name(),
			"godot": Engine.get_version_info().string,
			"debug_build": OS.is_debug_build(),
		},
	}
	for i: int in Simulation.SystemId.COUNT:
		result["systems_ms"][Simulation.SYSTEM_NAMES[i]] = _stats_ms(sys_usec[i])

	var threshold: Dictionary = SCENARIOS.get(scenario, {})
	var passed: bool = true
	if not threshold.is_empty():
		result["threshold"] = threshold.duplicate()
		result["threshold"]["snapshot_max_bytes"] = SnapshotCodec.MAX_SNAPSHOT_BYTES
		result["threshold"]["max_kbps"] = MAX_KBPS
		var checks := {}
		checks["tick_p95"] = result["tick_ms"].get("p95", INF) <= threshold["p95_ms"]
		if threshold["p99_ms"] > 0.0:
			checks["tick_p99"] = result["tick_ms"].get("p99", INF) <= threshold["p99_ms"]
		if not _ghosts.is_empty():
			checks["snapshot_cap"] = net_result["snapshot_bytes"].get("max", 0) <= SnapshotCodec.MAX_SNAPSHOT_BYTES \
					and net_result["max_packet_bytes"] <= SnapshotCodec.MAX_PACKET_BYTES
			checks["max_kbps"] = net_result["kbps_per_player"]["max_second"] <= MAX_KBPS
			if threshold["battle_kbps"] > 0.0:
				checks["battle_kbps"] = net_result["kbps_per_player"]["battle_mean"] <= threshold["battle_kbps"]
			if threshold["combat_age_ms"] > 0.0:
				checks["combat_age"] = net_result["combat_age_ms"].get("max", 0) <= threshold["combat_age_ms"]
			checks["ghosts_consistent"] = net_result["ghosts_consistent"]
			if threshold["sync_ms"] > 0.0:
				checks["initial_sync"] = net_result["initial_sync_ms"] >= 0 and net_result["initial_sync_ms"] <= threshold["sync_ms"]
		for k: String in checks:
			passed = passed and checks[k]
		result["checks"] = checks
		result["pass"] = passed

	var json := JSON.stringify(result, "  ", false)
	print("LOAD_RESULT ", JSON.stringify(result, "", false))
	_save(scenario, json)
	for g: MatchClient in _ghosts:
		g.close()
	_ghosts.clear()
	_server.close()
	_server = null
	_sim = null
	get_tree().quit(0 if passed else 1)


func _spawn_armies(players: int, units: int) -> void:
	var center := _sim.bounds.get_center()
	var cols: int = ceili(sqrt(float(units)))
	var spacing: float = 2.5
	for p: int in players:
		var angle: float = TAU * p / players
		var base := center + Vector2(cos(angle), sin(angle)) * _start_radius
		var ids := PackedInt32Array()
		for i: int in units:
			var off := Vector2((i % cols - cols * 0.5) * spacing, (i / cols - cols * 0.5) * spacing)
			var pos := base + off
			ids.append(_sim.spawn_entity(0, p + 1, pos.x, pos.y, angle + PI))
		_armies.append(ids)
		_bot_side.append(0)


## IA bot mínima (2 Hz): cruza el ejército al lado opuesto y hace micro con 16 unidades.
func _bots_decide(players: int) -> void:
	var center := _sim.bounds.get_center()
	for p: int in players:
		var ids: PackedInt32Array = _armies[p]
		var angle: float = TAU * p / players
		var home := center + Vector2(cos(angle), sin(angle)) * _start_radius
		var away := center - Vector2(cos(angle), sin(angle)) * _start_radius
		if _army_idle_ratio(ids) > 0.9:
			var dest: Vector2 = away if _bot_side[p] == 0 else home
			_bot_side[p] = 1 - _bot_side[p]
			# Máximo 512 ids por comando: los ejércitos grandes se ordenan en varias partes.
			var max_ids: int = SimConstants.MAX_IDS_PER_COMMAND
			for start: int in range(0, ids.size(), max_ids):
				var part := ids.slice(start, mini(start + max_ids, ids.size()))
				_submit(p + 1, Command.make_move(_next_seq(), part, dest, true))
		else:
			var subset := PackedInt32Array()
			var start: int = _rng.randi_range(0, ids.size() - MICRO_UNITS)
			for i: int in MICRO_UNITS:
				subset.append(ids[start + i])
			var s := _sim.store.slot_of(subset[0])
			var jitter := Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-30.0, 30.0))
			var target := Vector2(_sim.store.dest_x[s], _sim.store.dest_z[s]) + jitter
			_submit(p + 1, Command.make_move(_next_seq(), subset, target, true))


## Simula bajas mientras no exista el combate: borra entidades al azar (swap-remove, invalida los
## objetivos de quienes las apuntaban) y repone cada una en la base de su jugador, para que el
## total se mantenga. Corre fuera de step(), así que su costo no entra en el tiempo por tick.
func _churn(players: int, deaths_per_sec: int, t: int) -> void:
	if deaths_per_sec <= 0:
		return
	# Reparte las bajas del segundo entre sus 20 ticks.
	var per_tick: int = (deaths_per_sec * (t % SimConstants.TICK_RATE + 1)) / SimConstants.TICK_RATE \
			- (deaths_per_sec * (t % SimConstants.TICK_RATE)) / SimConstants.TICK_RATE
	var center := _sim.bounds.get_center()
	for k: int in per_tick:
		var p: int = _rng.randi_range(0, players - 1)
		var ids: PackedInt32Array = _armies[p]
		var idx: int = _rng.randi_range(0, ids.size() - 1)
		_sim.remove_entity(ids[idx])
		ids.remove_at(idx)
		var angle: float = TAU * p / players
		var home := center + Vector2(cos(angle), sin(angle)) * _start_radius
		# Los ids nuevos son mayores que todos: la lista sigue ordenada.
		ids.append(_sim.spawn_entity(0, p + 1, home.x + _rng.randf_range(-20.0, 20.0), home.y + _rng.randf_range(-20.0, 20.0)))
		_armies[p] = ids


func _army_idle_ratio(ids: PackedInt32Array) -> float:
	var idle: int = 0
	for e: int in ids:
		var s := _sim.store.slot_of(e)
		if s >= 0 and _sim.store.action[s] == SimConstants.Action.IDLE:
			idle += 1
	return float(idle) / maxi(1, ids.size())


func _count_with_target() -> int:
	var n: int = 0
	var targets := _sim.store.target_id
	for s: int in _sim.store.count:
		if targets[s] != 0:
			n += 1
	return n


## Para cada fantasma: con su último estado completo (tick T), predice la posición de cada
## entidad en el tick actual del servidor y la compara con la real. Registra el error máximo por
## fantasma (en cm) y cuántas entidades están fuera del umbral (+ medio paso de cuantización). Lo
## que pasó entre T y el tick actual (1-2 ticks) también cuenta, así que es una cota pesimista.
func _measure_dr_error() -> void:
	var now: int = _sim.tick
	var limit: float = SnapshotCodec.DR_THRESHOLD_M + 0.0625 + 0.001
	for g: MatchClient in _ghosts:
		var t: int = g.receiver.latest_complete_tick
		if t < 0:
			continue
		var st: SnapshotState = g.receiver.get_state(t)
		var worst: float = 0.0
		for i: int in st.size():
			var s := _sim.store.slot_of(st.ids[i])
			if s < 0:
				continue
			var w: int = st.words[i]
			var v: int = st.vel[i]
			var dt: int = now - st.ref[i]
			var x := MapGrid.dequantize(SnapshotCodec.predict_q(SnapshotCodec.word_qx(w), SnapshotCodec.vel_x8(v), dt))
			var z := MapGrid.dequantize(SnapshotCodec.predict_q(SnapshotCodec.word_qz(w), SnapshotCodec.vel_z8(v), dt))
			var e := Vector2(x - _sim.store.pos_x[s], z - _sim.store.pos_z[s]).length()
			worst = maxf(worst, e)
			_dr_checked += 1
			if e > limit:
				_dr_over += 1
		_dr_err_cm.append(int(worst * 100.0))


func _submit(player_id: int, cmd: Command) -> void:
	_commands_sent += 1
	if _sim.submit_command(player_id, cmd) != Command.Reject.OK:
		_commands_rejected += 1


func _next_seq() -> int:
	_seq += 1
	return _seq


func _net_stats(players: int, snap_bytes: PackedInt64Array, snap_age: PackedInt64Array,
		snap_deferred: PackedInt64Array, max_packet: int, cap_cuts: int, second_bytes: Array[PackedInt64Array],
		battle_seconds: PackedByteArray, ghost_usec: PackedInt64Array, loss: float) -> Dictionary:
	if _ghosts.is_empty():
		return {"ghosts": 0}
	# KB/s por jugador: media de todos los segundos, de los de batalla y el peor segundo.
	var all_sum: float = 0.0
	var all_n: int = 0
	var battle_sum: float = 0.0
	var battle_n: int = 0
	var max_second: float = 0.0
	for sec: int in second_bytes.size():
		for p: int in players:
			var kb: float = second_bytes[sec][p] / 1024.0
			all_sum += kb
			all_n += 1
			max_second = maxf(max_second, kb)
			if battle_seconds[sec] != 0:
				battle_sum += kb
				battle_n += 1
	var age_ms := PackedInt64Array()
	for a: int in snap_age:
		age_ms.append(a * 1000 / SimConstants.TICK_RATE)
	# Coherencia: el último estado completo de cada fantasma es idéntico al que guardó el servidor.
	var consistent: bool = true
	var completed: int = 0
	var parts_dropped: int = 0
	var full_resets: int = 0
	for p: int in players:
		var g := _ghosts[p]
		var sender := _server.get_conn(p + 1).sender
		full_resets += sender.full_resets
		completed += g.receiver.snapshots_completed
		parts_dropped += g.receiver.parts_rejected + g.receiver.parts_without_base
		var t: int = g.receiver.latest_complete_tick
		if t < 0 or not sender.has_state(t):
			continue
		var a: SnapshotState = g.receiver.get_state(t)
		var b: SnapshotState = sender.get_state(t)
		if a.ids != b.ids or a.words != b.words:
			consistent = false
	return {
		"ghosts": _ghosts.size(),
		"loss": loss,
		"snapshots": snap_bytes.size(),
		"snapshot_bytes": _stats_int(snap_bytes),
		"max_packet_bytes": max_packet,
		"cap_cuts": cap_cuts,
		"deferred_per_snapshot": _stats_int(snap_deferred),
		"kbps_per_player": {
			"mean": snappedf(all_sum / maxi(all_n, 1), 0.01),
			"battle_mean": snappedf(battle_sum / maxi(battle_n, 1), 0.01),
			"battle_seconds": battle_n / maxi(players, 1),
			"max_second": snappedf(max_second, 0.01),
		},
		"combat_age_ms": _stats_int(age_ms),
		"ghost_decode_ms_per_tick": _stats_ms(ghost_usec),
		"snapshots_completed": completed,
		"parts_dropped": parts_dropped,
		"packets_lost": _net.dropped_packets,
		"full_resets": full_resets,
		"ghosts_consistent": consistent,
		"dr_threshold_m": SnapshotCodec.DR_THRESHOLD_M,
		"dr_error_cm": _stats_int(_dr_err_cm),
		"dr_checked": _dr_checked,
		"combat_age_over_300ms_ticks": _late_ticks,
		"dr_over_threshold_fraction": snappedf(float(_dr_over) / maxi(_dr_checked, 1), 0.0001),
	}


static func _stats_ms(samples: PackedInt64Array) -> Dictionary:
	if samples.is_empty():
		return {}
	var sorted := samples.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var total: int = 0
	for v: int in sorted:
		total += v
	return {
		"p50": _ms(sorted[int(n * 0.50)]),
		"p95": _ms(sorted[mini(int(n * 0.95), n - 1)]),
		"p99": _ms(sorted[mini(int(n * 0.99), n - 1)]),
		"max": _ms(sorted[n - 1]),
		"mean": snappedf(total / 1000.0 / n, 0.001),
	}


static func _stats_int(samples: PackedInt64Array) -> Dictionary:
	if samples.is_empty():
		return {}
	var sorted := samples.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var total: int = 0
	for v: int in sorted:
		total += v
	return {
		"p50": sorted[int(n * 0.50)],
		"p95": sorted[mini(int(n * 0.95), n - 1)],
		"p99": sorted[mini(int(n * 0.99), n - 1)],
		"max": sorted[n - 1],
		"mean": snappedf(float(total) / n, 0.1),
	}


static func _ms(usec: int) -> float:
	return snappedf(usec / 1000.0, 0.001)


func _parse_args() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _save(scenario: String, json: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://load")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://load/%s_%s.json" % [scenario, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("No se pudo escribir %s" % path)
		return
	f.store_string(json)
	print("Resultado guardado en ", ProjectSettings.globalize_path(path))
