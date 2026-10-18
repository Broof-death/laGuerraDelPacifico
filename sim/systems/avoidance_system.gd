class_name AvoidanceSystem
extends RefCounted
## Evitación local (ADR-006 punto 1, T-018): separa las unidades de tierra que se solapan (propias
## y ajenas), según su radio. Corre a 10 Hz (un tick de cada dos, RUN_EVERY), después del
## movimiento.
##
## REJILLA: dos rejillas dispersas de celdas finas (como la SpatialGrid: claves celda/dueño/slot
## ordenadas con el sort nativo; lado = la mayor distancia de contacto, dos radios de la unidad de
## tierra más grande que hay en la partida), una con las unidades QUIETAS y otra con las que se
## MUEVEN, reconstruidas cada tick. Dos unidades que se tocan están en la misma celda o en celdas
## vecinas. Nada es O(n^2) ni usa búsquedas binarias por unidad: las claves están ordenadas por
## celda (fila a fila) y los vecinos se encuentran con punteros que solo avanzan.
##
## PARES:
## - En movimiento contra quieta, en cada pasada (10 Hz): cada unidad en movimiento mira las quietas de sus 3 x 3
##   celdas. Es el choque que más se ve (una columna que atraviesa una formación parada): la quieta
##   cede IDLE_SHARE del empuje.
## - Quieta contra quieta (IDLE_PHASES) y en movimiento contra en movimiento (SLOW_PHASES), escalonados
##   por filas de la rejilla (cada par cada 0,2 o 0,4 s): son solapes que cambian
##   despacio (dos unidades que avanzan juntas o una formación que se acomoda). Así el costo por
##   tick baja a la cuarta parte cuando todo el ejército se mueve. Cada par se revisa una sola vez
##   (la "mitad siguiente" del vecindario).
## - PROVISIONAL hasta el combate: dos unidades de distinto dueño que se mueven las dos se
##   atraviesan. Sin combate, los ATTACK_MOVE cruzados de la prueba de carga formarían un tapón de
##   miles de unidades; con combate, el ATTACK_MOVE se detendrá a distancia de tiro.
##
## EMPUJE: cada par que se solapa se separa PUSH_FACTOR del solape (más SLOP), repartido entre las
## dos. Si coinciden exactamente, la dirección sale de sus claves (determinista). El empuje total
## de una unidad en un tick se limita a MAX_PUSH. Nunca mete a una unidad en una celda prohibida
## para su capa (agua para las tropas): se intenta deslizar por un solo eje y, si tampoco se puede,
## se descarta. Determinista: el orden de las claves (celda, dueño, slot) fija el de las sumas.
## Los buques (capa de mar) no entran: su evitación es de otra tarea.

const PUSH_FACTOR: float = 0.5
## Holgura (m): un par cuenta como solapado si le faltan más de SLOP para tocarse apenas, y el
## empuje lo deja SLOP más separado de lo justo (si no, la separación por mitades nunca termina).
const SLOP: float = 0.01
## Empuje máximo por tick (m): 6 m/s a 20 Hz.
const MAX_PUSH: float = 0.3
## Parte del empuje que recibe una unidad quieta frente a una que se mueve (la otra, el resto).
const IDLE_SHARE: float = 0.8
## Fases del escalonado de los pares quieta-quieta y en movimiento-en movimiento.
const SLOW_PHASES: int = 4
## Las quietas entre sí, en menos fases (cada par cada 0,2 s): así una formación apretada se
## acomoda rápido.
const IDLE_PHASES: int = 2
## La evitación corre un tick de cada RUN_EVERY (10 Hz), en los ticks con tick % RUN_EVERY ==
## RUN_PHASE: los que NO cuantizan el mundo para los snapshots (MatchServer lo hace cuando el tick
## ya incrementado es par), para repartir el costo entre los dos ticks del ciclo.
const RUN_EVERY: int = 2
const RUN_PHASE: int = 0
## Dos unidades que se mueven las dos pueden solaparse hasta un cuarto de la suma de sus radios
## sin empujarse (columnas que se cruzan o se acomodan): menos empujones y menos reenvíos en los
## snapshots. Al detenerse, la separación completa las deja sin solaparse.
const MOVING_REACH: float = 0.75

## false = sin evitación (solo para mediciones A/B de la prueba de carga).
var enabled: bool = true
## Pares revisados y pares que se solapaban en el último run() (estadística).
var last_pairs: int = 0
var last_overlaps: int = 0
## Tiempos (µs) de las fases del último run(), solo para medir: rejillas, copia, pares y empuje.
var last_phase_usec := PackedInt64Array([0, 0, 0, 0])

var _bounds: Rect2
var _cell: float = 2.0
var _cols: int = 1
var _rows: int = 1
## Conjuntos: 0 = quietas, 1 = en movimiento. Por conjunto: claves ordenadas y, en ese orden,
## posición, radio, dueño, celda y empuje acumulado.
var _keys: Array[PackedInt64Array] = [PackedInt64Array(), PackedInt64Array()]
var _x: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _z: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _r: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _o: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _c: Array[PackedInt64Array] = [PackedInt64Array(), PackedInt64Array()]
var _px: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _pz: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _pairs: int = 0
var _overlaps: int = 0


func _init(bounds: Rect2) -> void:
	_bounds = bounds
	_set_cell(2.0)


func _set_cell(cell: float) -> void:
	_cell = cell
	_cols = maxi(1, ceili(_bounds.size.x / cell))
	_rows = maxi(1, ceili(_bounds.size.y / cell))


## Lado de las celdas finas (m).
func cell_size() -> float:
	return _cell


## `include_by_def`: 1 para las defs que participan (unidades de tierra móviles).
## `contact`: la mayor distancia de contacto (2 x el mayor radio de las que participan).
## `tick`: fija la fase del escalonado.
func run(store: EntityStore, map: LogicMap, include_by_def: PackedByteArray, radius_by_def: PackedFloat32Array,
		contact: float, tick: int) -> void:
	last_pairs = 0
	last_overlaps = 0
	_pairs = 0
	_overlaps = 0
	if contact <= 0.0 or not enabled:
		return
	var cell: float = maxf(contact, 0.5)
	if cell != _cell:
		_set_cell(cell)
	var t0: int = Time.get_ticks_usec()
	_build_keys(store, include_by_def)
	var t1: int = Time.get_ticks_usec()
	last_phase_usec[0] = t1 - t0
	_copy(store, radius_by_def)
	var t2: int = Time.get_ticks_usec()
	last_phase_usec[1] = t2 - t1
	var run: int = tick / RUN_EVERY
	_moving_vs_idle()
	_within(0, run % IDLE_PHASES, IDLE_PHASES, false, 1.0)
	_within(1, run % SLOW_PHASES, SLOW_PHASES, true, MOVING_REACH)
	last_pairs = _pairs
	last_overlaps = _overlaps
	var t3: int = Time.get_ticks_usec()
	last_phase_usec[2] = t3 - t2
	last_phase_usec[3] = 0
	if _overlaps == 0:
		return
	_apply(store, map, 0)
	_apply(store, map, 1)
	last_phase_usec[3] = Time.get_ticks_usec() - t3


## Claves (celda, dueño, slot) de las quietas y de las que se mueven, ordenadas.
func _build_keys(store: EntityStore, include_by_def: PackedByteArray) -> void:
	var n: int = store.count
	var px := store.pos_x
	var pz := store.pos_z
	var owners := store.owner
	var defs := store.def_index
	var act := store.action
	var ki: PackedInt64Array = _keys[0]
	var km: PackedInt64Array = _keys[1]
	ki.resize(n)
	km.resize(n)
	var ni: int = 0
	var nm: int = 0
	var inv: float = 1.0 / _cell
	var ox: float = _bounds.position.x
	var oz: float = _bounds.position.y
	var max_cx: int = _cols - 1
	var max_cz: int = _rows - 1
	var cols: int = _cols
	const CS: int = SpatialGrid.CELL_SHIFT
	const OS: int = SpatialGrid.OWNER_SHIFT
	const MOVE: int = SimConstants.Action.MOVE
	for s: int in n:
		if include_by_def[defs[s]] == 0:
			continue
		# Las posiciones de la simulación están dentro de los límites (no negativas: sin floor).
		var fx: float = (px[s] - ox) * inv
		var fz: float = (pz[s] - oz) * inv
		var cx: int = mini(int(fx), max_cx) if fx > 0.0 else 0
		var cz: int = mini(int(fz), max_cz) if fz > 0.0 else 0
		var key: int = ((cz * cols + cx) << CS) | (owners[s] << OS) | s
		if act[s] == MOVE:
			km[nm] = key
			nm += 1
		else:
			ki[ni] = key
			ni += 1
	ki.resize(ni)
	km.resize(nm)
	ki.sort()
	km.sort()


## Copia posición, radio, dueño y celda en el orden de las claves, y pone el empuje a cero.
func _copy(store: EntityStore, radius_by_def: PackedFloat32Array) -> void:
	var px := store.pos_x
	var pz := store.pos_z
	var defs := store.def_index
	const CS: int = SpatialGrid.CELL_SHIFT
	const SM: int = SpatialGrid.SLOT_MASK
	const OS: int = SpatialGrid.OWNER_SHIFT
	for set: int in 2:
		var keys: PackedInt64Array = _keys[set]
		var m: int = keys.size()
		var X: PackedFloat64Array = _x[set]
		var Z: PackedFloat64Array = _z[set]
		var R: PackedFloat32Array = _r[set]
		var O: PackedInt32Array = _o[set]
		var C: PackedInt64Array = _c[set]
		X.resize(m)
		Z.resize(m)
		R.resize(m)
		O.resize(m)
		C.resize(m)
		_px[set].resize(m)
		_pz[set].resize(m)
		_px[set].fill(0.0)
		_pz[set].fill(0.0)
		for i: int in m:
			var k: int = keys[i]
			var s: int = k & SM
			X[i] = px[s]
			Z[i] = pz[s]
			R[i] = radius_by_def[defs[s]]
			O[i] = (k >> OS) & 15
			C[i] = k >> CS


## Unidades en movimiento contra quietas (20 Hz): vecindario completo de 3 x 3 celdas de cada una
## en la rejilla de las quietas, con tres punteros (filas de arriba, propia y de abajo). Las de una
## misma celda comparten los tramos, y las filas sin quietas cerca se saltan de una vez.
func _moving_vs_idle() -> void:
	var mi: int = _keys[0].size()
	var mm: int = _keys[1].size()
	if mi == 0 or mm == 0:
		return
	var IX: PackedFloat64Array = _x[0]
	var IZ: PackedFloat64Array = _z[0]
	var IR: PackedFloat32Array = _r[0]
	var IC: PackedInt64Array = _c[0]
	var IPX: PackedFloat64Array = _px[0]
	var IPZ: PackedFloat64Array = _pz[0]
	var MX: PackedFloat64Array = _x[1]
	var MZ: PackedFloat64Array = _z[1]
	var MR: PackedFloat32Array = _r[1]
	var MC: PackedInt64Array = _c[1]
	var MPX: PackedFloat64Array = _px[1]
	var MPZ: PackedFloat64Array = _pz[1]
	var cols: int = _cols
	var p0: int = 0
	var p1: int = 0
	var p2: int = 0
	var pairs: int = 0
	var overlaps: int = 0
	var ranges := PackedInt32Array([0, 0, 0, 0, 0, 0])
	const SHARE_M: float = 1.0 - IDLE_SHARE
	var a: int = 0
	while a < mm:
		var ca: int = MC[a]
		var row: int = ca / cols
		# Sin quietas en las filas row-1..row+1: salta todas las que se mueven hasta la fila
		# anterior a la de la próxima quieta.
		var row_start: int = (row - 1) * cols - 1
		while p0 < mi and IC[p0] < row_start:
			p0 += 1
		if p0 >= mi:
			break
		var idle_row: int = IC[p0] / cols
		if idle_row > row + 1:
			var target: int = (idle_row - 1) * cols - 1
			while a < mm and MC[a] < target:
				a += 1
			continue
		# Unidades en movimiento de la misma celda: comparten los tres tramos de quietas.
		var e: int = a + 1
		while e < mm and MC[e] == ca:
			e += 1
		var lo: int = ca - cols - 1
		while p0 < mi and IC[p0] < lo:
			p0 += 1
		var q: int = p0
		while q < mi and IC[q] <= lo + 2:
			q += 1
		ranges[0] = p0
		ranges[1] = q
		lo = ca - 1
		while p1 < mi and IC[p1] < lo:
			p1 += 1
		q = p1
		while q < mi and IC[q] <= lo + 2:
			q += 1
		ranges[2] = p1
		ranges[3] = q
		lo = ca + cols - 1
		while p2 < mi and IC[p2] < lo:
			p2 += 1
		q = p2
		while q < mi and IC[q] <= lo + 2:
			q += 1
		ranges[4] = p2
		ranges[5] = q
		var cand: int = ranges[1] - ranges[0] + ranges[3] - ranges[2] + ranges[5] - ranges[4]
		if cand > 0:
			pairs += cand * (e - a)
			for k: int in range(a, e):
				var ax: float = MX[k]
				var az: float = MZ[k]
				var ra: float = MR[k]
				for t: int in 3:
					for b: int in range(ranges[t * 2], ranges[t * 2 + 1]):
						var dx: float = IX[b] - ax
						var dz: float = IZ[b] - az
						var lim: float = ra + IR[b] - SLOP
						var d2: float = dx * dx + dz * dz
						if d2 >= lim * lim:
							continue
						overlaps += 1
						var dd: float = sqrt(d2)
						var nx: float = 1.0
						var nz: float = 0.0
						if dd > 0.0001:
							nx = dx / dd
							nz = dz / dd
						else:
							var ang: float = _tie_angle(_keys[1][k], _keys[0][b])
							nx = cos(ang)
							nz = sin(ang)
						var amount: float = (lim + 2.0 * SLOP - dd) * PUSH_FACTOR
						MPX[k] -= nx * amount * SHARE_M
						MPZ[k] -= nz * amount * SHARE_M
						IPX[b] += nx * amount * IDLE_SHARE
						IPZ[b] += nz * amount * IDLE_SHARE
		a = e
	_pairs += pairs
	_overlaps += overlaps


## Pares dentro de un conjunto (quietas o en movimiento), escalonados: solo las unidades de las
## filas de la rejilla con fila % phases == phase miran la mitad siguiente de su vecindario
## (el resto de su celda, la celda de la derecha y las tres de la fila de abajo). Con
## `skip_enemies`, dos de distinto dueño no se empujan (en movimiento las dos: provisional).
## `reach`: fracción de la suma de radios a partir de la cual se separan.
func _within(set: int, phase: int, phases: int, skip_enemies: bool, reach: float) -> void:
	var m: int = _keys[set].size()
	if m < 2:
		return
	var X: PackedFloat64Array = _x[set]
	var Z: PackedFloat64Array = _z[set]
	var R: PackedFloat32Array = _r[set]
	var O: PackedInt32Array = _o[set]
	var C: PackedInt64Array = _c[set]
	var PX: PackedFloat64Array = _px[set]
	var PZ: PackedFloat64Array = _pz[set]
	var cols: int = _cols
	var pairs: int = 0
	var overlaps: int = 0
	var p: int = 0
	var i: int = 0
	while i < m:
		var ci: int = C[i]
		# Fila de esta celda: si no le toca en esta fase, salta la fila entera.
		var row: int = ci / cols
		if row % phases != phase:
			# Salta a la próxima fila de esta fase (búsqueda binaria nativa).
			var skip: int = (phase - row % phases + phases) % phases
			i = C.bsearch((row + skip) * cols, true)
			continue
		var e: int = i + 1
		while e < m and C[e] == ci:
			e += 1
		# Celda de la derecha: [e, j_end). Fila de abajo, columnas cx-1..cx+1: [p, q_end).
		var j_end: int = e
		while j_end < m and C[j_end] == ci + 1:
			j_end += 1
		var lo: int = ci + cols - 1
		var hi: int = lo + 2
		if p < j_end:
			p = j_end
		while p < m and C[p] < lo:
			p += 1
		var q_end: int = p
		while q_end < m and C[q_end] <= hi:
			q_end += 1
		var na: int = e - i
		pairs += na * (j_end - i - 1) - na * (na - 1) / 2 + na * (q_end - p)
		for a: int in range(i, e):
			var ax: float = X[a]
			var az: float = Z[a]
			var ra: float = R[a]
			var oa: int = O[a]
			# Dos tramos de candidatos: el resto de la fila y la fila de abajo (el cuerpo se repite:
			# es el bucle más caliente y una llamada por par costaría más).
			for b: int in range(a + 1, j_end):
				var dx: float = X[b] - ax
				var dz: float = Z[b] - az
				var lim: float = (ra + R[b]) * reach - SLOP
				var d2: float = dx * dx + dz * dz
				if d2 >= lim * lim or (skip_enemies and O[b] != oa):
					continue
				overlaps += 1
				var dd: float = sqrt(d2)
				var nx: float = 1.0
				var nz: float = 0.0
				if dd > 0.0001:
					nx = dx / dd
					nz = dz / dd
				else:
					var ang: float = _tie_angle(_keys[set][a], _keys[set][b])
					nx = cos(ang)
					nz = sin(ang)
				var half: float = (lim + 2.0 * SLOP - dd) * PUSH_FACTOR * 0.5
				PX[a] -= nx * half
				PZ[a] -= nz * half
				PX[b] += nx * half
				PZ[b] += nz * half
			for b: int in range(p, q_end):
				var dx: float = X[b] - ax
				var dz: float = Z[b] - az
				var lim: float = (ra + R[b]) * reach - SLOP
				var d2: float = dx * dx + dz * dz
				if d2 >= lim * lim or (skip_enemies and O[b] != oa):
					continue
				overlaps += 1
				var dd: float = sqrt(d2)
				var nx: float = 1.0
				var nz: float = 0.0
				if dd > 0.0001:
					nx = dx / dd
					nz = dz / dd
				else:
					var ang: float = _tie_angle(_keys[set][a], _keys[set][b])
					nx = cos(ang)
					nz = sin(ang)
				var half: float = (lim + 2.0 * SLOP - dd) * PUSH_FACTOR * 0.5
				PX[a] -= nx * half
				PZ[a] -= nz * half
				PX[b] += nx * half
				PZ[b] += nz * half
		i = e
	_pairs += pairs
	_overlaps += overlaps


## Aplica el empuje acumulado del conjunto (en el orden de las claves) sin entrar en terreno
## prohibido y sin salir de los límites.
func _apply(store: EntityStore, map: LogicMap, set: int) -> void:
	var keys: PackedInt64Array = _keys[set]
	var m: int = keys.size()
	var X: PackedFloat64Array = _x[set]
	var Z: PackedFloat64Array = _z[set]
	var PX: PackedFloat64Array = _px[set]
	var PZ: PackedFloat64Array = _pz[set]
	var px := store.pos_x
	var pz := store.pos_z
	var has_map: bool = map != null
	var table: PackedFloat32Array = map.cost_tables[Terrain.Layer.LAND] if has_map else PackedFloat32Array()
	const HALF: float = MapGrid.MAP_HALF
	const INV_CELL: float = 1.0 / MapGrid.TERRAIN_CELL
	const SM: int = SpatialGrid.SLOT_MASK
	var min_x: float = _bounds.position.x
	var min_z: float = _bounds.position.y
	var max_x: float = _bounds.end.x
	var max_z: float = _bounds.end.y
	for k: int in m:
		var mx: float = PX[k]
		var mz: float = PZ[k]
		if mx == 0.0 and mz == 0.0:
			continue
		var len2: float = mx * mx + mz * mz
		if len2 > MAX_PUSH * MAX_PUSH:
			var f: float = MAX_PUSH / sqrt(len2)
			mx *= f
			mz *= f
		var ox: float = X[k]
		var oz: float = Z[k]
		var nx: float = clampf(ox + mx, min_x, max_x)
		var nz: float = clampf(oz + mz, min_z, max_z)
		if has_map:
			var ogx: int = int((ox + HALF) * INV_CELL)
			var ogz: int = int((oz + HALF) * INV_CELL)
			var ngx: int = int((nx + HALF) * INV_CELL)
			var ngz: int = int((nz + HALF) * INV_CELL)
			if (ngx != ogx or ngz != ogz) and table[map.cell_byte(ngx, ngz)] <= 0.0:
				if ngx != ogx and table[map.cell_byte(ngx, ogz)] > 0.0:
					nz = oz
				elif ngz != ogz and table[map.cell_byte(ogx, ngz)] > 0.0:
					nx = ox
				else:
					continue
		var s: int = keys[k] & SM
		px[s] = nx
		pz[s] = nz


## Dirección de separación de dos unidades en el mismo punto: sale de sus claves (celda, dueño y
## slot; deterministas).
static func _tie_angle(ka: int, kb: int) -> float:
	var h: int = ((ka & 0xFFFFF) * 7919 + (kb & 0xFFFFF) * 104729) % 4096
	return float(h) * (TAU / 4096.0)
