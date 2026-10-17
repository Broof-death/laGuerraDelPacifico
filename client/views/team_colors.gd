class_name TeamColors
extends RefCounted
## Colores de bando para las vistas provisionales (ADR-005, T-017). Solo cliente.
##
## PROVISIONAL: todavía no hay una asignación jugador -> FactionDef (la partida de prueba pone a
## todos en la misma facción), así que el color sale de una paleta por player_id para que los
## bandos se distingan. Cuando el arranque de partida asigne facciones, el que arme las vistas
## pasa los colores con from_factions() (FactionDef.color) y nada más cambia.

## Índice = player_id (0 = neutral). Colores neutros, sin intención histórica.
const PALETTE: Array[Color] = [
	Color(0.62, 0.62, 0.62),  # 0 neutral
	Color(0.80, 0.16, 0.14),  # 1 rojo
	Color(0.15, 0.36, 0.85),  # 2 azul
	Color(0.92, 0.78, 0.15),  # 3 amarillo
	Color(0.20, 0.66, 0.26),  # 4 verde
	Color(0.58, 0.26, 0.74),  # 5 morado
	Color(0.95, 0.52, 0.12),  # 6 naranja
]


## Paleta por defecto para los player_id 0..SimConstants.MAX_PLAYER_ID.
static func default_palette() -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(SimConstants.MAX_PLAYER_ID + 1)
	for p: int in out.size():
		out[p] = color_for_player(p)
	return out


## Color de un player_id. Más allá de la paleta se repite con un tono más oscuro.
static func color_for_player(player_id: int) -> Color:
	if player_id <= 0:
		return PALETTE[0]
	var i: int = (player_id - 1) % (PALETTE.size() - 1) + 1
	var c: Color = PALETTE[i]
	if player_id >= PALETTE.size():
		c = c.darkened(0.35)
	return c


## Paleta a partir de las facciones de cada jugador (índice = player_id; null = paleta por
## defecto para ese jugador).
static func from_factions(factions_by_player: Array[FactionDef]) -> PackedColorArray:
	var out := default_palette()
	for p: int in mini(factions_by_player.size(), out.size()):
		var f: FactionDef = factions_by_player[p]
		if f != null:
			out[p] = f.color
	return out
