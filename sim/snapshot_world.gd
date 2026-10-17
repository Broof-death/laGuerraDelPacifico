class_name SnapshotWorld
extends RefCounted
## Foto cuantizada de todas las entidades, tomada UNA vez por ciclo de snapshots y compartida por
## todos los clientes (ADR-006 punto 5: "cada entidad se cuantiza una vez por ciclo").
## Arrays paralelos ordenados por id (para el delta por mezcla contra la base de cada cliente).
##
## Gestión de interés PROVISIONAL (hasta que T-014 implemente la visibilidad por equipo en celdas
## de 32 m): un jugador ve las celdas de INTEREST_CELL m (256 m = 4 x 4 celdas de 64 m de la
## SpatialGrid) que están a menos del mayor vision_range de alguna celda donde tiene entidades.
## vis[i] es la máscara de jugadores (bit player_id) que ven la entidad i. Es más generosa que la
## visión real (hasta ~256 m de más), nunca más estricta.

const INTEREST_CELL_SHIFT: int = 2  # 4 x 4 celdas de 64 m
## Multiplicador de fila de las celdas de interés (cubre la rejilla del mundo entero).
const INTEREST_SIDE: int = MapGrid.GRID_CELLS_PER_SIDE >> INTEREST_CELL_SHIFT

## Tick de la simulación en que se tomó (el que llevan los snapshots).
var tick: int = -1
var count: int = 0
var ids := PackedInt32Array()
var words := PackedInt64Array()
## Velocidad cuantizada (SnapshotCodec.pack_vel).
var vel := PackedInt32Array()
var prog := PackedByteArray()
var def_index := PackedInt32Array()
var owner := PackedInt32Array()
## 1 si la entidad está en combate (tiene objetivo): su antigüedad pesa el doble.
var combat := PackedByteArray()
var vis := PackedInt32Array()

var _keys := PackedInt64Array()


## Cuantiza el estado actual de la simulación. Usa store.cell (la escribe SpatialGrid.rebuild en
## cada step()), así que debe llamarse después de step().
func capture(sim: Simulation) -> void:
	var st := sim.store
	var n: int = st.count
	tick = sim.tick
	count = n
	ids.resize(n)
	words.resize(n)
	vel.resize(n)
	prog.resize(n)
	def_index.resize(n)
	owner.resize(n)
	combat.resize(n)
	vis.resize(n)

	# Orden por id: clave (id << 16) | slot, ordenada en nativo.
	_keys.resize(n)
	var sid := st.id
	for s: int in n:
		_keys[s] = (sid[s] << 16) | s
	_keys.sort()

	var visible_by_coarse: Dictionary[int, int] = _interest(sim)
	var px := st.pos_x
	var pz := st.pos_z
	var hd := st.heading
	var vxs := st.vel_x
	var vzs := st.vel_z
	const VINV: float = 1.0 / SnapshotCodec.VEL_STEP
	const VL: int = SnapshotCodec.VEL_LIMIT
	var hp := st.hp
	var act := st.action
	var prg := st.progress
	var defs := st.def_index
	var own := st.owner
	var tgt := st.target_id
	var cells := st.cell
	var max_hp := sim.max_hp_by_def
	const HALF: float = MapGrid.MAP_HALF
	const INV: float = MapGrid.QUANT_INV_STEP
	const QMAX: int = MapGrid.QUANT_MAX
	const HSCALE: float = 256.0 / TAU
	var side: int = sim.grid.cols
	const SH: int = INTEREST_CELL_SHIFT
	const ISIDE: int = INTEREST_SIDE
	for i: int in n:
		var s: int = _keys[i] & 0xFFFF
		var d: int = defs[s]
		var qx: int = clampi(int(floor((px[s] + HALF) * INV)), 0, QMAX)
		var qz: int = clampi(int(floor((pz[s] + HALF) * INV)), 0, QMAX)
		var h8: int = int(roundf(hd[s] * HSCALE)) & 0xFF
		var mh: float = max_hp[d]
		var hp8: int = clampi(int(roundf(hp[s] / mh * 255.0)), 0, 255) if mh > 0.0 else 0
		if hp8 == 0 and hp[s] > 0.0:
			hp8 = 1
		var a: int = act[s]
		ids[i] = sid[s]
		words[i] = qx | (qz << 20) | (h8 << 40) | (hp8 << 48) | (a << 56)
		var vx8: int = clampi(int(roundf(vxs[s] * VINV)), -VL, VL)
		var vz8: int = clampi(int(roundf(vzs[s] * VINV)), -VL, VL)
		vel[i] = (vx8 & 0xFF) | ((vz8 & 0xFF) << 8)
		prog[i] = SnapshotCodec.quantize_progress(prg[s]) if SnapshotCodec.action_uses_progress(a) else 0
		def_index[i] = d
		owner[i] = own[s]
		combat[i] = 1 if tgt[s] != 0 else 0
		var c: int = cells[s]
		vis[i] = visible_by_coarse.get(((c / side) >> SH) * ISIDE + ((c % side) >> SH), 0)


## Celda de interés -> máscara de jugadores que la ven.
func _interest(sim: Simulation) -> Dictionary[int, int]:
	var grid := sim.grid
	var keys := grid.keys
	var cols: int = grid.cols
	var max_vision: float = 0.0
	for v: float in sim.vision_by_def:
		max_vision = maxf(max_vision, v)
	var interest_size: float = grid.cell_size * (1 << INTEREST_CELL_SHIFT)
	var ring: int = ceili(max_vision / interest_size)
	var rows_i: int = ((grid.rows - 1) >> INTEREST_CELL_SHIFT) + 1
	var cols_i: int = ((cols - 1) >> INTEREST_CELL_SHIFT) + 1
	# 1) Celdas de interés ocupadas por cada dueño (las claves vienen ordenadas por celda y dueño).
	var occupied: Dictionary[int, bool] = {}
	var last: int = -1
	for k: int in keys:
		var cell_owner: int = k >> SpatialGrid.OWNER_SHIFT
		if cell_owner == last:
			continue
		last = cell_owner
		var own: int = cell_owner & SpatialGrid.OWNER_MASK
		if own == SimConstants.NEUTRAL_PLAYER:
			continue
		var c: int = cell_owner >> 4
		var coarse: int = ((c / cols) >> INTEREST_CELL_SHIFT) * INTEREST_SIDE + ((c % cols) >> INTEREST_CELL_SHIFT)
		occupied[(coarse << 4) | own] = true
	# 2) Marcar el entorno de cada celda ocupada.
	var out: Dictionary[int, int] = {}
	for key: int in occupied:
		var own: int = key & 0xF
		var coarse: int = key >> 4
		var cz: int = coarse / INTEREST_SIDE
		var cx: int = coarse % INTEREST_SIDE
		var bit: int = 1 << own
		for z: int in range(maxi(cz - ring, 0), mini(cz + ring, rows_i - 1) + 1):
			for x: int in range(maxi(cx - ring, 0), mini(cx + ring, cols_i - 1) + 1):
				var ck: int = z * INTEREST_SIDE + x
				out[ck] = out.get(ck, 0) | bit
	return out
