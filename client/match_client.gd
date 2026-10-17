class_name MatchClient
extends RefCounted
## Cliente de una partida (ADR-006 puntos 6 y 9). Habla con el servidor solo por un Transport
## (LocalTransport en un jugador y en el anfitrión, ENetTransport al unirse), así que el modo de
## un jugador no tiene código aparte. No usa nodos: el dueño (main/match.gd) llama a update().
## - Saluda con HELLO (versión del protocolo y huella de GameData) y espera WELCOME o REFUSED.
## - Envía comandos (CommandCodec) con seq propio; COMMAND_REJECTED llega como señal.
## - Recibe snapshots (SnapshotReceiver), confirma con ack los completos y mantiene ClientState
##   interpolado con INTERPOLATION_DELAY_TICKS de retraso (200 ms).

signal welcomed(player_id: int)
signal refused(reason: int)
signal command_rejected(seq: int, reason: int)
signal disconnected()

const INTERPOLATION_DELAY_TICKS: float = 4.0
## Si el reloj de dibujo se separa más que esto del objetivo, salta en lugar de ajustarse.
const RESYNC_TICKS: float = 10.0

var transport: Transport
var receiver := SnapshotReceiver.new()
var state := ClientState.new()
## Jugador asignado por el servidor (0 hasta WELCOME).
var player_id: int = 0
var max_players: int = 0
## Si es false, update() no interpola (clientes fantasma de la prueba de carga).
var interpolate_enabled: bool = true
## Instante de dibujo en ticks del servidor (con decimales).
var render_tick: float = 0.0
var snapshot_bytes_received: int = 0

var _catalog_hash: int
var _next_seq: int = 1
var _connected: bool = false


func _init(p_transport: Transport, catalog_hash: int) -> void:
	transport = p_transport
	_catalog_hash = catalog_hash
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.packet_received.connect(_on_packet)


func is_in_match() -> bool:
	return player_id != 0


## Envía un comando. Le asigna el próximo seq y lo devuelve (0 si no se pudo enviar).
func send_command(cmd: Command) -> int:
	if player_id == 0:
		return 0
	cmd.seq = _next_seq
	var data := CommandCodec.encode(cmd)
	if data.is_empty():
		return 0
	_next_seq += 1
	transport.send(Transport.SERVER_PEER, Transport.Channel.COMMANDS, data)
	return cmd.seq


## Último comando propio que el servidor confirmó haber recibido (para limpiar la respuesta
## cosmética de las órdenes).
func last_confirmed_seq() -> int:
	return receiver.last_seq


## Procesa la red y avanza el reloj de dibujo `delta` segundos.
func update(delta: float) -> void:
	transport.poll()
	if receiver.latest_tick < 0:
		return
	var target: float = receiver.latest_tick - INTERPOLATION_DELAY_TICKS
	render_tick += delta * SimConstants.TICK_RATE
	if absf(render_tick - target) > RESYNC_TICKS:
		render_tick = target
	else:
		render_tick += (target - render_tick) * 0.1
	# Sin snapshots nuevos (pausa, corte) no se dibuja más allá del último recibido.
	render_tick = minf(render_tick, receiver.latest_tick)
	if interpolate_enabled:
		state.interpolate(render_tick)


func close() -> void:
	transport.close()


func _on_peer_connected(peer_id: int) -> void:
	if peer_id != Transport.SERVER_PEER:
		return
	_connected = true
	transport.send(Transport.SERVER_PEER, Transport.Channel.COMMANDS, NetProtocol.encode_hello(_catalog_hash))


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == Transport.SERVER_PEER:
		_connected = false
		disconnected.emit()


func _on_packet(_peer_id: int, data: PackedByteArray) -> void:
	match NetProtocol.msg_type(data):
		NetProtocol.Msg.SNAPSHOT:
			if player_id == 0:
				return
			snapshot_bytes_received += data.size()
			var part := receiver.receive(data)
			if part != null:
				state.apply_part(part)
			if receiver.completed_tick >= 0:
				transport.send(Transport.SERVER_PEER, Transport.Channel.SNAPSHOTS,
						NetProtocol.encode_ack(receiver.completed_tick))
		NetProtocol.Msg.WELCOME:
			var w := NetProtocol.decode_welcome(data)
			if w.is_empty():
				return
			player_id = w[0]
			max_players = w[2]
			render_tick = w[1]
			welcomed.emit(player_id)
		NetProtocol.Msg.REFUSED:
			refused.emit(NetProtocol.decode_refused(data))
		NetProtocol.Msg.COMMAND_REJECTED:
			var r := NetProtocol.decode_rejected(data)
			if not r.is_empty():
				command_rejected.emit(r[0], r[1])
