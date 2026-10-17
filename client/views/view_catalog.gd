class_name ViewCatalog
extends RefCounted
## Catálogo visual del cliente: de cada definición (def_index de GameData) saca, bajo demanda y
## con caché, las mallas por lotes de cada nivel de detalle y la escena de su vista individual
## (ADR-007 punto 2, ADR-006 punto 7). Solo cliente: el servidor nunca lo carga.
##
## - Si view_scene_path tiene una escena que carga, la vista individual es esa escena (si su raíz
##   no es una EntityView, se envuelve en una) y la malla por lotes es su primer MeshInstance3D,
##   con su transformación horneada. Ese modelo se usa en FULL y SIMPLE (si el modelo trae LOD de
##   importación, Godot lo aplica solo).
## - Si está vacío o no carga, se usa la forma provisional (placeholder_shape/size) y
##   placeholder_view.tscn.
## - El impostor (> 1,5 km) es siempre un quad del color del bando.

const PLACEHOLDER_VIEW_SCENE: String = "res://client/views/placeholder_view.tscn"


class Entry:
	var def_index: int = -1
	var def: EntityDef
	## Malla por nivel (PlaceholderMeshes.Lod).
	var meshes: Array[Mesh] = []
	## true si la malla y la vista vienen de view_scene_path.
	var from_scene: bool = false
	var view_scene: PackedScene
	## Buques y edificios: vista individual también a media distancia (ADR-006 punto 7).
	var prefers_view: bool = false
	## Huella en el plano (x, z) en metros, para escalar el impostor.
	var footprint := Vector2.ONE
	## Radio de la esfera que la contiene (recorte por frustum).
	var cull_radius: float = 1.0


var game_data: GameData
## Material de las mallas provisionales por lotes: el color sale del color por instancia.
var batch_material: StandardMaterial3D
var impostor_material: StandardMaterial3D

var _entries: Array[Entry] = []
var _placeholder_scene: PackedScene


func _init(p_game_data: GameData) -> void:
	game_data = p_game_data
	batch_material = StandardMaterial3D.new()
	batch_material.vertex_color_use_as_albedo = true
	batch_material.roughness = 0.8
	impostor_material = StandardMaterial3D.new()
	impostor_material.vertex_color_use_as_albedo = true
	impostor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## Entrada visual de un def_index (null si no existe en GameData).
func entry(def_index: int) -> Entry:
	if def_index < 0:
		return null
	if def_index < _entries.size() and _entries[def_index] != null:
		return _entries[def_index]
	var def: EntityDef = game_data.get_def(def_index)
	if def == null:
		return null
	if _entries.size() <= def_index:
		_entries.resize(def_index + 1)
	var e := _make_entry(def_index, def)
	_entries[def_index] = e
	return e


## Crea la vista individual de un def_index con el color del bando. El pool la reutiliza.
func create_view(def_index: int, team_color: Color, faction: FactionDef = null) -> EntityView:
	var e := entry(def_index)
	if e == null:
		return null
	var view: EntityView
	if e.view_scene != null:
		var inst: Node = e.view_scene.instantiate()
		if inst is EntityView:
			view = inst
		else:
			view = EntityView.new()
			view.add_child(inst)
	else:
		view = _get_placeholder_scene().instantiate() as EntityView
	view.name = "Vista_%s" % e.def.id
	view.setup(e.def, faction, team_color)
	return view


## Carga una escena de arte final; null (con un aviso) si la ruta está vacía o no carga.
static func load_view_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("ViewCatalog: no existe view_scene_path '%s'; se usa la forma provisional." % path)
		return null
	var res: Resource = load(path)
	if not (res is PackedScene):
		push_warning("ViewCatalog: '%s' no es una escena; se usa la forma provisional." % path)
		return null
	return res


func _make_entry(def_index: int, def: EntityDef) -> Entry:
	var e := Entry.new()
	e.def_index = def_index
	e.def = def
	e.prefers_view = def is BuildingDef or (def is UnitDef and (def as UnitDef).domain == UnitDef.Domain.SEA)
	var size: Vector3 = def.placeholder_size
	e.meshes.resize(3)
	e.view_scene = load_view_scene(def.view_scene_path)
	if e.view_scene != null:
		var inst: Node = e.view_scene.instantiate()
		var found := PlaceholderMeshes.find_first_mesh(inst)
		inst.free()
		if found.is_empty():
			push_warning("ViewCatalog: '%s' no tiene MeshInstance3D; los lotes usan la forma provisional." % def.view_scene_path)
		else:
			var m := PlaceholderMeshes.bake(found[0], found[1])
			e.meshes[PlaceholderMeshes.Lod.FULL] = m
			e.meshes[PlaceholderMeshes.Lod.SIMPLE] = m
			e.from_scene = true
			var aabb: AABB = m.get_aabb()
			size = aabb.size
	if not e.from_scene:
		for lod: PlaceholderMeshes.Lod in [PlaceholderMeshes.Lod.FULL, PlaceholderMeshes.Lod.SIMPLE]:
			var m := PlaceholderMeshes.build(def.placeholder_shape, def.placeholder_size, lod)
			for s: int in m.get_surface_count():
				m.surface_set_material(s, batch_material)
			e.meshes[lod] = m
	var imp := PlaceholderMeshes.impostor()
	imp.surface_set_material(0, impostor_material)
	e.meshes[PlaceholderMeshes.Lod.IMPOSTOR] = imp
	e.footprint = Vector2(maxf(size.x, 0.5), maxf(size.z, 0.5))
	e.cull_radius = size.length() * 0.5 + 0.5
	return e


func _get_placeholder_scene() -> PackedScene:
	if _placeholder_scene == null:
		_placeholder_scene = load(PLACEHOLDER_VIEW_SCENE)
	return _placeholder_scene
