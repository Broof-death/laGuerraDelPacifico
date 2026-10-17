class_name MatchServer
extends RefCounted
## Servidor con autoridad de una partida (ADR-001, ADR-006). RefCounted, sin nodos ni autoloads:
## el dueño (main/match.gd, la prueba de carga o una prueba unitaria) llama a update() en cada frame.
## - Avanza la Simulation con un TickAccumulator propio (20 Hz fijos, máx. 3 ticks por frame).
## - Atiende uno o más Transport (en el anfitrión: ENet para los remotos y LocalTransport para su
##   propio cliente). Cada conexión saluda con HELLO; si la versión y la huella de GameData
##   coinciden y hay lugar, recibe un player_id (1..max_players) y WELCOME.
## - Comandos: el player_id sale de la conexión, nunca del paquete. Límite de 8 KB/s por conexión
##   sobre TODO lo que manda el cliente (HELLO, COMMAND y ACK; los acks son ~50 B/s) y de 30
##   comandos/s (CommandQueue), ambos con ventana de tiempo real. Pasado el límite, los COMMAND se
##   rechazan con RATE_LIMITED y los HELLO y ACK se descartan. Los rechazos vuelven como
##   COMMAND_REJECTED(seq, motivo) por el canal de eventos. last_seq (en la cabecera de los
##   snapshots) es el seq más alto que llegó, aunque el comando se haya rechazado.
## - Snapshots a 10 Hz fijos: en los ticks pares se cuantiza el mundo una vez (SnapshotWorld) y se
##   arma el snapshot de la mitad de los clientes; en el tick siguiente, el de la otra mitad, con
##   la misma foto (ADR-006: los jugadores se reparten entre los 2 ticks del ciclo).
## - Pausa y velocidad x2 solo si allow_time_scale (modo de un jugador).

signal player_joined(player_id: int)
signal player_left(player_id: int)

class Conn:
	var transport: Transport
	var peer_id: int
	var player_id: int = 0
	var sender: SnapshotSender
	var last_seq: int = 0
	var cmd_window_start: int = -SimConstants.RATE_LIMIT_WINDOW_MSEC
	var cmd_bytes: int = 0
	var bytes_sent: int = 0


var sim: Simulation
var accumulator := TickAccumulator.new()
var max_players: int = SimConstants.MAX_PLAYERS
## Solo en el modo de un jugador: permite pausa y velocidad x2.
var allow_time_scale: bool = false
## Reloj manual (milisegundos) para pruebas; -1 = Time.get_ticks_msec().
var manual_msec: int = -1
## Si es true, se mide el armado de snapshots en last_snapshot_usec.
var profiling: bool = false
var last_snapshot_usec: int = 0
var world := SnapshotWorld.new()

var _catalog_hash: int
var _transports: Array[Transport] = []
var _conns: Array[Conn] = []


func _init(p_sim: Simulation) -> void:
	sim = p_sim
	_catalog_hash = sim.game_data.catalog_hash() if sim.game_data != null and sim.game_data.is_built() else 0


func add_transport(t: Transport) -> void:
	_transports.append(t)
	t.peer_connected.connect(_on_peer_connected.bind(t))
	t.peer_disconnected.connect(_on_peer_disconnected.bind(t))
	t.packet_received.connect(_on_packet.bind(t))


func now_msec() -> int:
	return manual_msec if manual_msec >= 0 else Time.get_ticks_msec()


## Procesa la red y ejecuta los ticks que tocan según el tiempo real. Devuelve los ticks ejecutados.
func update(frame_delta: float) -> int:
	poll()
	var n: int = accumulator.advance(frame_delta)
	for i: int in n:
		tick_once()
	return n


## Recibe lo pendiente de todos los transportes.
func poll() -> void:
	for t: Transport in _transports:
		t.poll()
	_flush_rejections()


## Un tick completo: simulación y, si toca, snapshots. La prueba de carga lo llama directamente.
func tick_once() -> void:
	sim.step()
	_flush_rejections()
	_send_snapshots()


func set_paused(paused: bool) -> void:
	if allow_time_scale:
		accumulator.time_scale = 0.0 if paused else 1.0


func set_time_scale(scale: float) -> void:
	if allow_time_scale:
		accumulator.time_scale = clampf(scale, 0.0, 2.0)


func connected_players() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: Conn in _conns:
		if c.player_id != 0:
			out.append(c.player_id)
	return out


func get_conn(player_id: int) -> Conn:
	for c: Conn in _conns:
		if c.player_id == player_id:
			return c
	return null


## PROVISIONAL hasta el arranque real de partida (facciones y unidades iniciales de GameData):
## coloca `units` unidades del def_index 0 por jugador, en bloques sobre un círculo de `radius` m
## alrededor del centro del mapa, mirando al centro.
func spawn_test_armies(players: int, units: int, radius: float = 60.0) -> void:
	if sim.max_hp_by_def.is_empty():
		return
	var center: Vector2 = sim.bounds.get_center()
	var cols: int = maxi(1, ceili(sqrt(float(units))))
	for p: int in players:
		var angle: float = TAU * p / maxi(players, 1)
		var base: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		for i: int in units:
			var off := Vector2((i % cols - cols * 0.5) * 3.0, (i / cols - cols * 0.5) * 3.0)
			sim.spawn_entity(0, p + 1, base.x + off.x, base.y + off.y, atan2(-cos(angle), -sin(angle)))


func close() -> void:
	for t: Transport in _transports:
		t.close()
	_transports.clear()
	_conns.clear()


# --- Snapshots ---------------------------------------------------------------------------------

func _send_snapshots() -> void:
	var phase: int = sim.tick % SimConstants.SNAPSHOT_EVERY_TICKS
	var t0: int = Time.get_ticks_usec() if profiling else 0
	if phase == 0:
		world.capture(sim)
	if world.tick < 0:
		return
	for c: Conn in _conns:
		if c.player_id == 0 or c.player_id % SimConstants.SNAPSHOT_EVERY_TICKS != phase:
			continue
		var packets := c.sender.build(world, c.last_seq)
		for p: PackedByteArray in packets:
			c.transport.send(c.peer_id, Transport.Channel.SNAPSHOTS, p)
			c.bytes_sent += p.size()
	if profiling:
		last_snapshot_usec = Time.get_ticks_usec() - t0


# --- Conexiones y mensajes ---------------------------------------------------------------------

func _find(t: Transport, peer_id: int) -> Conn:
	for c: Conn in _conns:
		if c.transport == t and c.peer_id == peer_id:
			return c
	return null


func _on_peer_connected(peer_id: int, t: Transport) -> void:
	var c := Conn.new()
	c.transport = t
	c.peer_id = peer_id
	_conns.append(c)


func _on_peer_disconnected(peer_id: int, t: Transport) -> void:
	var c := _find(t, peer_id)
	if c == null:
		return
	_conns.erase(c)
	if c.player_id != 0:
		player_left.emit(c.player_id)


func _on_packet(peer_id: int, data: PackedByteArray, t: Transport) -> void:
	var c := _find(t, peer_id)
	if c == null:
		return
	var over_limit: bool = _count_bytes(c, data.size())
	var msg: int = NetProtocol.msg_type(data)
	if over_limit and msg != NetProtocol.Msg.COMMAND:
		return
	match msg:
		NetProtocol.Msg.ACK:
			if c.sender != null:
				var tick: int = NetProtocol.decode_ack(data)
				if tick >= 0:
					c.sender.on_ack(tick, sim.tick)
		NetProtocol.Msg.COMMAND:
			_on_command(c, data, over_limit)
		NetProtocol.Msg.HELLO:
			_on_hello(c, data)


func _on_hello(c: Conn, data: PackedByteArray) -> void:
	if c.player_id != 0:
		return
	var hello := NetProtocol.decode_hello(data)
	var reason: NetProtocol.Refuse = NetProtocol.Refuse.NONE
	if hello.is_empty():
		reason = NetProtocol.Refuse.MALFORMED
	elif hello[0] != NetProtocol.PROTOCOL_VERSION:
		reason = NetProtocol.Refuse.PROTOCOL_VERSION
	elif hello[1] != _catalog_hash:
		reason = NetProtocol.Refuse.CATALOG_MISMATCH
	var pid: int = 0
	if reason == NetProtocol.Refuse.NONE:
		pid = _free_player_id()
		if pid == 0:
			reason = NetProtocol.Refuse.MATCH_FULL
	if reason != NetProtocol.Refuse.NONE:
		c.transport.send(c.peer_id, Transport.Channel.EVENTS, NetProtocol.encode_refused(reason))
		return
	c.player_id = pid
	c.sender = SnapshotSender.new(pid, sim.tick)
	c.transport.send(c.peer_id, Transport.Channel.EVENTS, NetProtocol.encode_welcome(pid, sim.tick, max_players))
	player_joined.emit(pid)


func _free_player_id() -> int:
	for pid: int in range(1, max_players + 1):
		if get_conn(pid) == null:
			return pid
	return 0


## Suma `n` bytes a la ventana de 1 s de la conexión. Devuelve true si se pasó del límite.
func _count_bytes(c: Conn, n: int) -> bool:
	var now: int = now_msec()
	if now - c.cmd_window_start >= SimConstants.RATE_LIMIT_WINDOW_MSEC:
		c.cmd_window_start = now
		c.cmd_bytes = 0
	c.cmd_bytes += n
	return c.cmd_bytes > SimConstants.RATE_LIMIT_BYTES_PER_SEC


func _on_command(c: Conn, data: PackedByteArray, over_limit: bool) -> void:
	if c.player_id == 0:
		return
	var cmd := CommandCodec.decode(data)
	if cmd == null:
		_send_rejected(c, 0, Command.Reject.MALFORMED)
		return
	# last_seq avanza aunque el comando se rechace (por límite o por validación).
	c.last_seq = maxi(c.last_seq, cmd.seq)
	if over_limit:
		_send_rejected(c, cmd.seq, Command.Reject.RATE_LIMITED)
		return
	# Los rechazos de validación quedan en la cola y se envían en _flush_rejections().
	sim.submit_command(c.player_id, cmd, now_msec())


func _flush_rejections() -> void:
	var rej := sim.queue.drain_rejections()
	for r: PackedInt32Array in rej:
		var c := get_conn(r[0])
		if c != null:
			_send_rejected(c, r[1], r[2])


func _send_rejected(c: Conn, seq: int, reason: int) -> void:
	c.transport.send(c.peer_id, Transport.Channel.EVENTS, NetProtocol.encode_rejected(seq, reason))
