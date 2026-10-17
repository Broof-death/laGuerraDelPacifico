extends Node
## Escena de arranque de una partida (ADR-006 punto 9). Lee Session.config y arma:
##   SINGLE     MatchServer + MatchClient unidos por LocalTransport (mismo camino que en red)
##   HOST       MatchServer con ENetTransport (remotos) y LocalTransport (su propio cliente)
##   JOIN       MatchClient con ENetTransport
##   DEDICATED  MatchServer con ENetTransport, sin cliente (--server)
## Todavía no dibuja unidades (las vistas son de T-017): muestra un texto de estado.

var config: MatchConfig
var server: MatchServer
var client: MatchClient
var _elapsed: float = 0.0
var _status: Label
var _status_timer: float = 0.0


func _ready() -> void:
	config = Session.config
	var data: GameData = load(GameData.DEFAULT_PATH)
	var errors := data.build_index()
	if not errors.is_empty():
		push_error("GameData inválido, la partida no arranca: %s" % [errors])
		get_tree().quit(2)
		return
	if config.is_server():
		_start_server(data)
	if config.has_client():
		_start_client(data)
	if DisplayServer.get_name() != "headless":
		_status = Label.new()
		_status.position = Vector2(16, 16)
		add_child(_status)
	print("Partida: modo %s" % MatchConfig.Mode.keys()[config.mode])


func _start_server(data: GameData) -> void:
	var sim := Simulation.new(data, config.match_seed)
	server = MatchServer.new(sim)
	server.max_players = config.max_players
	server.allow_time_scale = config.mode == MatchConfig.Mode.SINGLE
	server.spawn_test_armies(config.players, config.units_per_player)
	server.player_joined.connect(func(pid: int) -> void: print("Servidor: entra el jugador %d" % pid))
	server.player_left.connect(func(pid: int) -> void: print("Servidor: sale el jugador %d" % pid))
	if config.mode == MatchConfig.Mode.HOST or config.mode == MatchConfig.Mode.DEDICATED:
		var enet := ENetTransport.create_server(config.port, config.max_players)
		if enet == null:
			get_tree().quit(3)
			return
		server.add_transport(enet)
		print("Servidor escuchando en el puerto %d" % config.port)


func _start_client(data: GameData) -> void:
	var t: Transport
	if config.mode == MatchConfig.Mode.JOIN:
		t = ENetTransport.create_client(config.address, config.port)
		if t == null:
			get_tree().quit(3)
			return
		t.connection_failed.connect(func() -> void:
			push_error("No se pudo conectar a %s:%d" % [config.address, config.port])
			get_tree().quit(4))
	else:
		# Un jugador y anfitrión: el cliente propio va por LocalTransport, sin latencia.
		var net := LocalNetwork.new()
		var server_end := net.create_server()
		server.add_transport(server_end)
		t = net.create_client()
	client = MatchClient.new(t, data.catalog_hash())
	client.welcomed.connect(func(pid: int) -> void: print("Cliente: soy el jugador %d" % pid))
	client.refused.connect(func(reason: int) -> void:
		push_error("El servidor rechazó la conexión: %s" % NetProtocol.Refuse.keys()[reason])
		get_tree().quit(5))
	client.command_rejected.connect(func(seq: int, reason: int) -> void:
		print("Comando %d rechazado: %s" % [seq, Command.Reject.keys()[reason]]))


func _process(delta: float) -> void:
	if server != null:
		server.update(delta)
	if client != null:
		client.update(delta)
	_elapsed += delta
	if config.quit_after_seconds > 0.0 and _elapsed >= config.quit_after_seconds:
		get_tree().quit(0)
	if _status != null:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status_timer = 0.25
			_status.text = _status_text()


func _exit_tree() -> void:
	if client != null:
		client.close()
	if server != null:
		server.close()


func _status_text() -> String:
	var lines := PackedStringArray()
	lines.append("Modo: %s" % MatchConfig.Mode.keys()[config.mode])
	if server != null:
		lines.append("Servidor: tick %d, %d entidades, jugadores %s" % [server.sim.tick, server.sim.store.count, server.connected_players()])
	if client != null:
		lines.append("Cliente: jugador %d, %d entidades conocidas, último snapshot %d" % [client.player_id, client.state.count, client.receiver.latest_complete_tick])
	return "\n".join(lines)
