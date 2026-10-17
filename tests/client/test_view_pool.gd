extends GdUnitTestSuite
## EntityViewPool (máximo de vistas, reutilización por def, liberación) y el reparto entre vistas
## individuales y lotes de UnitBatchRenderer, sin GPU.

var _created: int = 0


func _factory(def_index: int, color: Color) -> EntityView:
	_created += 1
	var v := EntityView.new()
	var def := UnitDef.new()
	def.id = StringName("def_%d" % def_index)
	v.setup(def, null, color)
	return v


func _make_pool(max_views: int) -> EntityViewPool:
	_created = 0
	var parent: Node3D = auto_free(Node3D.new())
	return EntityViewPool.new(parent, _factory, max_views)


func test_acquire_creates_until_max_then_returns_null() -> void:
	var pool := _make_pool(3)
	for id: int in [1, 2, 3]:
		assert_object(pool.acquire(id, 0, Color.RED)).is_not_null()
	assert_object(pool.acquire(4, 0, Color.RED)).is_null()
	assert_int(pool.in_use()).is_equal(3)
	assert_int(pool.total).is_equal(3)


func test_acquire_same_id_returns_same_view() -> void:
	var pool := _make_pool(4)
	var v := pool.acquire(7, 0, Color.RED)
	assert_object(pool.acquire(7, 0, Color.RED)).is_same(v)
	assert_int(v.entity_id).is_equal(7)
	assert_int(_created).is_equal(1)


func test_released_views_are_reused_for_same_def() -> void:
	var pool := _make_pool(4)
	var v := pool.acquire(1, 2, Color.RED)
	pool.release(1)
	assert_bool(v.visible).is_false()
	assert_int(pool.free_count()).is_equal(1)
	var w := pool.acquire(9, 2, Color.BLUE)
	assert_object(w).is_same(v)
	assert_int(w.entity_id).is_equal(9)
	assert_bool(w.team_color.is_equal_approx(Color.BLUE)).is_true()
	assert_bool(w.visible).is_true()
	assert_int(_created).is_equal(1)


func test_full_pool_evicts_a_free_view_of_another_def() -> void:
	var pool := _make_pool(2)
	pool.acquire(1, 0, Color.RED)
	pool.acquire(2, 0, Color.RED)
	pool.release(2)
	var v := pool.acquire(3, 5, Color.RED)
	assert_object(v).is_not_null()
	assert_int(v.get_meta(&"def_index")).is_equal(5)
	assert_int(pool.total).is_equal(2)
	assert_int(pool.free_count()).is_equal(0)


func test_release_except_keeps_only_given_ids() -> void:
	var pool := _make_pool(8)
	for id: int in [1, 2, 3, 4]:
		pool.acquire(id, 0, Color.RED)
	pool.release_except({2: true, 4: true})
	assert_bool(pool.has_view(2)).is_true()
	assert_bool(pool.has_view(4)).is_true()
	assert_bool(pool.has_view(1)).is_false()
	assert_int(pool.in_use()).is_equal(2)
	assert_int(pool.free_count()).is_equal(2)


func test_default_max_is_256() -> void:
	assert_int(EntityViewPool.DEFAULT_MAX_VIEWS).is_equal(256)


# --- UnitBatchRenderer: reparto entre vistas, lotes y recorte ------------------------------------

func _make_scene(units: int, max_views: int) -> Array:
	var gd: GameData = load(GameData.DEFAULT_PATH)
	gd.build_index()
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var cam := Camera3D.new()
	cam.far = 6000.0
	root.add_child(cam)
	# Cámara a 40 m de altura mirando hacia -Z (y un poco hacia abajo).
	cam.look_at_from_position(Vector3(0, 40, 0), Vector3(0, 0, -60))
	var st := SyntheticClientState.new()
	for i: int in units:
		st.add_entity(i + 1, 0, 1 + i % 2, (i % 20 - 10) * 2.0, -40.0 - (i / 20) * 2.0)
	var r := UnitBatchRenderer.new()
	r.auto_update = false
	r.camera = cam
	root.add_child(r)
	r.setup(st, ViewCatalog.new(gd), PackedColorArray(), max_views)
	return [r, st, cam]


func test_near_units_get_views_up_to_pool_max_rest_in_batches() -> void:
	var parts := _make_scene(300, 256)
	var r: UnitBatchRenderer = parts[0]
	r.refresh()
	assert_int(r.stat_visible).is_equal(300)
	assert_int(r.stat_pooled).is_equal(256)
	assert_int(r.stat_lod[PlaceholderMeshes.Lod.FULL]).is_equal(300 - 256)
	assert_int(r.pool.in_use()).is_equal(256)


func test_entities_behind_camera_are_culled_and_views_released() -> void:
	var parts := _make_scene(50, 256)
	var r: UnitBatchRenderer = parts[0]
	var cam: Camera3D = parts[2]
	r.refresh()
	assert_int(r.stat_pooled).is_equal(50)
	cam.look_at_from_position(Vector3(0, 40, 0), Vector3(0, 0, 60))
	r.refresh()
	assert_int(r.stat_visible).is_equal(0)
	assert_int(r.pool.in_use()).is_equal(0)
	assert_int(r.stat_batches_drawn).is_equal(0)


func test_removed_entity_releases_its_view() -> void:
	var parts := _make_scene(10, 256)
	var r: UnitBatchRenderer = parts[0]
	var st: SyntheticClientState = parts[1]
	r.refresh()
	assert_bool(r.pool.has_view(3)).is_true()
	st.remove(3)
	r.refresh()
	assert_bool(r.pool.has_view(3)).is_false()
	assert_int(r.pool.in_use()).is_equal(9)


func test_without_pool_everything_goes_to_batches_by_owner() -> void:
	var parts := _make_scene(40, 256)
	var r: UnitBatchRenderer = parts[0]
	r.use_pool = false
	r.refresh()
	assert_int(r.stat_pooled).is_equal(0)
	assert_int(r.stat_lod[PlaceholderMeshes.Lod.FULL]).is_equal(40)
	# Dos jugadores -> dos lotes con instancias.
	assert_int(r.stat_batches_drawn).is_equal(2)
