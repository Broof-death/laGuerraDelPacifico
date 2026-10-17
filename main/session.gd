extends Node
## Autoload "Session" (ADR-006 punto 9): el único autoload del juego. Lleva la MatchConfig de la
## próxima partida desde el menú (o la línea de comandos) hasta main/match.tscn.
## La simulación nunca lo usa. Sin class_name, para no chocar con el nombre del autoload.

var config: MatchConfig


func _init() -> void:
	config = MatchConfig.from_args(OS.get_cmdline_user_args())
