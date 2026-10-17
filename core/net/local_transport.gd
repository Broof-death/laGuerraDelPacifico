class_name LocalTransport
extends Transport
## Transporte en el mismo proceso (ADR-006 punto 9): modo de un jugador, cliente del anfitrión y
## pruebas. Los extremos se crean con LocalNetwork.create_server() / create_client(); la latencia,
## la pérdida y el ancho de banda se configuran en la LocalNetwork.

var network: LocalNetwork
var _id: int
var _server: bool
var _peers: Dictionary[int, bool] = {}
var _closed: bool = false


func _init(p_network: LocalNetwork, p_id: int, p_server: bool) -> void:
	network = p_network
	_id = p_id
	_server = p_server


func poll() -> void:
	if _closed:
		return
	for p: Array in network._deliver(_id):
		var from: int = p[1]
		match p[2]:
			LocalNetwork._KIND_CONNECT:
				_peers[from] = true
				peer_connected.emit(from)
			LocalNetwork._KIND_DISCONNECT:
				if _peers.erase(from):
					peer_disconnected.emit(from)
			_:
				if _peers.has(from):
					var data: PackedByteArray = p[3]
					bytes_received += data.size()
					packet_received.emit(from, data)
		if _closed:
			return


func send(peer_id: int, channel: int, data: PackedByteArray) -> void:
	if _closed or not _peers.has(peer_id):
		return
	bytes_sent += data.size()
	network._send(_id, peer_id, channel, data)


func disconnect_peer(peer_id: int) -> void:
	if _peers.erase(peer_id):
		network._disconnect(_id, peer_id)
		peer_disconnected.emit(peer_id)


func close() -> void:
	if _closed:
		return
	for peer: int in _peers.keys():
		network._disconnect(_id, peer)
	_peers.clear()
	_closed = true
	network._remove_endpoint(_id)


func is_server() -> bool:
	return _server


func get_local_id() -> int:
	return _id
