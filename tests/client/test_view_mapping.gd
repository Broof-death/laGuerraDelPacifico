extends GdUnitTestSuite
## Vistas del cliente (T-017) sin GPU: mallas provisionales, colores de bando, catálogo visual
## (def -> malla, escena y material) y niveles de detalle.

const HUASCAR_GLB: String = "res://assets/models/barcos/huascar.glb"


func _game_data() -> GameData:
	var gd: GameData = load(GameData.DEFAULT_PATH)
	assert_array(gd.build_index()).is_empty()
	return gd


# --- PlaceholderMeshes ---------------------------------------------------------------------------

func test_capsule_sits_on_ground_with_def_size() -> void:
	var m := PlaceholderMeshes.build(EntityDef.PlaceholderShape.CAPSULE, Vector3(1, 2, 1), PlaceholderMeshes.Lod.FULL)
	var aabb := m.get_aabb()
	assert_float(aabb.position.y).is_equal_approx(0.0, 0.01)
	assert_vector(aabb.size).is_equal_approx(Vector3(1, 2, 1), Vector3(0.05, 0.05, 0.05))


func test_box_and_cylinder_use_full_size() -> void:
	var box := PlaceholderMeshes.build(EntityDef.PlaceholderShape.BOX, Vector3(16, 7, 12), PlaceholderMeshes.Lod.FULL)
	assert_vector(box.get_aabb().size).is_equal_approx(Vector3(16, 7, 12), Vector3(0.01, 0.01, 0.01))
	assert_float(box.get_aabb().position.y).is_equal_approx(0.0, 0.01)
	var cyl := PlaceholderMeshes.build(EntityDef.PlaceholderShape.CYLINDER, Vector3(2.2, 1.2, 3.0), PlaceholderMeshes.Lod.FULL)
	assert_vector(cyl.get_aabb().size).is_equal_approx(Vector3(2.2, 1.2, 3.0), Vector3(0.05, 0.01, 0.05))


func test_hull_is_long_and_floats_at_waterline() -> void:
	var size := Vector3(10, 6, 60)
	var m := PlaceholderMeshes.build(EntityDef.PlaceholderShape.HULL, size, PlaceholderMeshes.Lod.SIMPLE)
	var aabb := m.get_aabb()
	assert_float(aabb.size.z).is_equal_approx(60.0, 0.01)
	assert_float(aabb.size.x).is_equal_approx(10.0, 0.01)
	assert_float(aabb.position.y).is_equal_approx(-size.y * PlaceholderMeshes.HULL_DRAFT, 0.01)
	# La proa (en punta) apunta a +Z: cerca de z = +L/2 el casco es más angosto que en el centro.
	var arrays := m.surface_get_arrays(0)
	var max_x_near_bow: float = 0.0
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		if v.z > 29.0:
			max_x_near_bow = maxf(max_x_near_bow, absf(v.x))
	assert_float(max_x_near_bow).is_less(1.0)


func test_hull_normals_point_outwards() -> void:
	var m := PlaceholderMeshes.hull(Vector3(10, 6, 60), false)
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var center := Vector3(0, 0.6, 0)
	for i: int in range(0, verts.size(), 3):
		var c := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		assert_float(normals[i].dot(c - center)).is_greater(0.0)
		# Cara frontal en sentido horario (convención de Godot): el producto vectorial apunta hacia dentro.
		var cr := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
		assert_float(cr.dot(normals[i])).is_less(0.0)


func test_simple_lod_has_fewer_triangles() -> void:
	for shape: EntityDef.PlaceholderShape in [EntityDef.PlaceholderShape.CAPSULE, EntityDef.PlaceholderShape.CYLINDER, EntityDef.PlaceholderShape.HULL]:
		var full := PlaceholderMeshes.triangle_count(PlaceholderMeshes.build(shape, Vector3(2, 3, 4), PlaceholderMeshes.Lod.FULL))
		var simple := PlaceholderMeshes.triangle_count(PlaceholderMeshes.build(shape, Vector3(2, 3, 4), PlaceholderMeshes.Lod.SIMPLE))
		assert_int(simple).is_less(full)


func test_impostor_is_one_flat_quad() -> void:
	var m := PlaceholderMeshes.build(EntityDef.PlaceholderShape.HULL, Vector3(10, 6, 60), PlaceholderMeshes.Lod.IMPOSTOR)
	assert_int(PlaceholderMeshes.triangle_count(m)).is_equal(2)
	assert_float(m.get_aabb().size.y).is_equal_approx(0.0, 0.001)
	assert_float(m.get_aabb().position.y).is_equal_approx(PlaceholderMeshes.IMPOSTOR_Y, 0.001)


func test_find_first_mesh_bakes_nested_transform() -> void:
	var root := Node3D.new()
	var mid := Node3D.new()
	mid.position = Vector3(0, 5, 0)
	root.add_child(mid)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	mi.mesh = box
	mi.scale = Vector3(2, 2, 2)
	mid.add_child(mi)
	var found := PlaceholderMeshes.find_first_mesh(root)
	assert_array(found).has_size(2)
	var baked := PlaceholderMeshes.bake(found[0], found[1])
	assert_vector(baked.get_aabb().size).is_equal_approx(Vector3(4, 4, 4), Vector3(0.01, 0.01, 0.01))
	assert_float(baked.get_aabb().get_center().y).is_equal_approx(5.0, 0.01)
	root.free()


# --- TeamColors ----------------------------------------------------------------------------------

func test_player_colors_are_distinct() -> void:
	var pal := TeamColors.default_palette()
	assert_int(pal.size()).is_equal(SimConstants.MAX_PLAYER_ID + 1)
	for a: int in range(0, SimConstants.MAX_PLAYERS + 1):
		for b: int in range(a + 1, SimConstants.MAX_PLAYERS + 1):
			assert_bool(pal[a].is_equal_approx(pal[b])).is_false()


func test_faction_colors_override_palette() -> void:
	var f := FactionDef.new()
	f.color = Color(0.1, 0.2, 0.3)
	var pal := TeamColors.from_factions([null, f, null])
	assert_bool(pal[1].is_equal_approx(Color(0.1, 0.2, 0.3))).is_true()
	assert_bool(pal[2].is_equal_approx(TeamColors.color_for_player(2))).is_true()


# --- ViewCatalog -----------------------------------------------------------------------------------

func test_placeholder_entry_uses_def_shape_and_batch_material() -> void:
	var gd := _game_data()
	var cat := ViewCatalog.new(gd)
	var e := cat.entry(gd.index_of(&"infanteria_prueba"))
	assert_object(e).is_not_null()
	assert_bool(e.from_scene).is_false()
	assert_bool(e.prefers_view).is_false()
	assert_int(e.meshes.size()).is_equal(3)
	for lod: int in 3:
		assert_object(e.meshes[lod]).is_not_null()
	assert_object(e.meshes[PlaceholderMeshes.Lod.FULL].surface_get_material(0)).is_same(cat.batch_material)
	assert_object(e.meshes[PlaceholderMeshes.Lod.IMPOSTOR].surface_get_material(0)).is_same(cat.impostor_material)
	assert_vector(e.meshes[PlaceholderMeshes.Lod.FULL].get_aabb().size).is_equal_approx(Vector3(1, 2, 1), Vector3(0.05, 0.05, 0.05))
	# Mismo objeto en la segunda consulta (caché).
	assert_object(cat.entry(gd.index_of(&"infanteria_prueba"))).is_same(e)


func test_ships_and_buildings_prefer_individual_views() -> void:
	var gd := _game_data()
	var cat := ViewCatalog.new(gd)
	assert_bool(cat.entry(gd.index_of(&"buque_prueba")).prefers_view).is_true()
	assert_bool(cat.entry(gd.index_of(&"edificio_prueba")).prefers_view).is_true()
	assert_bool(cat.entry(gd.index_of(&"caballeria_prueba")).prefers_view).is_false()
	assert_object(cat.entry(999)).is_null()


func test_each_test_type_has_a_different_mesh() -> void:
	var gd := _game_data()
	var cat := ViewCatalog.new(gd)
	var seen: Dictionary = {}
	for id: StringName in [&"infanteria_prueba", &"caballeria_prueba", &"artilleria_prueba", &"buque_prueba", &"edificio_prueba"]:
		var m: Mesh = cat.entry(gd.index_of(id)).meshes[PlaceholderMeshes.Lod.FULL]
		var key := "%s|%d" % [m.get_aabb().size, PlaceholderMeshes.triangle_count(m)]
		assert_bool(seen.has(key)).override_failure_message("%s se ve igual que %s" % [id, seen.get(key)]).is_false()
		seen[key] = id


# GameData en memoria con una sola unidad (no se toca el catálogo cargado, que está en caché).
func _single_def_data(def: UnitDef) -> GameData:
	def.cost = {}
	var gd := GameData.new()
	gd.units = [def]
	assert_array(gd.build_index()).is_empty()
	return gd


func test_view_scene_path_replaces_placeholder() -> void:
	var def: UnitDef = _game_data().get_def(_game_data().index_of(&"buque_prueba")).duplicate()
	def.view_scene_path = HUASCAR_GLB
	var gd := _single_def_data(def)
	var cat := ViewCatalog.new(gd)
	var e := cat.entry(0)
	assert_bool(e.from_scene).is_true()
	assert_object(e.meshes[PlaceholderMeshes.Lod.FULL]).is_not_null()
	assert_object(e.meshes[PlaceholderMeshes.Lod.FULL]).is_same(e.meshes[PlaceholderMeshes.Lod.SIMPLE])
	var view := cat.create_view(e.def_index, Color.RED)
	assert_bool(view is PlaceholderView).is_false()
	assert_int(view.get_child_count()).is_greater(0)
	view.free()


func test_missing_view_scene_falls_back_to_placeholder() -> void:
	var def: UnitDef = _game_data().get_def(0).duplicate()
	def.view_scene_path = "res://no/existe.tscn"
	var gd := _single_def_data(def)
	var cat := ViewCatalog.new(gd)
	assert_bool(cat.entry(0).from_scene).is_false()
	var view := cat.create_view(0, Color.BLUE)
	assert_bool(view is PlaceholderView).is_true()
	assert_bool(view.team_color.is_equal_approx(Color.BLUE)).is_true()
	view.set_details_visible(true)
	var label := view.get_node("Etiqueta") as Label3D
	assert_str(label.text).is_equal(def.placeholder_label)
	view.free()


# --- Niveles de detalle (ADR-006 punto 7) ---------------------------------------------------------

func test_lod_thresholds() -> void:
	assert_int(UnitBatchRenderer.lod_for_distance(10.0)).is_equal(PlaceholderMeshes.Lod.FULL)
	assert_int(UnitBatchRenderer.lod_for_distance(149.9)).is_equal(PlaceholderMeshes.Lod.FULL)
	assert_int(UnitBatchRenderer.lod_for_distance(150.0)).is_equal(PlaceholderMeshes.Lod.SIMPLE)
	assert_int(UnitBatchRenderer.lod_for_distance(1499.0)).is_equal(PlaceholderMeshes.Lod.SIMPLE)
	assert_int(UnitBatchRenderer.lod_for_distance(1500.0)).is_equal(PlaceholderMeshes.Lod.IMPOSTOR)


func test_impostor_grows_with_distance_but_never_shrinks() -> void:
	assert_float(UnitBatchRenderer.impostor_scale(60.0, 2000.0)).is_equal(1.0)
	var s := UnitBatchRenderer.impostor_scale(1.0, 3000.0)
	assert_float(s).is_greater(1.0)
	assert_float(s * 1.0).is_equal_approx(3000.0 * UnitBatchRenderer.IMPOSTOR_SIZE_PER_METER, 0.001)
