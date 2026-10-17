extends GdUnitTestSuite
## SpatialGrid: celdas de 64 m, reconstrucción por tick y consultas por filas.


func test_cell_of_uses_64m_cells() -> void:
	var g := SpatialGrid.new(1000.0, 1000.0)
	assert_int(g.cols).is_equal(16)
	assert_int(g.cell_of(0.0, 0.0)).is_equal(0)
	assert_int(g.cell_of(63.9, 0.0)).is_equal(0)
	assert_int(g.cell_of(64.0, 0.0)).is_equal(1)
	assert_int(g.cell_of(0.0, 64.0)).is_equal(16)
	# Fuera del mapa se recorta al borde.
	assert_int(g.cell_of(-50.0, -50.0)).is_equal(0)
	assert_int(g.cell_of(5000.0, 5000.0)).is_equal(16 * 16 - 1)


func test_rebuild_writes_cells_and_sorted_keys() -> void:
	var st := EntityStore.new()
	st.spawn(0, 1, 500.0, 500.0, 0.0, 1.0)
	st.spawn(0, 1, 10.0, 10.0, 0.0, 1.0)
	st.spawn(0, 1, 70.0, 10.0, 0.0, 1.0)
	var g := SpatialGrid.new(1000.0, 1000.0)
	g.rebuild(st)
	assert_int(st.cell[0]).is_equal(g.cell_of(500.0, 500.0))
	assert_int(st.cell[1]).is_equal(0)
	assert_int(st.cell[2]).is_equal(1)
	assert_int(g.keys.size()).is_equal(3)
	for i: int in g.keys.size() - 1:
		assert_bool(g.keys[i] < g.keys[i + 1]).is_true()


func test_query_box_matches_brute_force() -> void:
	var st := EntityStore.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 2000:
		st.spawn(0, 1, rng.randf_range(0.0, 2000.0), rng.randf_range(0.0, 2000.0), 0.0, 1.0)
	var g := SpatialGrid.new(2000.0, 2000.0)
	g.rebuild(st)
	for q: int in 20:
		var x := rng.randf_range(0.0, 2000.0)
		var z := rng.randf_range(0.0, 2000.0)
		var r := rng.randf_range(10.0, 300.0)
		var found := PackedInt32Array()
		g.query_box(x, z, r, found)
		var found_set := {}
		for s: int in found:
			found_set[s] = true
		# Toda entidad dentro del radio debe estar entre los candidatos.
		for s: int in st.count:
			var dx: float = st.pos_x[s] - x
			var dz: float = st.pos_z[s] - z
			if dx * dx + dz * dz <= r * r:
				assert_bool(found_set.has(s)).is_true()
		# Y los candidatos solo vienen de celdas que tocan la caja.
		for s: int in found:
			assert_bool(absf(st.pos_x[s] - x) <= r + 64.0 and absf(st.pos_z[s] - z) <= r + 64.0).is_true()


func test_row_range_empty_cells() -> void:
	var st := EntityStore.new()
	st.spawn(0, 1, 10.0, 10.0, 0.0, 1.0)
	var g := SpatialGrid.new(1000.0, 1000.0)
	g.rebuild(st)
	var r := g.row_range(5, 0, 15)
	assert_int(r.y - r.x).is_equal(0)
	r = g.row_range(0, 0, 0)
	assert_int(r.y - r.x).is_equal(1)
