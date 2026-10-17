class_name PlaceholderMeshes
extends RefCounted
## Mallas de la representación provisional (ADR-005, ADR-007: placeholder_shape/size) y utilidades
## de malla compartidas por las vistas individuales y el renderizador por lotes. Solo cliente.
##
## Convenciones: el frente de la unidad es +Z (la simulación usa rumbo = atan2(dx, dz)).
## Tropas y edificios apoyan la base en y = 0. Los cascos (HULL) tienen la línea de flotación en
## y = 0 y el 40 % de la altura bajo el agua.

## Nivel de detalle de las mallas por lotes (ADR-006 punto 7).
enum Lod {
	FULL,      ## < 150 m: malla completa
	SIMPLE,    ## 150 m - 1,5 km: malla simplificada
	IMPOSTOR,  ## > 1,5 km: un quad por unidad
}

## Fracción de la altura del casco que queda bajo la línea de flotación.
const HULL_DRAFT: float = 0.4
## Altura del quad del impostor sobre el suelo (para que no parpadee con el terreno).
const IMPOSTOR_Y: float = 0.3


## Malla provisional de una forma, con la base (o la flotación) en y = 0. Sin material.
static func build(shape: EntityDef.PlaceholderShape, size: Vector3, lod: Lod) -> ArrayMesh:
	size = size.max(Vector3(0.05, 0.05, 0.05))
	if lod == Lod.IMPOSTOR:
		return impostor()
	var full: bool = lod == Lod.FULL
	match shape:
		EntityDef.PlaceholderShape.CAPSULE:
			var m := CapsuleMesh.new()
			m.radius = minf(size.x, size.z) * 0.5
			m.height = maxf(size.y, m.radius * 2.0)
			m.radial_segments = 12 if full else 6
			m.rings = 3 if full else 1
			return bake(m, Transform3D(Basis.IDENTITY, Vector3(0.0, m.height * 0.5, 0.0)))
		EntityDef.PlaceholderShape.CYLINDER:
			var m := CylinderMesh.new()
			m.top_radius = minf(size.x, size.z) * 0.5
			m.bottom_radius = m.top_radius
			m.height = size.y
			m.radial_segments = 12 if full else 6
			m.rings = 0
			# Achatado en x/z si la huella no es cuadrada.
			var sc := Vector3(size.x / (m.top_radius * 2.0), 1.0, size.z / (m.top_radius * 2.0))
			return bake(m, Transform3D(Basis.from_scale(sc), Vector3(0.0, size.y * 0.5, 0.0)))
		EntityDef.PlaceholderShape.HULL:
			return hull(size, full)
		_:
			var m := BoxMesh.new()
			m.size = size
			return bake(m, Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.5, 0.0)))


## Quad horizontal de 1 x 1 m mirando hacia arriba (el renderizador lo escala por instancia).
static func impostor() -> ArrayMesh:
	var m := PlaneMesh.new()
	m.size = Vector2.ONE
	return bake(m, Transform3D(Basis.IDENTITY, Vector3(0.0, IMPOSTOR_Y, 0.0)))


## Casco alargado: popa recta, proa en punta y fondo más angosto que la cubierta. Con `full`
## agrega una caseta y una chimenea, para distinguirlo de cerca.
static func hull(size: Vector3, full: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl: float = size.z * 0.5
	var hb: float = size.x * 0.5
	var yd: float = size.y * (1.0 - HULL_DRAFT)
	var yk: float = -size.y * HULL_DRAFT
	var center := Vector3(0.0, (yd + yk) * 0.5, 0.0)
	# Estaciones de popa a proa: (z, media manga en cubierta, media manga en la quilla).
	var stations: Array[Vector3] = [
		Vector3(-hl, hb * 0.78, hb * 0.35),
		Vector3(-hl * 0.6, hb, hb * 0.55),
		Vector3(hl * 0.4, hb, hb * 0.55),
		Vector3(hl * 0.78, hb * 0.6, hb * 0.2),
		Vector3(hl, 0.0, 0.0),
	]
	for i: int in stations.size() - 1:
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i + 1]
		for side: float in [1.0, -1.0]:
			_quad(st, center,
					Vector3(side * a.y, yd, a.x), Vector3(side * b.y, yd, b.x),
					Vector3(side * b.z, yk, b.x), Vector3(side * a.z, yk, a.x))
		_quad(st, center, Vector3(-a.y, yd, a.x), Vector3(a.y, yd, a.x), Vector3(b.y, yd, b.x), Vector3(-b.y, yd, b.x))
		_quad(st, center, Vector3(-a.z, yk, a.x), Vector3(a.z, yk, a.x), Vector3(b.z, yk, b.x), Vector3(-b.z, yk, b.x))
	var s0: Vector3 = stations[0]
	_quad(st, center, Vector3(-s0.y, yd, s0.x), Vector3(s0.y, yd, s0.x), Vector3(s0.z, yk, s0.x), Vector3(-s0.z, yk, s0.x))
	if full:
		var h: float = size.y
		_box(st, Vector3(-hb * 0.45, yd, -hl * 0.25), Vector3(hb * 0.45, yd + h * 0.3, hl * 0.1))
		_box(st, Vector3(-hb * 0.15, yd + h * 0.3, -hl * 0.1), Vector3(hb * 0.15, yd + h * 0.75, -hl * 0.02))
	return st.commit()


## Copia una malla con todos sus vértices transformados por `xf` (y sin huesos ni blend shapes,
## que el MultiMesh no usa). Conserva los materiales de cada superficie salvo que se pase
## `material`, que reemplaza a todos.
static func bake(mesh: Mesh, xf: Transform3D, material: Material = null) -> ArrayMesh:
	var out := ArrayMesh.new()
	if mesh == null:
		return out
	var nb: Basis = xf.basis.inverse().transposed()
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: int in verts.size():
			verts[v] = xf * verts[v]
		arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for v: int in normals.size():
				normals[v] = (nb * normals[v]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for v: int in tangents.size() / 4:
				var t := (xf.basis * Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])).normalized()
				tangents[v * 4] = t.x
				tangents[v * 4 + 1] = t.y
				tangents[v * 4 + 2] = t.z
			arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		var prim: Mesh.PrimitiveType = Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			prim = (mesh as ArrayMesh).surface_get_primitive_type(i)
		out.add_surface_from_arrays(prim, arrays)
		var mat: Material = material if material != null else mesh.surface_get_material(i)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## Primer MeshInstance3D de `root` (en profundidad, en orden de hijos) y su transformación
## relativa a `root`. Devuelve [] si no hay ninguno. `root` no necesita estar en el árbol.
static func find_first_mesh(root: Node) -> Array:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return [(root as MeshInstance3D).mesh, Transform3D.IDENTITY]
	for child: Node in root.get_children():
		var found := find_first_mesh(child)
		if not found.is_empty():
			var xf: Transform3D = found[1]
			if child is Node3D:
				xf = (child as Node3D).transform * xf
			return [found[0], xf]
	return []


## Triángulos de una malla (para pruebas y para el presupuesto de primitivas).
static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


# Cuadrilátero a-b-c-d (en orden alrededor del borde), con la normal hacia fuera de `center`.
static func _quad(st: SurfaceTool, center: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, center, a, b, c)
	_tri(st, center, a, c, d)


# Triángulo con normal plana hacia fuera de `center`. Godot toma como cara frontal la que se ve
# con los vértices en sentido horario, así que el producto vectorial debe apuntar hacia dentro.
static func _tri(st: SurfaceTool, center: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-8:
		return
	var outward := (a + b + c) / 3.0 - center
	var n := cr.normalized()
	if cr.dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
	else:
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var c := (lo + hi) * 0.5
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		_quad(st, c, p[f[0]], p[f[1]], p[f[2]], p[f[3]])
