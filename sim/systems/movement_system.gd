class_name MovementSystem
extends RefCounted
## Movimiento a 20 Hz (ADR-006 punto 1) siguiendo la ruta de la orden (T-013): cada unidad avanza
## en línea recta hacia su objetivo inmediato (wp_x, wp_z) a la velocidad de su definición
## (limitada por la del grupo de movimiento, si hay grupo). Los objetivos son los puntos de paso de
## la ruta compartida (RouteStore) desplazados por el puesto de la unidad en la formación (si ese
## punto desplazado no es transitable, el punto de paso tal cual) y, en el último tramo, su destino.
## - Ruta PENDING: la unidad espera quieta. FAILED: se detiene (el rechazo ya se avisó).
## - Al empezar la ruta, el destino de la unidad se corre con el ajuste del destino del grupo y, si
##   su puesto cae en terreno prohibido para su capa, va al destino ajustado del grupo.
## - VALIDACIÓN DEL TERRENO EN CADA PASO: si el paso entra en una celda prohibida para la capa de la
##   unidad (tropa al mar o barco a tierra), se intenta deslizar por un solo eje; si tampoco se
##   puede, la unidad se detiene. Una unidad que ya está en una celda prohibida puede salir.
## - Al llegar al destino, la entidad queda en IDLE y suelta su grupo y su ruta.
## Pendiente: giro progresivo con turn_rate, formaciones y evitación local (T-018).


## Recorre los slots [0, store.count). speed_by_def: velocidad en m/s por def_index; layer_by_def:
## Terrain.Layer por def_index. `map` puede ser null (sin terreno: todo transitable).
static func run(store: EntityStore, groups: MoveGroups, routes: RouteStore, map: LogicMap,
		layer_by_def: PackedByteArray, speed_by_def: PackedFloat32Array, dt: float) -> void:
	var n: int = store.count
	var act := store.action
	var defs := store.def_index
	var grp := store.move_group
	var rte := store.route
	var way := store.way_index
	var px := store.pos_x
	var pz := store.pos_z
	var wx := store.wp_x
	var wz := store.wp_z
	var hd := store.heading
	var vx := store.vel_x
	var vz := store.vel_z
	var caps := groups.speed_cap
	var r_status := routes.status
	var has_map: bool = map != null
	var land_table: PackedFloat32Array = map.cost_tables[Terrain.Layer.LAND] if has_map else PackedFloat32Array()
	var sea_table: PackedFloat32Array = map.cost_tables[Terrain.Layer.SEA] if has_map else PackedFloat32Array()
	var inv_dt: float = 1.0 / dt
	const MOVE: int = SimConstants.Action.MOVE
	const PENDING: int = RouteStore.Status.PENDING
	const FAILED: int = RouteStore.Status.FAILED
	const HALF: float = MapGrid.MAP_HALF
	const INV_CELL: float = 1.0 / MapGrid.TERRAIN_CELL
	for s: int in n:
		if act[s] != MOVE:
			continue
		var r: int = rte[s]
		if r != 0:
			var st: int = r_status[r]
			if st == PENDING:
				vx[s] = 0.0
				vz[s] = 0.0
				continue
			if st == FAILED:
				halt(store, groups, routes, s)
				continue
			if way[s] < 0:
				_begin_route(store, routes, map, layer_by_def[defs[s]], s, r)
		var speed: float = speed_by_def[defs[s]]
		var g: int = grp[s]
		if g != 0:
			speed = minf(speed, caps[g])
		var ox: float = px[s]
		var oz: float = pz[s]
		var dx: float = wx[s] - ox
		var dz: float = wz[s] - oz
		var dist: float = sqrt(dx * dx + dz * dz)
		var step: float = speed * dt
		var nx: float
		var nz: float
		var arrived: bool = dist <= step or dist < 0.0001
		if arrived:
			nx = wx[s]
			nz = wz[s]
		else:
			var k: float = step / dist
			nx = ox + dx * k
			nz = oz + dz * k
		if has_map:
			var ogx: int = int(floor((ox + HALF) * INV_CELL))
			var ogz: int = int(floor((oz + HALF) * INV_CELL))
			var ngx: int = int(floor((nx + HALF) * INV_CELL))
			var ngz: int = int(floor((nz + HALF) * INV_CELL))
			if ngx != ogx or ngz != ogz:
				var table: PackedFloat32Array = sea_table if layer_by_def[defs[s]] == Terrain.Layer.SEA else land_table
				if table[map.cell_byte(ngx, ngz)] <= 0.0 and table[map.cell_byte(ogx, ogz)] > 0.0:
					# Celda prohibida para la capa: deslizar por un solo eje o detenerse.
					arrived = false
					if ngx != ogx and table[map.cell_byte(ngx, ogz)] > 0.0:
						nz = oz
					elif ngz != ogz and table[map.cell_byte(ogx, ngz)] > 0.0:
						nx = ox
					else:
						halt(store, groups, routes, s)
						continue
		px[s] = nx
		pz[s] = nz
		if arrived:
			if r != 0 and way[s] < routes.point_count(r) - 1:
				# Punto de paso intermedio: pasa al siguiente sin detenerse.
				way[s] += 1
				_set_target(store, routes, map, layer_by_def[defs[s]], s, r)
				vx[s] = (nx - ox) * inv_dt
				vz[s] = (nz - oz) * inv_dt
				continue
			halt(store, groups, routes, s)
			continue
		vx[s] = (nx - ox) * inv_dt
		vz[s] = (nz - oz) * inv_dt
		hd[s] = atan2(nx - ox, nz - oz)


## Detiene la unidad (IDLE, velocidad 0) y suelta su grupo y su ruta.
static func halt(store: EntityStore, groups: MoveGroups, routes: RouteStore, s: int) -> void:
	store.action[s] = SimConstants.Action.IDLE
	store.vel_x[s] = 0.0
	store.vel_z[s] = 0.0
	var g: int = store.move_group[s]
	if g != 0:
		groups.leave(g)
		store.move_group[s] = 0
	var r: int = store.route[s]
	if r != 0:
		routes.release(r)
		store.route[s] = 0
	store.way_index[s] = -1


## La ruta está lista: corre el destino de la unidad con el ajuste del destino del grupo y apunta
## al primer punto de paso.
static func _begin_route(store: EntityStore, routes: RouteStore, map: LogicMap, layer: int, s: int, r: int) -> void:
	store.dest_x[s] += routes.final_x[r] - routes.goal_x[r]
	store.dest_z[s] += routes.final_z[r] - routes.goal_z[r]
	if map != null and not map.passable_at(layer, store.dest_x[s], store.dest_z[s]):
		store.dest_x[s] = routes.final_x[r]
		store.dest_z[s] = routes.final_z[r]
	store.way_index[s] = 0
	_set_target(store, routes, map, layer, s, r)


## Objetivo inmediato para el punto de paso way_index[s].
static func _set_target(store: EntityStore, routes: RouteStore, map: LogicMap, layer: int, s: int, r: int) -> void:
	var i: int = store.way_index[s]
	var count: int = routes.point_count(r)
	if i >= count - 1:
		store.wp_x[s] = store.dest_x[s]
		store.wp_z[s] = store.dest_z[s]
		return
	var pts: PackedFloat64Array = routes.points[r]
	var x: float = pts[i * 2] + (store.dest_x[s] - routes.final_x[r])
	var z: float = pts[i * 2 + 1] + (store.dest_z[s] - routes.final_z[r])
	if map != null and not map.passable_at(layer, x, z):
		x = pts[i * 2]
		z = pts[i * 2 + 1]
	store.wp_x[s] = x
	store.wp_z[s] = z
