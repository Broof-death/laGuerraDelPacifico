class_name MovementSystem
extends RefCounted
## Movimiento a 20 Hz (ADR-006 punto 1): avance en línea recta hacia el destino (dest_x, dest_z)
## a la velocidad de la definición (limitada por la del grupo de movimiento, si hay grupo).
## Al llegar, la entidad queda en IDLE y sale de su grupo.
## Pendiente: giro progresivo con turn_rate, evitación local (con la SpatialGrid) y rutas (T-018).


## Recorre los slots [0, store.count). speed_by_def: velocidad en m/s por def_index.
static func run(store: EntityStore, groups: MoveGroups, speed_by_def: PackedFloat32Array, dt: float) -> void:
	var n: int = store.count
	var act := store.action
	var defs := store.def_index
	var grp := store.move_group
	var px := store.pos_x
	var pz := store.pos_z
	var dx_arr := store.dest_x
	var dz_arr := store.dest_z
	var hd := store.heading
	var vx := store.vel_x
	var vz := store.vel_z
	var caps := groups.speed_cap
	const MOVE: int = SimConstants.Action.MOVE
	const IDLE: int = SimConstants.Action.IDLE
	for s: int in n:
		if act[s] != MOVE:
			continue
		var speed: float = speed_by_def[defs[s]]
		var g: int = grp[s]
		if g != 0:
			speed = minf(speed, caps[g])
		var ox: float = px[s]
		var oz: float = pz[s]
		var dx: float = dx_arr[s] - ox
		var dz: float = dz_arr[s] - oz
		var dist: float = sqrt(dx * dx + dz * dz)
		var step: float = speed * dt
		if dist <= step or dist < 0.0001:
			px[s] = dx_arr[s]
			pz[s] = dz_arr[s]
			vx[s] = 0.0
			vz[s] = 0.0
			act[s] = IDLE
			if g != 0:
				groups.leave(g)
				grp[s] = 0
			continue
		var k: float = step / dist
		px[s] = ox + dx * k
		pz[s] = oz + dz * k
		var inv: float = speed / dist
		vx[s] = dx * inv
		vz[s] = dz * inv
		hd[s] = atan2(dx, dz)
