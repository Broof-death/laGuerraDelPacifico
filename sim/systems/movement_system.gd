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

## way_index: índice del punto de paso en los bits bajos; RAW = sigue la ruta sin desplazamiento.
const RAW: int = 1 << 24
const INDEX_MASK: int = RAW - 1


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
						# Sin salida: si iba a un punto desplazado (formación), pasa al punto de
						# la ruta tal cual; si ya iba ahí, se detiene.
						if not _fall_back_to_route(store, routes, s, r):
							halt(store, groups, routes, s)
						continue
		px[s] = nx
		pz[s] = nz
		if arrived:
			if r != 0 and (way[s] & INDEX_MASK) < routes.point_count(r) - 1:
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


## Cambia el objetivo inmediato desplazado por el punto de la ruta sin desplazar (o el destino
## propio por el del grupo) y sigue la ruta sin desplazamiento. Devuelve false si ya apuntaba ahí.
static func _fall_back_to_route(store: EntityStore, routes: RouteStore, s: int, r: int) -> bool:
	if r == 0 or store.way_index[s] < 0:
		return false
	var i: int = store.way_index[s] & INDEX_MASK
	var x: float
	var z: float
	if i >= routes.point_count(r) - 1:
		x = routes.final_x[r]
		z = routes.final_z[r]
		store.dest_x[s] = x
		store.dest_z[s] = z
	else:
		x = routes.points[r][i * 2]
		z = routes.points[r][i * 2 + 1]
	if store.wp_x[s] == x and store.wp_z[s] == z:
		return false
	store.way_index[s] = i | RAW
	store.wp_x[s] = x
	store.wp_z[s] = z
	store.vel_x[s] = 0.0
	store.vel_z[s] = 0.0
	return true


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


## Objetivo inmediato para el punto de paso way_index[s] (desde la posición actual P):
## - Tramo intermedio i: el punto de la ruta desplazado por el puesto de la unidad, si el segmento
##   P -> punto desplazado es transitable; si no, el punto de la ruta tal cual (y desde ahí sigue
##   la ruta sin desplazamiento, "modo RAW"); si tampoco se llega en línea recta, vuelve primero al
##   punto de ruta anterior (desde el que el tramo de la ruta es transitable por construcción).
## - Último tramo: su puesto; si no se llega en línea recta, el destino del grupo; si tampoco,
##   vuelve al punto de ruta anterior.
## Con desplazamiento nulo (órdenes de menos de 8 unidades) y P en la ruta, no hace falta revisar.
static func _set_target(store: EntityStore, routes: RouteStore, map: LogicMap, layer: int, s: int, r: int) -> void:
	var w: int = store.way_index[s]
	var raw: bool = (w & RAW) != 0
	var i: int = w & INDEX_MASK
	var count: int = routes.point_count(r)
	var pts: PackedFloat64Array = routes.points[r]
	var px: float = store.pos_x[s]
	var pz: float = store.pos_z[s]
	var off_x: float = store.dest_x[s] - routes.final_x[r]
	var off_z: float = store.dest_z[s] - routes.final_z[r]
	var no_offset: bool = absf(off_x) < 0.001 and absf(off_z) < 0.001
	if i >= count - 1:
		if map == null or (no_offset and (raw or i > 0)) 				or map.segment_passable(layer, px, pz, store.dest_x[s], store.dest_z[s]):
			store.wp_x[s] = store.dest_x[s]
			store.wp_z[s] = store.dest_z[s]
			return
		if map.segment_passable(layer, px, pz, routes.final_x[r], routes.final_z[r]) or i == 0:
			store.dest_x[s] = routes.final_x[r]
			store.dest_z[s] = routes.final_z[r]
			store.wp_x[s] = store.dest_x[s]
			store.wp_z[s] = store.dest_z[s]
			return
		_back_to(store, pts, s, i - 1)
		return
	var rx: float = pts[i * 2]
	var rz: float = pts[i * 2 + 1]
	if not raw and not no_offset:
		var tx: float = rx + off_x
		var tz: float = rz + off_z
		if map == null or (map.passable_at(layer, tx, tz) and map.segment_passable(layer, px, pz, tx, tz)):
			store.wp_x[s] = tx
			store.wp_z[s] = tz
			return
	if map == null or ((raw or no_offset) and i > 0) or i == 0 or map.segment_passable(layer, px, pz, rx, rz):
		store.way_index[s] = i | RAW
		store.wp_x[s] = rx
		store.wp_z[s] = rz
		return
	_back_to(store, pts, s, i - 1)


## Vuelve al punto de ruta j (sin desplazamiento): desde ahí el siguiente tramo es transitable.
static func _back_to(store: EntityStore, pts: PackedFloat64Array, s: int, j: int) -> void:
	store.way_index[s] = j | RAW
	store.wp_x[s] = pts[j * 2]
	store.wp_z[s] = pts[j * 2 + 1]
