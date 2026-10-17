class_name ENetTransport
extends Transport
## Transporte por red real con ENetMultiplayerPeer (ADR-006 punto 9).
## Usa la capa de paquetes de MultiplayerPeer (put_packet / get_packet con canal y modo de
## transferencia) en lugar de RPC sobre nodos: así no hace falta un NetBridge en el SceneTree y
## MatchServer/MatchClient siguen siendo RefCounted. Los canales y modos son los de ADR-006:
## COMMANDS y EVENTS reliable, SNAPSHOTS unreliable ordenado.

const DEFAULT_PORT: int = 24790

var _peer: ENetMultiplayerPeer
var _server: bool = false
var _connected_to_server: bool = false
var _failed: bool = false


## Abre un servidor en `port`. Devuelve null (y deja el error en la consola) si no se puede.
static func create_server(port: int = DEFAULT_PORT, max_clients: int = SimConstants.MAX_PLAYERS) -> ENetTransport:
	var t := ENetTransport.new()
	t._peer = ENetMultiplayerPeer.new()
	var err: Error = t._peer.create_server(port, max_clients, CHANNEL_COUNT)
	if err != OK:
		push_error("ENetTransport: no se pudo abrir el puerto %d (%s)" % [port, error_string(err)])
		return null
	t._server = true
	t._connect_signals()
	return t


## Empieza a conectar con un servidor. La conexión se confirma con peer_connected(SERVER_PEER)
## o falla con connection_failed.
static func create_client(address: String, port: int = DEFAULT_PORT) -> ENetTransport:
	var t := ENetTransport.new()
	t._peer = ENetMultiplayerPeer.new()
	var err: Error = t._peer.create_client(address, port, CHANNEL_COUNT)
	if err != OK:
		push_error("ENetTransport: no se pudo conectar a %s:%d (%s)" % [address, port, error_string(err)])
		return null
	t._connect_signals()
	return t


func _connect_signals() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if not _server and not _connected_to_server and not _failed \
			and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_failed = true
		connection_failed.emit()
		return
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from: int = _peer.get_packet_peer()
		var data: PackedByteArray = _peer.get_packet()
		bytes_received += data.size()
		packet_received.emit(from, data)


func send(peer_id: int, channel: int, data: PackedByteArray) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(peer_id)
	# El canal 0 de MultiplayerPeer es el del sistema; los nuestros van de 1 a CHANNEL_COUNT.
	_peer.transfer_channel = channel + 1
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if Transport.is_reliable(channel) \
			else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	if _peer.put_packet(data) == OK:
		bytes_sent += data.size()


func disconnect_peer(peer_id: int) -> void:
	if _peer != null and _server:
		_peer.disconnect_peer(peer_id)


func close() -> void:
	if _peer == null:
		return
	_peer.close()
	_peer = null


func is_server() -> bool:
	return _server


func get_local_id() -> int:
	return _peer.get_unique_id() if _peer != null else 0


func _on_peer_connected(id: int) -> void:
	if not _server and id == SERVER_PEER:
		_connected_to_server = true
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
