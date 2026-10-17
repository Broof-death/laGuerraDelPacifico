class_name TargetAcquisitionSystem
extends RefCounted
## Adquisición de objetivos a 5 Hz escalonada (ADR-006 punto 1): cada tick procesa una de las
## SimConstants.SLOW_PHASES partes de los slots, así que cada entidad se revisa cada 4 ticks.
##
## Reglas:
## - Un objetivo se conserva mientras siga vivo, sea enemigo y esté dentro de vision_range
##   (como en un RTS clásico; evita recalcular a las unidades que ya combaten).
## - Si no tiene objetivo válido, toma el enemigo más cercano entre los CANDIDATES_PER_CELL
##   enemigos más próximos a su celda. Los candidatos se calculan una sola vez por (celda, dueño)
##   y tick, recorriendo la SpatialGrid en anillos de celdas alrededor de la celda y saltando de
##   una vez a todos los aliados de cada celda (SpatialGrid.run_end). En celdas muy densas el
##   resultado es aproximado (el más cercano entre los primeros candidatos hallados, que están
##   en la misma celda o en el anillo más próximo que tenga enemigos).
## - Enemigo = otro dueño distinto de neutral (los equipos llegan con su mecánica).
## Escribe store.target_id (0 = ninguno). Todavía no dispara: el combate es de otra tarea.

## Máximo de enemigos candidatos que se guardan por (celda, dueño).
const CANDIDATES_PER_CELL: int = 24

# Caché del tick: (celda << 4 | dueño) -> ids de enemigos candidatos.
var _cache: Dictionary[int, PackedInt32Array] = {}


## phase en [0, phases): rango de slots que toca este tick.
func run(store: EntityStore, grid: SpatialGrid, vision_by_def: PackedFloat32Array, phase: int, phases: int) -> void:
	var n: int = store.count
	if n == 0:
		return
	_cache.clear()
	var from: int = (n * phase) / phases
	var to: int = (n * (phase + 1)) / phases
	var owner := store.owner
	var ids := store.id
	var defs := store.def_index
	var targets := store.target_id
	var cells := store.cell
	var px := store.pos_x
	var pz := store.pos_z
	var id_to_slot := store.id_to_slot
	var id_limit: int = id_to_slot.size()
	var max_vision: float = 0.0
	for v: float in vision_by_def:
		max_vision = maxf(max_vision, v)
	var max_ring: int = ceili(max_vision / grid.cell_size)
	const NEUTRAL: int = SimConstants.NEUTRAL_PLAYER
	const NONE: int = SimConstants.NO_ENTITY

	for s: int in range(from, to):
		var own: int = owner[s]
		if own == NEUTRAL:
			continue
		var r: float = vision_by_def[defs[s]]
		var r2: float = r * r
		var x: float = px[s]
		var z: float = pz[s]

		# 1) Conservar el objetivo actual si sigue siendo válido.
		var t: int = targets[s]
		if t > NONE and t < id_limit:
			var ts: int = id_to_slot[t]
			if ts >= 0 and owner[ts] != own:
				var tdx: float = px[ts] - x
				var tdz: float = pz[ts] - z
				if tdx * tdx + tdz * tdz <= r2:
					continue

		# 2) El más cercano entre los candidatos de su celda.
		var key: int = (cells[s] << 4) | own
		var cands: PackedInt32Array
		if _cache.has(key):
			cands = _cache[key]
		else:
			cands = _collect_candidates(grid, ids, cells[s], own, max_ring)
			_cache[key] = cands
		var best: int = NONE
		var best_d2: float = r2
		for cid: int in cands:
			var o: int = id_to_slot[cid]
			var dx: float = px[o] - x
			var dz: float = pz[o] - z
			var d2: float = dx * dx + dz * dz
			if d2 < best_d2 or (d2 == best_d2 and best != NONE and cid < best):
				best_d2 = d2
				best = cid
		targets[s] = best


## Hasta CANDIDATES_PER_CELL ids de enemigos de `own`, recorriendo anillos de celdas desde `cell`.
static func _collect_candidates(grid: SpatialGrid, ids: PackedInt32Array, cell: int, own: int, max_ring: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var keys := grid.keys
	var cols: int = grid.cols
	var rows: int = grid.rows
	var cx: int = cell % cols
	var cz: int = cell / cols
	for k: int in max_ring + 1:
		var a: int = maxi(cx - k, 0)
		var b: int = mini(cx + k, cols - 1)
		# Filas superior e inferior del anillo (completas) y columnas laterales (sin esquinas):
		# tríos (fila, cx0, cx1).
		var segments := PackedInt32Array()
		if cz - k >= 0:
			segments.append_array([cz - k, a, b])
		if k > 0 and cz + k < rows:
			segments.append_array([cz + k, a, b])
		if k > 0:
			for row: int in range(maxi(cz - k + 1, 0), mini(cz + k - 1, rows - 1) + 1):
				if cx - k >= 0:
					segments.append_array([row, cx - k, cx - k])
				if cx + k < cols:
					segments.append_array([row, cx + k, cx + k])
		for j: int in range(0, segments.size(), 3):
			var rr: Vector2i = grid.row_range(segments[j], segments[j + 1], segments[j + 2])
			var i: int = rr.x
			while i < rr.y:
				var kv: int = keys[i]
				var ow: int = (kv >> SpatialGrid.OWNER_SHIFT) & SpatialGrid.OWNER_MASK
				if ow == own or ow == SimConstants.NEUTRAL_PLAYER:
					i = grid.run_end(i)
					continue
				out.append(ids[kv & SpatialGrid.SLOT_MASK])
				if out.size() >= CANDIDATES_PER_CELL:
					return out
				i += 1
	return out
