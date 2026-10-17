class_name MatchConfig
extends RefCounted
## Configuración de arranque de una partida (ADR-006 punto 9). La lleva el autoload Session y la
## lee main/match.tscn. Se puede llenar desde el menú (T-038) o desde la línea de comandos:
##   godot --path . res://main/match.tscn -- --mode=host
##   godot --path . res://main/match.tscn -- --mode=join --address=127.0.0.1
##   godot --headless --path . res://main/match.tscn -- --server --port=24790
## Opciones: --mode=single|host|join|dedicated (o --server), --address=, --port=,
## --max_players=, --players=, --units=, --seed=, --quit_after= (segundos; 0 = nunca).

enum Mode {
	SINGLE,     ## un jugador: servidor y cliente en el mismo proceso, por LocalTransport
	HOST,       ## anfitrión: servidor ENet + su propio cliente por LocalTransport
	JOIN,       ## unirse a un anfitrión o servidor dedicado por ENet
	DEDICATED,  ## servidor dedicado sin cliente (--server)
}

var mode: Mode = Mode.SINGLE
var address: String = "127.0.0.1"
var port: int = 24790
var max_players: int = SimConstants.MAX_PLAYERS
## Ejércitos de prueba (provisional hasta que exista el arranque real de partida): cuántos
## jugadores reciben unidades y cuántas cada uno.
var players: int = 2
var units_per_player: int = 20
var match_seed: int = 1
## Cierra el juego pasados estos segundos (servidores de prueba headless). 0 = nunca.
var quit_after_seconds: float = 0.0


func is_server() -> bool:
	return mode != Mode.JOIN


func has_client() -> bool:
	return mode != Mode.DEDICATED


static func from_args(args: PackedStringArray) -> MatchConfig:
	var c := MatchConfig.new()
	for a: String in args:
		if a == "--server":
			c.mode = Mode.DEDICATED
			continue
		if not a.begins_with("--") or not a.contains("="):
			continue
		var kv := a.substr(2).split("=", true, 1)
		var v: String = kv[1]
		match kv[0]:
			"mode":
				match v:
					"single":
						c.mode = Mode.SINGLE
					"host":
						c.mode = Mode.HOST
					"join":
						c.mode = Mode.JOIN
					"dedicated", "server":
						c.mode = Mode.DEDICATED
			"address":
				c.address = v
			"port":
				c.port = v.to_int()
			"max_players":
				c.max_players = clampi(v.to_int(), 1, SimConstants.MAX_PLAYERS)
			"players":
				c.players = clampi(v.to_int(), 0, SimConstants.MAX_PLAYERS)
			"units":
				c.units_per_player = maxi(0, v.to_int())
			"seed":
				c.match_seed = v.to_int()
			"quit_after":
				c.quit_after_seconds = v.to_float()
	return c
