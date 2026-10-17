extends Node
## Prueba de carga headless de la simulación (ADR-006 punto 10).
##
## Uso (desde la raíz del proyecto):
##   godot --headless --path . res://tests/load/load_test.tscn -- --scenario=S1
##   godot --headless --path . res://tests/load/load_test.tscn -- --players=6 --units=500 --seconds=120 --seed=1
##
## Cada jugador empieza con N unidades en bloque sobre un círculo alrededor del centro del mapa.
## Los bots deciden a 2 Hz por la misma cola de comandos que un jugador: ATTACK_MOVE de todo el
## ejército al lado opuesto del círculo (los ejércitos se cruzan en el centro, una batalla grande)
## y, en cada decisión, una orden MOVE a un subconjunto de 16 unidades (micro).
## Mide el tiempo de cada step() completo y de cada sistema, con los ticks corriendo tan rápido
## como se pueda (no en tiempo real). Salida JSON en la consola (línea "LOAD_RESULT {...}") y en
## user://load/. Código de salida 0 si cumple los umbrales del escenario, 1 si no.
##
## Pendiente de T-005: bytes por snapshot, KB/s por jugador, antigüedad de las entidades y el
## cliente fantasma con pérdida simulada (todavía no existe el SnapshotCodec).

const SCENARIOS: Dictionary = {
	"S1": {"players": 2, "units": 500, "p95_ms": 6.0, "p99_ms": -1.0},
	"S2": {"players": 6, "units": 500, "p95_ms": 20.0, "p99_ms": 35.0},
	"S3": {"players": 6, "units": 750, "p95_ms": 35.0, "p99_ms": -1.0},
}
const BOT_DECISION_TICKS: int = SimConstants.TICK_RATE / 2  # 2 Hz
const START_RADIUS: float = 200.0
const MICRO_UNITS: int = 16
const WARMUP_TICKS: int = 20

var _sim: Simulation
var _rng := RandomNumberGenerator.new()
var _armies: Array[PackedInt32Array] = []
var _bot_side: PackedInt32Array = PackedInt32Array()  # 0 = va hacia el lado opuesto, 1 = vuelve
var _seq: int = 0
var _commands_sent: int = 0
var _commands_rejected: int = 0


func _ready() -> void:
	var args := _parse_args()
	var scenario: String = args.get("scenario", "")
	var preset: Dictionary = SCENARIOS.get(scenario, {})
	var players: int = int(args.get("players", preset.get("players", 2)))
	var units: int = int(args.get("units", preset.get("units", 500)))
	var seconds: float = float(args.get("seconds", 120.0))
	var seed_value: int = int(args.get("seed", 1))
	var deaths_per_sec: int = int(args.get("deaths_per_sec", 0))
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

	var ticks: int = int(seconds * SimConstants.TICK_RATE)
	var tick_usec := PackedInt64Array()
	var sys_usec: Array[PackedInt64Array] = []
	for i: int in Simulation.SystemId.COUNT:
		sys_usec.append(PackedInt64Array())
	var max_targets: int = 0

	var wall_start := Time.get_ticks_usec()
	for t: int in ticks:
		if t % BOT_DECISION_TICKS == 0:
			_bots_decide(players)
		_churn(players, deaths_per_sec, t)
		var t0 := Time.get_ticks_usec()
		_sim.step()
		var dt := Time.get_ticks_usec() - t0
		if t >= mini(WARMUP_TICKS, ticks / 10):
			tick_usec.append(dt)
			for i: int in Simulation.SystemId.COUNT:
				sys_usec[i].append(_sim.last_system_usec[i])
		if t % 100 == 0:
			max_targets = maxi(max_targets, _count_with_target())
	var wall_s: float = (Time.get_ticks_usec() - wall_start) / 1_000_000.0

	var result := {
		"scenario": scenario,
		"players": players,
		"units_per_player": units,
		"entities": _sim.store.count,
		"seconds_simulated": seconds,
		"ticks_measured": tick_usec.size(),
		"seed": seed_value,
		"deaths_per_sec": deaths_per_sec,
		"wall_seconds": snappedf(wall_s, 0.01),
		"tick_ms": _stats_ms(tick_usec),
		"systems_ms": {},
		"commands_sent": _commands_sent,
		"commands_rejected": _commands_rejected,
		"max_entities_with_target": max_targets,
		"static_memory_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"snapshot": "no medido: SnapshotCodec y transporte son de T-005",
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
		result["threshold"] = {"p95_ms": threshold["p95_ms"], "p99_ms": threshold["p99_ms"]}
		passed = result["tick_ms"].get("p95", INF) <= threshold["p95_ms"]
		if threshold["p99_ms"] > 0.0:
			passed = passed and result["tick_ms"].get("p99", INF) <= threshold["p99_ms"]
		result["pass"] = passed

	var json := JSON.stringify(result, "  ", false)
	print("LOAD_RESULT ", JSON.stringify(result, "", false))
	_save(scenario, json)
	_sim = null
	get_tree().quit(0 if passed else 1)


func _spawn_armies(players: int, units: int) -> void:
	var center := _sim.bounds.get_center()
	var cols: int = ceili(sqrt(float(units)))
	var spacing: float = 2.5
	for p: int in players:
		var angle: float = TAU * p / players
		var base := center + Vector2(cos(angle), sin(angle)) * START_RADIUS
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
		var home := center + Vector2(cos(angle), sin(angle)) * START_RADIUS
		var away := center - Vector2(cos(angle), sin(angle)) * START_RADIUS
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
		var home := center + Vector2(cos(angle), sin(angle)) * START_RADIUS
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


func _submit(player_id: int, cmd: Command) -> void:
	_commands_sent += 1
	if _sim.submit_command(player_id, cmd) != Command.Reject.OK:
		_commands_rejected += 1


func _next_seq() -> int:
	_seq += 1
	return _seq


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
