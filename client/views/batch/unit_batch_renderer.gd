class_name UnitBatchRenderer
extends Node3D
## Dibuja todas las entidades de un ClientState (ADR-006 punto 7, ADR-010 puntos 5 y 6). Solo
## cliente. En cada frame, después de que MatchClient interpola, lee render_x/render_z/
## render_heading y:
## 1. Recorta en CPU contra el frustum de la cámara (Godot recorta un MultiMesh entero, no cada
##    instancia: ADR-010 punto 6).
## 2. Elige el nivel por distancia a la cámara: < 150 m malla completa, 150 m - 1,5 km malla
##    simplificada, > 1,5 km impostor (quad horizontal que crece con la distancia para seguir
##    viéndose como unos 3 px).
## 3. Da una vista individual (EntityViewPool, como máximo 256) a lo más cercano: las unidades
##    a < 150 m y los buques y edificios hasta 1,5 km, por orden de distancia. Esas entidades no
##    se dibujan en los lotes. Las vistas a < 60 m muestran etiqueta y barra de vida.
## 4. Escribe el buffer completo de cada MultiMesh (uno por def_index, jugador y nivel) de una
##    vez y ajusta visible_instance_count. Color de bando por instancia.
##
## Solo sombras en el nivel completo (lo cercano); el resto no proyecta sombra.
## La altura es y = 0 (tropas sobre el suelo, buques con la flotación en 0) hasta que exista
## TerrainView (ADR-010 punto 1).

const LOD_NEAR: float = 150.0
const LOD_FAR: float = 1500.0
const DETAIL_DISTANCE: float = 60.0
## Tamaño mínimo del impostor en metros por metro de distancia (~3 px a 1080p con fov 50°).
const IMPOSTOR_SIZE_PER_METER: float = 0.0026
## Floats por instancia en el buffer: transformación 3x4 + color.
const STRIDE: int = 16
const OWNER_SLOTS: int = 16
const LODS: int = 3
## AABB fija de los lotes: el recorte se hace en CPU, así Godot no recalcula la AABB del buffer.
const WORLD_AABB := AABB(Vector3(-MapGrid.MAP_HALF, -200.0, -MapGrid.MAP_HALF), Vector3(MapGrid.MAP_SIZE, 1200.0, MapGrid.MAP_SIZE))

var state: ClientState
var catalog: ViewCatalog
## Color por player_id (ver TeamColors).
var owner_colors: PackedColorArray
var pool: EntityViewPool
## false = todo por lotes, sin vistas individuales.
var use_pool: bool = true
## Si es true, se actualiza solo en _process (process_priority alta, después de Match).
var auto_update: bool = true
## Cámara a usar; null = la cámara activa del viewport.
var camera: Camera3D

## Estadísticas del último refresh().
var stat_visible: int = 0
var stat_lod := PackedInt32Array([0, 0, 0])
var stat_pooled: int = 0
var stat_batches_drawn: int = 0
var last_update_usec: int = 0

# Grupo g = (def_index, jugador); lote b = g * LODS + nivel.
var _group_of := PackedInt32Array()
var _mm: Array[MultiMesh] = []
var _mmi: Array[MultiMeshInstance3D] = []
var _b_color := PackedFloat32Array()
# Tablas por def_index.
var _def_radius := PackedFloat32Array()
var _def_prefers := PackedByteArray()
var _def_foot_x := PackedFloat32Array()
var _def_foot_z := PackedFloat32Array()
var _def_foot_max := PackedFloat32Array()
# Memoria de trabajo reutilizada entre frames.
var _bucket := PackedInt32Array()
var _dist := PackedFloat32Array()
var _buf := PackedFloat32Array()
var _counts := PackedInt32Array()
var _cursor := PackedInt32Array()
var _views_root: Node3D


func _ready() -> void:
	process_priority = 100


func _exit_tree() -> void:
	if pool != null:
		pool.release_all()
	PlaceholderView.clear_cache()
	EntityView.clear_cache()


## Conecta el renderizador a un estado de cliente. `colors` vacío = TeamColors.default_palette().
func setup(p_state: ClientState, p_catalog: ViewCatalog, colors: PackedColorArray = PackedColorArray(),
		max_views: int = EntityViewPool.DEFAULT_MAX_VIEWS) -> void:
	state = p_state
	catalog = p_catalog
	owner_colors = colors if not colors.is_empty() else TeamColors.default_palette()
	if _views_root == null:
		_views_root = Node3D.new()
		_views_root.name = "Vistas"
		add_child(_views_root)
	pool = EntityViewPool.new(_views_root, _create_view, max_views)


func _process(_delta: float) -> void:
	if auto_update and state != null:
		refresh()


## Nivel de detalle para una distancia a la cámara.
static func lod_for_distance(dist: float) -> PlaceholderMeshes.Lod:
	if dist < LOD_NEAR:
		return PlaceholderMeshes.Lod.FULL
	if dist < LOD_FAR:
		return PlaceholderMeshes.Lod.SIMPLE
	return PlaceholderMeshes.Lod.IMPOSTOR


## Escala del impostor: la huella real o, si se vería más chica que ~3 px, más grande.
static func impostor_scale(footprint_max: float, dist: float) -> float:
	return maxf(1.0, dist * IMPOSTOR_SIZE_PER_METER / maxf(footprint_max, 0.01))


## Actualiza vistas y lotes con el estado actual. Lo llama _process (o la prueba de carga).
func refresh() -> void:
	var t0: int = Time.get_ticks_usec()
	var cam: Camera3D = camera if camera != null else get_viewport().get_camera_3d()
	if cam == null or state == null:
		return
	var n: int = state.count
	if _bucket.size() < n:
		var cap: int = maxi(256, n * 2)
		_bucket.resize(cap)
		_dist.resize(cap)
		_buf.resize(cap * STRIDE)

	# Planos del frustum (normales hacia fuera): fuera si n·p - d > radio.
	var planes: Array[Plane] = cam.get_frustum()
	if planes.size() < 6:
		return
	var a0: float = planes[0].normal.x; var b0: float = planes[0].normal.y; var c0: float = planes[0].normal.z; var d0: float = planes[0].d
	var a1: float = planes[1].normal.x; var b1: float = planes[1].normal.y; var c1: float = planes[1].normal.z; var d1: float = planes[1].d
	var a2: float = planes[2].normal.x; var b2: float = planes[2].normal.y; var c2: float = planes[2].normal.z; var d2: float = planes[2].d
	var a3: float = planes[3].normal.x; var b3: float = planes[3].normal.y; var c3: float = planes[3].normal.z; var d3: float = planes[3].d
	var a4: float = planes[4].normal.x; var b4: float = planes[4].normal.y; var c4: float = planes[4].normal.z; var d4: float = planes[4].d
	var a5: float = planes[5].normal.x; var b5: float = planes[5].normal.y; var c5: float = planes[5].normal.z; var d5: float = planes[5].d
	var cam_pos: Vector3 = cam.global_position
	var cx: float = cam_pos.x
	var cy: float = cam_pos.y
	var cz: float = cam_pos.z
	# Centro aproximado de las entidades sobre el suelo.
	const Y: float = 1.0

	var defs := state.def_index
	var owners := state.owner
	var rx := state.render_x
	var rz := state.render_z
	var bucket := _bucket
	_bucket = PackedInt32Array()
	var dist_arr := _dist
	_dist = PackedFloat32Array()
	var counts := _counts
	_counts = PackedInt32Array()
	counts.resize(_mm.size())
	counts.fill(0)
	var group_of := _group_of
	var rad := _def_radius
	var prefers := _def_prefers
	var candidates := PackedInt64Array()
	var with_pool: bool = use_pool and pool != null
	var visible_count: int = 0

	for s: int in n:
		var d: int = defs[s]
		var key: int = d * OWNER_SLOTS + (owners[s] & (OWNER_SLOTS - 1))
		var g: int = group_of[key] if key < group_of.size() else -1
		if g == -1:
			g = _create_group(d, owners[s])
			group_of = _group_of
			rad = _def_radius
			prefers = _def_prefers
			var prev: int = counts.size()
			counts.resize(_mm.size())
			for k: int in range(prev, counts.size()):
				counts[k] = 0
		if g < 0:
			bucket[s] = -1
			continue
		var x: float = rx[s]
		var z: float = rz[s]
		var r: float = rad[d]
		if a0 * x + b0 * Y + c0 * z - d0 > r or a1 * x + b1 * Y + c1 * z - d1 > r \
				or a2 * x + b2 * Y + c2 * z - d2 > r or a3 * x + b3 * Y + c3 * z - d3 > r \
				or a4 * x + b4 * Y + c4 * z - d4 > r or a5 * x + b5 * Y + c5 * z - d5 > r:
			bucket[s] = -1
			continue
		var dx: float = x - cx
		var dy: float = Y - cy
		var dz: float = z - cz
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		var lod: int = 0 if dist < LOD_NEAR else (1 if dist < LOD_FAR else 2)
		if with_pool and (lod == 0 or (lod == 1 and prefers[d] == 1)):
			candidates.append((int(dist * 8.0) << 32) | s)
		var b: int = g * LODS + lod
		bucket[s] = b
		counts[b] += 1
		dist_arr[s] = dist
		visible_count += 1

	# Vistas individuales para lo más cercano.
	var pooled: int = 0
	if with_pool:
		if candidates.size() > pool.max_views:
			candidates.sort()
			candidates.resize(pool.max_views)
		var ids := state.ids
		var keep: Dictionary = {}
		for c: int in candidates:
			keep[ids[c & 0xFFFFFFFF]] = true
		pool.release_except(keep)
		var rh := state.render_heading
		var act := state.action
		var hp := state.hp_ratio
		var prog := state.progress
		for c: int in candidates:
			var s: int = c & 0xFFFFFFFF
			var o: int = owners[s]
			var v: EntityView = pool.acquire(ids[s], defs[s], _owner_color(o))
			if v == null:
				continue
			counts[bucket[s]] -= 1
			bucket[s] = -1
			pooled += 1
			v.position = Vector3(rx[s], 0.0, rz[s])
			v.rotation = Vector3(0.0, rh[s], 0.0)
			var near: bool = dist_arr[s] < DETAIL_DISTANCE
			if near != v.details_visible:
				v.set_details_visible(near)
			v.apply_state(act[s], hp[s], prog[s])

	# Inicio de cada lote en el buffer (counting sort).
	var nb: int = _mm.size()
	var cursor := _cursor
	_cursor = PackedInt32Array()
	cursor.resize(nb)
	var acc: int = 0
	for b: int in nb:
		cursor[b] = acc
		acc += counts[b]
	var starts := cursor.duplicate()

	var buf := _buf
	_buf = PackedFloat32Array()
	var rh2 := state.render_heading
	var col := _b_color
	var foot_x := _def_foot_x
	var foot_z := _def_foot_z
	var foot_max := _def_foot_max
	const K: float = IMPOSTOR_SIZE_PER_METER
	for s: int in n:
		var b: int = bucket[s]
		if b < 0:
			continue
		var i: int = cursor[b] * STRIDE
		cursor[b] += 1
		var h: float = rh2[s]
		var co: float = cos(h)
		var si: float = sin(h)
		var sx: float = 1.0
		var sz: float = 1.0
		if b % LODS == 2:
			var d: int = defs[s]
			var f: float = maxf(1.0, dist_arr[s] * K / foot_max[d])
			sx = foot_x[d] * f
			sz = foot_z[d] * f
		buf[i] = co * sx
		buf[i + 1] = 0.0
		buf[i + 2] = si * sz
		buf[i + 3] = rx[s]
		buf[i + 4] = 0.0
		buf[i + 5] = 1.0
		buf[i + 6] = 0.0
		buf[i + 7] = 0.0
		buf[i + 8] = -si * sx
		buf[i + 9] = 0.0
		buf[i + 10] = co * sz
		buf[i + 11] = rz[s]
		var bc: int = b * 4
		buf[i + 12] = col[bc]
		buf[i + 13] = col[bc + 1]
		buf[i + 14] = col[bc + 2]
		buf[i + 15] = col[bc + 3]

	# Subida: un buffer completo por lote.
	var drawn: int = 0
	var lod_counts := PackedInt32Array([0, 0, 0])
	for b: int in nb:
		var c: int = counts[b]
		var mmi: MultiMeshInstance3D = _mmi[b]
		if c <= 0:
			if mmi.visible:
				mmi.visible = false
			continue
		lod_counts[b % LODS] += c
		var mm: MultiMesh = _mm[b]
		if c > mm.instance_count:
			mm.instance_count = maxi(64, nearest_po2(c))
		var slice := buf.slice(starts[b] * STRIDE, (starts[b] + c) * STRIDE)
		slice.resize(mm.instance_count * STRIDE)
		mm.buffer = slice
		mm.visible_instance_count = c
		if not mmi.visible:
			mmi.visible = true
		drawn += 1

	_bucket = bucket
	_dist = dist_arr
	_counts = counts
	_cursor = cursor
	_buf = buf
	stat_visible = visible_count
	stat_lod = lod_counts
	stat_pooled = pooled
	stat_batches_drawn = drawn
	last_update_usec = Time.get_ticks_usec() - t0


func get_stats() -> Dictionary:
	return {
		"visible": stat_visible,
		"lod_full": stat_lod[0],
		"lod_simple": stat_lod[1],
		"lod_impostor": stat_lod[2],
		"pooled_views": stat_pooled,
		"pool_total": pool.total if pool != null else 0,
		"batches_drawn": stat_batches_drawn,
		"batches_total": _mm.size(),
		"update_usec": last_update_usec,
	}


func _owner_color(o: int) -> Color:
	return owner_colors[o] if o >= 0 and o < owner_colors.size() else TeamColors.color_for_player(o)


func _create_view(def_index: int, team_color: Color) -> EntityView:
	return catalog.create_view(def_index, team_color)


## Crea los lotes de (def_index, jugador). Devuelve el grupo, o -2 si el def_index no existe.
func _create_group(d: int, o: int) -> int:
	var key: int = d * OWNER_SLOTS + (o & (OWNER_SLOTS - 1))
	if _group_of.size() <= key:
		var old: int = _group_of.size()
		_group_of.resize(key + OWNER_SLOTS)
		for k: int in range(old, _group_of.size()):
			_group_of[k] = -1
	var e: ViewCatalog.Entry = catalog.entry(d) if catalog != null else null
	if e == null:
		_group_of[key] = -2
		return -2
	if _def_radius.size() <= d:
		_def_radius.resize(d + 1)
		_def_prefers.resize(d + 1)
		_def_foot_x.resize(d + 1)
		_def_foot_z.resize(d + 1)
		_def_foot_max.resize(d + 1)
	_def_radius[d] = e.cull_radius
	_def_prefers[d] = 1 if e.prefers_view else 0
	_def_foot_x[d] = e.footprint.x
	_def_foot_z[d] = e.footprint.y
	_def_foot_max[d] = maxf(e.footprint.x, e.footprint.y)
	var g: int = _mm.size() / LODS
	var color: Color = _owner_color(o)
	for lod: int in LODS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = e.meshes[lod]
		mm.custom_aabb = WORLD_AABB
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lote_%s_j%d_%s" % [e.def.id, o, PlaceholderMeshes.Lod.keys()[lod]]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
		_mm.append(mm)
		_mmi.append(mmi)
		_b_color.append(color.r)
		_b_color.append(color.g)
		_b_color.append(color.b)
		_b_color.append(color.a)
	_group_of[key] = g
	return g
