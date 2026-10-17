class_name LocalNetwork
extends RefCounted
## "Red" en memoria que une extremos LocalTransport del mismo proceso (ADR-006 punto 9).
## Copia cada paquete (los bytes ya vienen serializados por el códec binario) y puede simular:
## - latencia fija en un sentido (latency_msec),
## - pérdida de paquetes unreliable (loss, 0..1; los reliable nunca se pierden),
## - límite de ancho de banda por enlace y sentido (bandwidth_bytes_per_sec, 0 = sin límite): los
##   paquetes esperan su turno; un paquete unreliable que esperaría más de max_backlog_msec se
##   descarta, como en un enlace saturado.
## Reloj: real (Time.get_ticks_msec) o manual (manual_clock = true y advance()), para pruebas
## deterministas y para la prueba de carga.

const _KIND_DATA: int = 0
const _KIND_CONNECT: int = 1
const _KIND_DISCONNECT: int = 2

var latency_msec: int = 0
var loss: float = 0.0
var bandwidth_bytes_per_sec: int = 0
var max_backlog_msec: int = 250
var manual_clock: bool = false
var rng := RandomNumberGenerator.new()
## Paquetes unreliable descartados (pérdida simulada o enlace saturado).
var dropped_packets: int = 0

var _now: int = 0
var _endpoints: Dictionary[int, LocalTransport] = {}
var _next_client_id: int = 2
# Paquetes en vuelo por destino: arrays paralelos (tiempo de entrega, origen, tipo, datos).
var _in_flight: Dictionary[int, Array] = {}
# Instante en que queda libre cada enlace (from << 32 | to), para el límite de ancho de banda.
var _link_free_at: Dictionary[int, int] = {}


func _init(p_seed: int = 0) -> void:
	rng.seed = p_seed


func now_msec() -> int:
	return _now if manual_clock else Time.get_ticks_msec()


## Avanza el reloj manual.
func advance(msec: int) -> void:
	_now += msec


## Crea el extremo del servidor (id 1).
func create_server() -> LocalTransport:
	var t := LocalTransport.new(self, Transport.SERVER_PEER, true)
	_endpoints[Transport.SERVER_PEER] = t
	_in_flight[Transport.SERVER_PEER] = []
	return t


## Crea un cliente y lo conecta al servidor (la conexión llega con la latencia simulada).
func create_client() -> LocalTransport:
	var id: int = _next_client_id
	_next_client_id += 1
	var t := LocalTransport.new(self, id, false)
	_endpoints[id] = t
	_in_flight[id] = []
	_enqueue(id, Transport.SERVER_PEER, _KIND_CONNECT, Transport.Channel.EVENTS, PackedByteArray())
	_enqueue(Transport.SERVER_PEER, id, _KIND_CONNECT, Transport.Channel.EVENTS, PackedByteArray())
	return t


func _send(from: int, to: int, channel: int, data: PackedByteArray) -> void:
	if not _endpoints.has(to):
		return
	if not Transport.is_reliable(channel) and loss > 0.0 and rng.randf() < loss:
		dropped_packets += 1
		return
	_enqueue(from, to, _KIND_DATA, channel, data.duplicate())


func _disconnect(a: int, b: int) -> void:
	if _endpoints.has(b):
		_enqueue(a, b, _KIND_DISCONNECT, Transport.Channel.EVENTS, PackedByteArray())
	if _endpoints.has(a):
		_enqueue(b, a, _KIND_DISCONNECT, Transport.Channel.EVENTS, PackedByteArray())


func _remove_endpoint(id: int) -> void:
	_endpoints.erase(id)
	_in_flight.erase(id)


func _enqueue(from: int, to: int, kind: int, channel: int, data: PackedByteArray) -> void:
	var now: int = now_msec()
	var at: int = now
	if bandwidth_bytes_per_sec > 0 and kind == _KIND_DATA:
		var link: int = (from << 32) | to
		var free_at: int = maxi(_link_free_at.get(link, now), now)
		if not Transport.is_reliable(channel) and free_at - now > max_backlog_msec:
			dropped_packets += 1
			return
		free_at += (data.size() * 1000) / bandwidth_bytes_per_sec
		_link_free_at[link] = free_at
		at = free_at
	at += latency_msec
	var q: Array = _in_flight.get(to, [])
	q.append([at, from, kind, data])


## Entrega al extremo `to` los paquetes que ya llegaron, en orden de envío.
func _deliver(to: int) -> Array:
	var q: Array = _in_flight.get(to, [])
	if q.is_empty():
		return []
	var now: int = now_msec()
	var due: Array = []
	var waiting: Array = []
	# Dentro de un enlace los tiempos de entrega son crecientes (latencia fija y el ancho de
	# banda serializa), así que se conserva el orden de envío de cada par.
	for p: Array in q:
		if p[0] <= now:
			due.append(p)
		else:
			waiting.append(p)
	if not due.is_empty():
		_in_flight[to] = waiting
	return due
