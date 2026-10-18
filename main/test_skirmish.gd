class_name TestSkirmish
extends RefCounted
## PROVISIONAL (T-017), hasta el arranque real de partida y la IA (T-038 y siguientes): completa
## los ejércitos de prueba de MatchServer.spawn_test_armies con un poco de cada tipo de prueba de
## data/ (caballería, artillería, un edificio y buques) y mueve a los jugadores sin conexión con
## un bot mínimo. El bot usa la misma cola de comandos que un jugador (Simulation.submit_command).
## Solo se usa en el modo de un jugador.

const BOT_FIRST_ORDER: float = 2.0
const BOT_INTERVAL: float = 7.0
## Costa del mapa provisional cerca del origen (core/map/test_map_builder.gd, el mismo que dibuja
## client/world/logic_map_view.gd): mar para x > COAST_X entre z = -500 y z = 500.
const COAST_X: float = 250.0

var server: MatchServer
var rng := RandomNumberGenerator.new()
var _timer: float = BOT_FIRST_ORDER
var _defs: Dictionary[StringName, int] = {}


func _init(p_server: MatchServer, seed_value: int = 1) -> void:
	server = p_server
	rng.seed = seed_value
	var gd := server.sim.game_data
	for id: StringName in [&"caballeria_prueba", &"artilleria_prueba", &"buque_prueba", &"edificio_prueba"]:
		_defs[id] = gd.index_of(id)


## Agrega a cada ejército de spawn_test_armies (mismo círculo de `radius` m) caballería,
## artillería, un edificio detrás y `ships` buques en el mar.
func spawn_extras(players: int, radius: float = 60.0, ships: int = 3) -> void:
	var sim := server.sim
	var center: Vector2 = sim.bounds.get_center()
	for p: int in players:
		var angle: float = TAU * p / maxi(players, 1)
		var dir := Vector2(cos(angle), sin(angle))
		var side := Vector2(-dir.y, dir.x)
		var base: Vector2 = center + dir * radius
		var facing: float = atan2(-dir.x, -dir.y)
		var owner: int = p + 1
		if _defs[&"caballeria_prueba"] >= 0:
			for i: int in 12:
				var q := base + side * (26.0 + (i / 6) * 4.0) + dir * ((i % 6) - 2.5) * 4.0
				sim.spawn_entity(_defs[&"caballeria_prueba"], owner, q.x, q.y, facing)
		if _defs[&"artilleria_prueba"] >= 0:
			for i: int in 4:
				var q := base - side * 26.0 + dir * (i - 1.5) * 6.0
				sim.spawn_entity(_defs[&"artilleria_prueba"], owner, q.x, q.y, facing)
		if _defs[&"edificio_prueba"] >= 0:
			var q := base + dir * 45.0
			sim.spawn_entity(_defs[&"edificio_prueba"], owner, q.x, q.y, facing)
		if _defs[&"buque_prueba"] >= 0:
			for i: int in ships:
				var q := Vector2(COAST_X + 90.0 + p * 140.0, center.y + (i - (ships - 1) * 0.5) * 90.0)
				sim.spawn_entity(_defs[&"buque_prueba"], owner, q.x, q.y, PI)


## Bot: cada BOT_INTERVAL s, cada jugador sin conexión manda sus tropas de tierra a un punto al
## azar en tierra y sus buques a un punto al azar en el mar.
func update(delta: float, players: int) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = BOT_INTERVAL
	var connected := server.connected_players()
	for owner: int in range(1, players + 1):
		if connected.has(owner):
			continue
		_order_bot(owner)


func _order_bot(owner: int) -> void:
	var sim := server.sim
	var st := sim.store
	var land := PackedInt32Array()
	var sea := PackedInt32Array()
	var ship_def: int = _defs[&"buque_prueba"]
	for s: int in st.count:
		if st.owner[s] != owner:
			continue
		var d: int = st.def_index[s]
		if sim.speed_by_def[d] <= 0.0:
			continue  # edificios
		if d == ship_def:
			sea.append(st.id[s])
		else:
			land.append(st.id[s])
	var c: Vector2 = sim.bounds.get_center()
	if not land.is_empty():
		var target := Vector2(rng.randf_range(c.x - 220.0, minf(c.x + 160.0, COAST_X - 40.0)), rng.randf_range(c.y - 200.0, c.y + 200.0))
		sim.submit_command(owner, Command.make_move(0, land.slice(0, SimConstants.MAX_IDS_PER_COMMAND), target))
	if not sea.is_empty():
		var target := Vector2(rng.randf_range(COAST_X + 80.0, COAST_X + 700.0), rng.randf_range(c.y - 400.0, c.y + 400.0))
		sim.submit_command(owner, Command.make_move(0, sea, target))
