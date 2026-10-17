class_name Transport
extends RefCounted
## Interfaz de transporte (ADR-006 punto 9). La implementan LocalTransport (mismo proceso: modo de
## un jugador, anfitrión local, pruebas) y ENetTransport (red real). MatchServer y MatchClient solo
## conocen esta interfaz, así el modo de un jugador usa el mismo camino que el multijugador.
##
## Un Transport es un extremo: el del servidor tiene varios pares (los clientes) y el de un cliente
## tiene un único par, el servidor (SERVER_PEER). Los paquetes son PackedByteArray ya codificados
## con el códec binario; el primer byte es el tipo de mensaje (NetProtocol.Msg).
## No usa el SceneTree: el dueño llama a poll() en cada frame y las señales se emiten desde poll().

## Canales y su modo de entrega (ADR-006 punto 5).
enum Channel {
	COMMANDS = 0,   ## reliable: comandos (y el saludo)
	SNAPSHOTS = 1,  ## unreliable ordenado: snapshots y acks (paquetes <= 1200 B)
	EVENTS = 2,     ## reliable: inicio, COMMAND_REJECTED, conexión, fin, chat
}
const CHANNEL_COUNT: int = 3
## Id del servidor visto desde un cliente (como en la API multijugador de Godot).
const SERVER_PEER: int = 1
## Tamaño máximo de un paquete unreliable (los snapshots se parten para no superarlo).
const MAX_UNRELIABLE_BYTES: int = 1200

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
## Solo cliente: no se pudo conectar con el servidor.
signal connection_failed()
signal packet_received(peer_id: int, data: PackedByteArray)

## Bytes enviados por este extremo (cabeceras del transporte no incluidas).
var bytes_sent: int = 0
var bytes_received: int = 0


static func is_reliable(channel: int) -> bool:
	return channel != Channel.SNAPSHOTS


## Procesa la red y emite las señales pendientes.
func poll() -> void:
	pass


## Envía `data` a `peer_id` por `channel`.
func send(_peer_id: int, _channel: int, _data: PackedByteArray) -> void:
	pass


## Desconecta a un par (solo servidor).
func disconnect_peer(_peer_id: int) -> void:
	pass


func close() -> void:
	pass


func is_server() -> bool:
	return false


## Id de este extremo (1 en el servidor).
func get_local_id() -> int:
	return 0
