class_name Simulation
extends RefCounted
## Estado de la partida en el servidor (ADR-006). Datos puros: no usa el SceneTree, ni nodos,
## ni Jolt, ni autoloads, así que se puede crear y avanzar sin escena (y algún día en un hilo).
##
## Orden de cada step():
##   (a) vaciar la cola de comandos (los aceptados con submit() antes de este tick),
##   (b) sistemas a 20 Hz (movimiento), rejilla espacial y sistemas a 5 Hz escalonados
##       (adquisición de objetivos, visibilidad),
##   (c) tick += 1.
##   (d) los snapshots cada 2 ticks los hace MatchServer (T-005) después de step().
## El tiempo real lo maneja TickAccumulator: step() siempre avanza exactamente TICK_DT.

## Índices de last_system_usec.
enum SystemId { COMMANDS, MOVEMENT, GRID, ACQUISITION, VISIBILITY, COUNT }
const SYSTEM_NAMES: PackedStringArray = ["commands", "movement", "grid", "acquisition", "visibility"]

var tick: int = 0
var store: EntityStore
var grid: SpatialGrid
var queue: CommandQueue
var groups: MoveGroups
var game_data: GameData
## Límites del mapa en el plano (x, z). Por defecto, el mundo de ADR-009 centrado en el origen.
var bounds: Rect2
## Azar del servidor con semilla de partida (sin garantía de determinismo entre máquinas).
var rng: RandomNumberGenerator
## Si es true, step() mide el tiempo de cada sistema en last_system_usec.
var profiling: bool = false
var last_system_usec: PackedInt64Array = PackedInt64Array()

# Estadísticas fijas copiadas de GameData por def_index (ADR-006 punto 2).
var speed_by_def: PackedFloat32Array = PackedFloat32Array()
var max_hp_by_def: PackedFloat32Array = PackedFloat32Array()
var vision_by_def: PackedFloat32Array = PackedFloat32Array()
var radius_by_def: PackedFloat32Array = PackedFloat32Array()

var _acquisition := TargetAcquisitionSystem.new()
var _visibility := VisibilitySystem.new()


## `data` debe tener el índice construido y válido (GameData.build_index() sin errores).
## `p_bounds` vacío = MapGrid.world_rect() (131 072 m centrados; la celda de la rejilla es global).
func _init(data: GameData, p_seed: int = 0, p_bounds: Rect2 = Rect2()) -> void:
	game_data = data
	bounds = p_bounds if p_bounds.has_area() else MapGrid.world_rect()
	store = EntityStore.new()
	grid = SpatialGrid.new(bounds.size.x, bounds.size.y, bounds.position.x, bounds.position.y)
	queue = CommandQueue.new()
	groups = MoveGroups.new()
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	last_system_usec.resize(SystemId.COUNT)
	if data == null or not data.is_built():
		push_error("Simulation: GameData nulo o sin validar; llama a build_index() y revisa los errores.")
		return
	_build_stat_tables()


## Crea una entidad (solo servidor: preparación de la partida, producción...). Devuelve el id,
## o 0 si def_index no existe.
func spawn_entity(def_index: int, owner: int, x: float, z: float, heading: float = 0.0) -> int:
	if def_index < 0 or def_index >= max_hp_by_def.size():
		push_error("Simulation: def_index %d inexistente" % def_index)
		return SimConstants.NO_ENTITY
	return store.spawn(def_index, owner, x, z, heading, max_hp_by_def[def_index])


## Borra una entidad (y la saca de su grupo de movimiento). No llamar desde dentro de un sistema.
func remove_entity(entity_id: int) -> bool:
	var s: int = store.slot_of(entity_id)
	if s < 0:
		return false
	groups.leave(store.move_group[s])
	return store.remove(entity_id)


## Recibe un comando de player_id (lo deduce el servidor del peer). Valida y lo encola para el
## próximo step(). Devuelve Command.Reject.OK o el motivo del rechazo.
## `now_msec`: reloj real para el límite de 30 comandos/s (MatchServer lo pasa para que la ventana
## se renueve también en pausa). Si es negativo se usa el reloj de la simulación (tick * 50 ms).
func submit_command(player_id: int, cmd: Command, now_msec: int = -1) -> Command.Reject:
	var t: int = now_msec if now_msec >= 0 else tick * 1000 / SimConstants.TICK_RATE
	return queue.submit(player_id, cmd, store, bounds, t)


## Avanza un tick fijo (TICK_DT). Datos puros.
func step() -> void:
	var dt: float = SimConstants.TICK_DT
	var t0: int = Time.get_ticks_usec() if profiling else 0

	# (a) Comandos aceptados antes de este tick.
	var pending: Array = queue.take_pending()
	var players: PackedInt32Array = pending[0]
	var commands: Array[Command] = pending[1]
	for i: int in commands.size():
		_apply_command(players[i], commands[i])
		queue.record(tick, players[i], commands[i])
	var t1: int = _lap(SystemId.COMMANDS, t0)

	# (b) 20 Hz.
	MovementSystem.run(store, groups, speed_by_def, dt)
	var t2: int = _lap(SystemId.MOVEMENT, t1)
	grid.rebuild(store)
	var t3: int = _lap(SystemId.GRID, t2)

	# 5 Hz escalonado: cada tick procesa una fase de SLOW_PHASES.
	var phase: int = tick % SimConstants.SLOW_PHASES
	_acquisition.run(store, grid, vision_by_def, phase, SimConstants.SLOW_PHASES)
	var t4: int = _lap(SystemId.ACQUISITION, t3)
	_visibility.run(store, grid, phase, SimConstants.SLOW_PHASES)
	_lap(SystemId.VISIBILITY, t4)

	# (c)
	tick += 1


func _lap(system: SystemId, since: int) -> int:
	if not profiling:
		return 0
	var now: int = Time.get_ticks_usec()
	last_system_usec[system] = now - since
	return now


func _apply_command(_player_id: int, cmd: Command) -> void:
	match cmd.type:
		Command.Type.MOVE, Command.Type.ATTACK_MOVE:
			# ATTACK_MOVE se mueve igual que MOVE hasta que exista el combate.
			_apply_move(cmd)
		Command.Type.STOP:
			_apply_stop(cmd)
		Command.Type.ATTACK:
			# PROVISIONAL (T-007), hasta que exista el combate: ir a donde está el objetivo ahora.
			var t: int = store.slot_of(cmd.target_id)
			if t >= 0:
				var move := Command.make_move(cmd.seq, cmd.entity_ids, Vector2(store.pos_x[t], store.pos_z[t]))
				_apply_move(move)


func _apply_move(cmd: Command) -> void:
	# Las entidades que murieron entre la validación y este tick se ignoran.
	var slots := PackedInt32Array()
	for entity_id: int in cmd.entity_ids:
		var s: int = store.slot_of(entity_id)
		if s >= 0 and speed_by_def[store.def_index[s]] > 0.0:
			slots.append(s)
	if slots.is_empty():
		return
	var tx: float = cmd.target_pos.x
	var tz: float = cmd.target_pos.y
	for s: int in slots:
		_leave_group(s)
	if slots.size() < SimConstants.MOVE_GROUP_MIN_UNITS:
		for s: int in slots:
			_order_move(s, tx, tz, 0)
		return

	# Grupo de movimiento: una ruta (el destino) y una formación alrededor de él.
	var cx: float = 0.0
	var cz: float = 0.0
	var slowest: float = INF
	var widest: float = 0.0
	for s: int in slots:
		cx += store.pos_x[s]
		cz += store.pos_z[s]
		var d: int = store.def_index[s]
		slowest = minf(slowest, speed_by_def[d])
		widest = maxf(widest, radius_by_def[d])
	cx /= slots.size()
	cz /= slots.size()
	var forward := Vector2(tx - cx, tz - cz)
	var offsets: PackedVector2Array = FormationLayout.offsets(slots.size(), widest * 2.5, forward, cmd.formation)
	var gid: int = groups.create(slots.size(), slowest, tx, tz)
	for i: int in slots.size():
		var dest := Vector2(tx, tz) + offsets[i]
		dest.x = clampf(dest.x, bounds.position.x, bounds.end.x)
		dest.y = clampf(dest.y, bounds.position.y, bounds.end.y)
		_order_move(slots[i], dest.x, dest.y, gid)


func _apply_stop(cmd: Command) -> void:
	for entity_id: int in cmd.entity_ids:
		var s: int = store.slot_of(entity_id)
		if s < 0:
			continue
		_leave_group(s)
		store.action[s] = SimConstants.Action.IDLE
		store.dest_x[s] = store.pos_x[s]
		store.dest_z[s] = store.pos_z[s]
		store.vel_x[s] = 0.0
		store.vel_z[s] = 0.0


func _order_move(s: int, x: float, z: float, gid: int) -> void:
	store.dest_x[s] = x
	store.dest_z[s] = z
	store.move_group[s] = gid
	store.action[s] = SimConstants.Action.MOVE


func _leave_group(s: int) -> void:
	var g: int = store.move_group[s]
	if g != 0:
		groups.leave(g)
		store.move_group[s] = 0


func _build_stat_tables() -> void:
	var n: int = game_data.def_count()
	speed_by_def.resize(n)
	max_hp_by_def.resize(n)
	vision_by_def.resize(n)
	radius_by_def.resize(n)
	for i: int in n:
		var def: EntityDef = game_data.get_def(i)
		max_hp_by_def[i] = def.max_hp
		vision_by_def[i] = def.vision_range
		if def is UnitDef:
			speed_by_def[i] = (def as UnitDef).speed
			radius_by_def[i] = (def as UnitDef).radius
		else:
			speed_by_def[i] = 0.0
			radius_by_def[i] = 0.0
