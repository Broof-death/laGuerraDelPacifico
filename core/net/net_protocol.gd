class_name NetProtocol
extends RefCounted
## Mensajes de red (ADR-006 puntos 5 y 9). Todo paquete empieza con un byte de tipo (Msg).
## Canales (Transport.Channel):
##   COMMANDS  (reliable): HELLO y COMMAND, del cliente al servidor.
##   SNAPSHOTS (unreliable ordenado): SNAPSHOT (servidor -> cliente) y ACK (cliente -> servidor).
##   EVENTS    (reliable): WELCOME, REFUSED y COMMAND_REJECTED, del servidor al cliente.
## Codificación binaria con BitWriter/BitReader; nunca var_to_bytes.

## Sube cada vez que cambia el formato de algún mensaje o del snapshot.
const PROTOCOL_VERSION: int = 2

enum Msg {
	NONE = 0,
	HELLO = 1,
	COMMAND = 2,
	ACK = 3,
	WELCOME = 10,
	REFUSED = 11,
	SNAPSHOT = 12,
	COMMAND_REJECTED = 13,
}

## Motivo por el que el servidor no acepta a un cliente.
enum Refuse {
	NONE = 0,
	PROTOCOL_VERSION = 1,
	CATALOG_MISMATCH = 2,
	MATCH_FULL = 3,
	MALFORMED = 4,
}


static func msg_type(data: PackedByteArray) -> int:
	return data[0] if data.size() > 0 else Msg.NONE


## Canal por el que viaja cada tipo de mensaje.
static func channel_of(msg: int) -> int:
	match msg:
		Msg.SNAPSHOT, Msg.ACK:
			return Transport.Channel.SNAPSHOTS
		Msg.HELLO, Msg.COMMAND:
			return Transport.Channel.COMMANDS
		_:
			return Transport.Channel.EVENTS


# --- HELLO: versión del protocolo y huella del catálogo (ADR-007: misma versión de GameData) ----

static func encode_hello(catalog_hash: int) -> PackedByteArray:
	var w := BitWriter.new()
	w.write_bits(Msg.HELLO, 8)
	w.write_bits(PROTOCOL_VERSION, 16)
	w.write_bits(catalog_hash, 32)
	return w.get_bytes()


## Devuelve [version, catalog_hash] o un array vacío si está mal formado.
static func decode_hello(data: PackedByteArray) -> PackedInt64Array:
	var r := BitReader.new(data)
	if r.read_bits(8) != Msg.HELLO:
		return PackedInt64Array()
	var version: int = r.read_bits(16)
	var h: int = r.read_bits(32)
	if r.error:
		return PackedInt64Array()
	return PackedInt64Array([version, h])


# --- WELCOME -------------------------------------------------------------------------------------

static func encode_welcome(player_id: int, tick: int, max_players: int) -> PackedByteArray:
	var w := BitWriter.new()
	w.write_bits(Msg.WELCOME, 8)
	w.write_bits(player_id, 8)
	w.write_bits(tick, 32)
	w.write_bits(max_players, 8)
	return w.get_bytes()


## Devuelve [player_id, tick, max_players] o vacío.
static func decode_welcome(data: PackedByteArray) -> PackedInt64Array:
	var r := BitReader.new(data)
	if r.read_bits(8) != Msg.WELCOME:
		return PackedInt64Array()
	var out := PackedInt64Array([r.read_bits(8), r.read_bits(32), r.read_bits(8)])
	return PackedInt64Array() if r.error else out


# --- REFUSED -------------------------------------------------------------------------------------

static func encode_refused(reason: Refuse) -> PackedByteArray:
	return PackedByteArray([Msg.REFUSED, reason])


static func decode_refused(data: PackedByteArray) -> int:
	return data[1] if data.size() >= 2 and data[0] == Msg.REFUSED else Refuse.MALFORMED


# --- ACK (tick del último snapshot recibido completo) --------------------------------------------

static func encode_ack(tick: int) -> PackedByteArray:
	var w := BitWriter.new()
	w.write_bits(Msg.ACK, 8)
	w.write_bits(tick, 32)
	return w.get_bytes()


## Devuelve el tick confirmado o -1.
static func decode_ack(data: PackedByteArray) -> int:
	var r := BitReader.new(data)
	if r.read_bits(8) != Msg.ACK:
		return -1
	var t: int = r.read_bits(32)
	return -1 if r.error else t


# --- COMMAND_REJECTED(seq, motivo) ---------------------------------------------------------------

static func encode_rejected(seq: int, reason: int) -> PackedByteArray:
	var w := BitWriter.new()
	w.write_bits(Msg.COMMAND_REJECTED, 8)
	w.write_varint(seq)
	w.write_bits(reason, 8)
	return w.get_bytes()


## Devuelve [seq, motivo] o vacío.
static func decode_rejected(data: PackedByteArray) -> PackedInt32Array:
	var r := BitReader.new(data)
	if r.read_bits(8) != Msg.COMMAND_REJECTED:
		return PackedInt32Array()
	var out := PackedInt32Array([r.read_varint(), r.read_bits(8)])
	return PackedInt32Array() if r.error else out
