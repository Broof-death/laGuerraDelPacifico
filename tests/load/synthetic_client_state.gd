class_name SyntheticClientState
extends ClientState
## ClientState que se llena a mano (prueba de render y pruebas unitarias de las vistas): agrega
## entidades sin snapshots y permite escribir directamente las posiciones de dibujo.


## Agrega una entidad y devuelve su slot.
func add_entity(id: int, p_def: int, p_owner: int, x: float, z: float, heading: float = 0.0) -> int:
	var s: int = _add(id, p_def, p_owner)
	action[s] = 0
	hp_ratio[s] = 1.0
	progress[s] = 0.0
	render_x[s] = x
	render_z[s] = z
	render_heading[s] = heading
	return s
