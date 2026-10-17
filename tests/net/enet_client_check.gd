extends Node
## Comprobación de dos procesos por ENet (T-005). Se conecta a un anfitrión o servidor dedicado
## (main/match.tscn) y verifica, con su propio player_id:
##   1) recibe WELCOME y snapshots con unidades propias y ajenas;
##   2) puede mover sus unidades (avanzan al menos 10 m en los snapshots);
##   3) NO puede mover unidades de otro jugador (COMMAND_REJECTED NOT_OWNER y no van hacia el
##      destino de la orden rechazada).
## Se pueden lanzar dos a la vez contra un servidor dedicado (jugadores 1 y 2).
## Termina con código 0 si todo se cumple y 1 si no (o si pasan 20 s).
## Uso (con el servidor ya escuchando):
##   godot --headless --path . res://tests/net/enet_client_check.tscn -- --address=127.0.0.1 --port=24790

const TIMEOUT_SEC: float = 20.0
const REJECTED_OFFSET := Vector2(200.0, 0.0)

var _client: MatchClient
var _elapsed: float = 0.0
var _phase: int = 0
var _own_id: int = 0
var _own_start := Vector2.ZERO
var _target := Vector2.ZERO
var _enemy_id: int = 0
var _enemy_start := Vector2.ZERO
var _enemy_seq: int = 0
var _rejected_ok: bool = false


func _ready() -> void:
	var cfg := MatchConfig.from_args(OS.get_cmdline_user_args())
	var data: GameData = load(GameData.DEFAULT_PATH)
	if not data.build_index().is_empty():
		_finish(false, "GameData inválido")
		return
	var t := ENetTransport.create_client(cfg.address, cfg.port)
	if t == null:
		_finish(false, "no se pudo crear el cliente ENet")
		return
	t.connection_failed.connect(func() -> void: _finish(false, "no se pudo conectar"))
	_client = MatchClient.new(t, data.catalog_hash())
	_client.refused.connect(func(r: int) -> void: _finish(false, "rechazado: %d" % r))
	_client.command_rejected.connect(_on_rejected)


func _process(delta: float) -> void:
	if _client == null:
		return
	_client.update(delta)
	_elapsed += delta
	if _elapsed > TIMEOUT_SEC:
		_finish(false, "tiempo agotado en la fase %d" % _phase)
		return
	var st := _client.state
	match _phase:
		0:
			if _client.player_id == 0 or _client.receiver.latest_complete_tick < 0:
				return
			var mine := PackedInt32Array()
			for s: int in st.count:
				if st.owner[s] == _client.player_id:
					mine.append(st.ids[s])
				elif _enemy_id == 0:
					_enemy_id = st.ids[s]
			if mine.is_empty() or _enemy_id == 0:
				return
			mine.sort()
			_own_id = mine[0]
			_own_start = _pos(_own_id)
			_enemy_start = _pos(_enemy_id)
			_target = _own_start + Vector2(0.0, 40.0)
			print("CHECK jugador %d: %d entidades, %d propias" % [_client.player_id, st.count, mine.size()])
			_client.send_command(Command.make_move(0, mine, _target))
			_enemy_seq = _client.send_command(Command.make_move(0, PackedInt32Array([_enemy_id]), _enemy_start + REJECTED_OFFSET))
			_phase = 1
		1:
			var moved: float = _pos(_own_id).distance_to(_own_start)
			# El otro jugador puede mover sus unidades por su cuenta (esta misma comprobación las
			# lleva 40 m hacia +z, en formación); la orden rechazada llevaba una 200 m hacia +x.
			var rejected_target := _enemy_start + REJECTED_OFFSET
			var enemy_moved: float = REJECTED_OFFSET.length() - _pos(_enemy_id).distance_to(rejected_target)
			if enemy_moved > 15.0:
				_finish(false, "una unidad ajena se acercó %.2f m al destino rechazado" % enemy_moved)
			elif moved >= 10.0 and _rejected_ok:
				_finish(true, "propias +%.1f m, ajena %.2f m hacia el destino rechazado, rechazo NOT_OWNER recibido" % [moved, enemy_moved])


func _pos(id: int) -> Vector2:
	var s := _client.state.slot_of(id)
	if s < 0:
		return Vector2.INF
	return _client.state.predicted(s, _client.receiver.latest_tick)


func _on_rejected(seq: int, reason: int) -> void:
	if seq == _enemy_seq and reason == Command.Reject.NOT_OWNER:
		_rejected_ok = true


func _finish(ok: bool, msg: String) -> void:
	print("CHECK %s: %s" % ["OK" if ok else "FALLA", msg])
	if _client != null:
		_client.close()
		_client = null
	get_tree().quit(0 if ok else 1)
