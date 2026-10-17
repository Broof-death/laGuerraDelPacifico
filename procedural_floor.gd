extends Node3D
class_name ProceduralFloor
## Suelo plano infinito generado por chunks alrededor de una cámara (Godot 4.x, 3D).
## Crea los chunks que entran en el radio de visión y recicla los que salen.

@export var camera: Node3D                      ## Si queda vacío, usa la cámara activa del viewport
@export var chunk_size: float = 16.0            ## Lado de cada chunk en metros
@export_range(1, 32) var view_radius: int = 4   ## Radio de chunks visibles alrededor de la cámara
@export var floor_material: Material            ## Material del suelo (opcional)
@export var with_collision: bool = true         ## Agrega colisión para que los cuerpos se apoyen
@export var collision_thickness: float = 1.0    ## Grosor de la caja de colisión bajo el plano

var _chunks: Dictionary = {}        # Vector2i -> StaticBody3D
var _pool: Array[StaticBody3D] = [] # chunks reciclados, fuera del árbol
var _current := Vector2i(2147483647, 2147483647)
var _mesh: PlaneMesh
var _shape: BoxShape3D


func _ready() -> void:
	# Mesh y shape compartidos por todos los chunks: menos memoria y menos draw setup.
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(chunk_size, chunk_size)
	if floor_material:
		_mesh.material = floor_material

	_shape = BoxShape3D.new()
	_shape.size = Vector3(chunk_size, collision_thickness, chunk_size)


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return

	# Posición de la cámara en el espacio local del suelo -> coordenada de chunk.
	var p := to_local(camera.global_position)
	var c := Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))
	if c != _current:
		_current = c
		_update_chunks()


func _update_chunks() -> void:
	# 1) Qué chunks deberían existir (radio circular alrededor de la cámara).
	var needed := {}
	var r2 := view_radius * view_radius
	for dx in range(-view_radius, view_radius + 1):
		for dz in range(-view_radius, view_radius + 1):
			if dx * dx + dz * dz <= r2:
				needed[_current + Vector2i(dx, dz)] = true

	# 2) Reciclar primero los que quedaron fuera, para reutilizarlos de inmediato.
	for key in _chunks.keys():
		if not needed.has(key):
			_recycle(_chunks[key])
			_chunks.erase(key)

	# 3) Crear los que faltan.
	for key in needed.keys():
		if not _chunks.has(key):
			_chunks[key] = _spawn(key)


func _spawn(key: Vector2i) -> StaticBody3D:
	var body: StaticBody3D
	if _pool.is_empty():
		body = StaticBody3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		body.add_child(mi)
		if with_collision:
			var cs := CollisionShape3D.new()
			cs.shape = _shape
			cs.position.y = -collision_thickness * 0.5  # la cara superior queda en y = 0
			body.add_child(cs)
	else:
		body = _pool.pop_back()

	add_child(body)
	body.position = Vector3((key.x + 0.5) * chunk_size, 0.0, (key.y + 0.5) * chunk_size)
	_decorate_chunk(body, key)
	return body


func _recycle(body: StaticBody3D) -> void:
	# Sacarlo del árbol lo quita también de render y física.
	remove_child(body)
	_pool.append(body)


## Punto de extensión para contenido procedural por chunk (rocas, pasto, props...).
## Usa una semilla derivada de la coordenada para que el mismo chunk siempre
## se genere igual al volver a él.
func _decorate_chunk(_body: StaticBody3D, key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	# Ejemplo: limpiar decoraciones anteriores (si el chunk viene del pool)
	# y agregar nuevas con posiciones de rng.randf_range(-chunk_size / 2, chunk_size / 2).
	pass
