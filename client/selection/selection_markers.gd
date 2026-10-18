class_name SelectionMarkers
extends Node3D
## Respuesta visual de la selección y de las órdenes (T-007). Solo cliente.
## - Anillos bajo las entidades seleccionadas: UN MultiMesh (un anillo por entidad, color por
##   instancia), reescrito cada frame con las posiciones dibujadas de ClientState.
## - Marcador de destino de cada orden: un anillo que se cierra y se desvanece. Es la respuesta
##   cosmética e inmediata de ADR-006 (punto 6): se mantiene mientras el servidor no confirma el
##   comando (last_seq) y se apaga después de FADE_TIME.

const RING_Y: float = 0.08
const MAX_DEST_MARKERS: int = 12
const FADE_TIME: float = 0.9
## Si la confirmación no llega en este tiempo, el marcador se apaga igual.
const MAX_WAIT: float = 3.0
const COLOR_OWN := Color(0.35, 1.0, 0.45)
const COLOR_FOREIGN := Color(1.0, 0.3, 0.25)
const COLOR_MOVE := Color(0.35, 1.0, 0.45)
const COLOR_ATTACK := Color(1.0, 0.25, 0.2)
const COLOR_ATTACK_MOVE := Color(1.0, 0.6, 0.15)
const COLOR_REJECTED := Color(0.6, 0.6, 0.6)

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _dest: Array[MeshInstance3D] = []
var _dest_age := PackedFloat32Array()
var _dest_seq := PackedInt32Array()
var _dest_color: Array[Color] = []
var _next_dest: int = 0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := _ring_mesh(0.78, 1.0)
	ring.surface_set_material(0, mat)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = ring
	_mm.custom_aabb = UnitBatchRenderer.WORLD_AABB
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Anillos"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	var dest_mesh := _ring_mesh(0.75, 1.0)
	for i: int in MAX_DEST_MARKERS:
		var mi := MeshInstance3D.new()
		mi.name = "Destino%d" % i
		mi.mesh = dest_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_dest.append(mi)
		_dest_color.append(Color.WHITE)
	_dest_age.resize(MAX_DEST_MARKERS)
	_dest_seq.resize(MAX_DEST_MARKERS)


## Reescribe los anillos de la selección (radio según query.radius_of por def_index).
func update_rings(state: ClientState, selection: UnitSelection, query: SelectionQuery) -> void:
	if _mm == null:
		return
	var ids := selection.ids()
	var n: int = 0
	if _buf.size() < ids.size() * 16:
		_buf.resize(maxi(64, ids.size()) * 16)
	var color: Color = COLOR_FOREIGN if selection.inspecting else COLOR_OWN
	for id: int in ids:
		var s: int = state.slot_of(id)
		if s < 0:
			continue
		var r: float = query.radius_of(state.def_index[s]) * 1.3 + 0.6
		var i: int = n * 16
		_buf[i] = r; _buf[i + 1] = 0.0; _buf[i + 2] = 0.0; _buf[i + 3] = state.render_x[s]
		_buf[i + 4] = 0.0; _buf[i + 5] = 1.0; _buf[i + 6] = 0.0; _buf[i + 7] = RING_Y
		_buf[i + 8] = 0.0; _buf[i + 9] = 0.0; _buf[i + 10] = r; _buf[i + 11] = state.render_z[s]
		_buf[i + 12] = color.r; _buf[i + 13] = color.g; _buf[i + 14] = color.b; _buf[i + 15] = 1.0
		n += 1
	if n > _mm.instance_count:
		_mm.instance_count = maxi(64, nearest_po2(n))
	var slice := _buf.slice(0, n * 16)
	slice.resize(_mm.instance_count * 16)
	_mm.buffer = slice
	_mm.visible_instance_count = n
	_mmi.visible = n > 0


## Muestra un marcador de destino en (x, z) para el comando `seq`.
func show_destination(pos: Vector2, color: Color, seq: int, radius: float = 3.0) -> void:
	if _dest.is_empty():
		return
	var k: int = _next_dest
	_next_dest = (_next_dest + 1) % MAX_DEST_MARKERS
	var mi := _dest[k]
	mi.position = Vector3(pos.x, RING_Y + 0.02, pos.y)
	mi.set_meta(&"radius", radius)
	mi.visible = true
	_dest_age[k] = 0.0
	_dest_seq[k] = seq
	_dest_color[k] = color


## Marca como rechazados los marcadores del comando `seq` (se apagan en gris).
func reject(seq: int) -> void:
	for k: int in MAX_DEST_MARKERS:
		if _dest[k].visible and _dest_seq[k] == seq:
			_dest_color[k] = COLOR_REJECTED


## Anima los marcadores. `confirmed_seq` = último comando que el servidor confirmó.
func update_destinations(delta: float, confirmed_seq: int) -> void:
	for k: int in MAX_DEST_MARKERS:
		var mi := _dest[k]
		if not mi.visible:
			continue
		var pending: bool = _dest_seq[k] > confirmed_seq and _dest_age[k] < MAX_WAIT
		if pending:
			# Mientras no se confirma, el marcador no pasa del 30 % de su animación.
			_dest_age[k] = minf(_dest_age[k] + delta, FADE_TIME * 0.3)
		else:
			_dest_age[k] += delta
		var t: float = clampf(_dest_age[k] / FADE_TIME, 0.0, 1.0)
		if t >= 1.0:
			mi.visible = false
			continue
		var r: float = float(mi.get_meta(&"radius", 3.0)) * lerpf(1.6, 0.6, t)
		mi.scale = Vector3(r, 1.0, r)
		var c: Color = _dest_color[k]
		c.a = 1.0 - t * t
		(mi.material_override as StandardMaterial3D).albedo_color = c


## Cantidad de anillos dibujados (para pruebas y capturas).
func ring_count() -> int:
	return _mm.visible_instance_count if _mm != null else 0


## Anillo plano en y = 0, de radio interior `inner` y exterior `outer` (escala 1 = 1 m).
static func _ring_mesh(inner: float, outer: float, segments: int = 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segments:
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		st.set_normal(Vector3.UP)
		st.add_vertex(i0); st.add_vertex(i1); st.add_vertex(o0)
		st.add_vertex(o0); st.add_vertex(i1); st.add_vertex(o1)
	return st.commit()
