extends GdUnitTestSuite
## EntityStore: ids correlativos sin reutilización, creación, swap-remove y crecimiento.


func test_ids_are_sequential_from_one() -> void:
	var st := EntityStore.new()
	assert_int(st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)).is_equal(1)
	assert_int(st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)).is_equal(2)
	assert_int(st.spawn(0, 2, 0.0, 0.0, 0.0, 100.0)).is_equal(3)
	assert_int(st.count).is_equal(3)


func test_ids_are_never_reused() -> void:
	var st := EntityStore.new()
	var a := st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)
	var b := st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)
	assert_bool(st.remove(b)).is_true()
	assert_bool(st.remove(a)).is_true()
	var c := st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)
	assert_int(c).is_equal(3)
	assert_bool(st.is_alive(a)).is_false()
	assert_bool(st.is_alive(b)).is_false()


func test_zero_is_no_entity() -> void:
	var st := EntityStore.new()
	st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)
	assert_int(st.slot_of(0)).is_equal(-1)
	assert_int(st.slot_of(-5)).is_equal(-1)
	assert_int(st.slot_of(999)).is_equal(-1)
	assert_bool(st.remove(0)).is_false()


func test_spawn_sets_fields() -> void:
	var st := EntityStore.new()
	var e := st.spawn(3, 2, 10.5, -4.25, 1.0, 80.0)
	var s := st.slot_of(e)
	assert_int(st.def_index[s]).is_equal(3)
	assert_int(st.owner[s]).is_equal(2)
	assert_float(st.pos_x[s]).is_equal(10.5)
	assert_float(st.pos_z[s]).is_equal(-4.25)
	assert_float(st.hp[s]).is_equal(80.0)
	assert_int(st.action[s]).is_equal(SimConstants.Action.IDLE)


func test_swap_remove_moves_last_into_hole() -> void:
	var st := EntityStore.new()
	var ids: Array[int] = []
	for i: int in 5:
		ids.append(st.spawn(0, 1, float(i), 0.0, 0.0, 100.0))
	# Borrar el del medio: el último (id 5, x=4) debe pasar a su slot.
	var hole := st.slot_of(ids[2])
	assert_bool(st.remove(ids[2])).is_true()
	assert_int(st.count).is_equal(4)
	assert_int(st.id[hole]).is_equal(ids[4])
	assert_float(st.pos_x[hole]).is_equal(4.0)
	assert_int(st.slot_of(ids[4])).is_equal(hole)
	assert_int(st.slot_of(ids[2])).is_equal(-1)
	# El resto sigue donde estaba y es coherente.
	for s: int in st.count:
		assert_int(st.slot_of(st.id[s])).is_equal(s)
	assert_bool(st.remove(ids[2])).is_false()


func test_remove_last_slot() -> void:
	var st := EntityStore.new()
	var a := st.spawn(0, 1, 0.0, 0.0, 0.0, 100.0)
	var b := st.spawn(0, 1, 1.0, 0.0, 0.0, 100.0)
	assert_bool(st.remove(b)).is_true()
	assert_int(st.count).is_equal(1)
	assert_int(st.slot_of(a)).is_equal(0)


func test_grows_beyond_initial_capacity() -> void:
	var st := EntityStore.new(4)
	for i: int in 1000:
		st.spawn(0, 1, float(i), float(-i), 0.0, 100.0)
	assert_int(st.count).is_equal(1000)
	assert_int(st.capacity).is_greater_equal(1000)
	var s := st.slot_of(777)
	assert_float(st.pos_x[s]).is_equal(776.0)
	assert_float(st.pos_z[s]).is_equal(-776.0)
	assert_int(st.pos_x.size()).is_equal(st.capacity)
	assert_int(st.progress.size()).is_equal(st.capacity)


func test_many_random_removes_keep_index_consistent() -> void:
	var st := EntityStore.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var alive: Array[int] = []
	for i: int in 500:
		alive.append(st.spawn(0, 1, float(i), 0.0, 0.0, 100.0))
	for i: int in 300:
		var k := rng.randi_range(0, alive.size() - 1)
		assert_bool(st.remove(alive[k])).is_true()
		alive.remove_at(k)
	assert_int(st.count).is_equal(alive.size())
	for e: int in alive:
		var s := st.slot_of(e)
		assert_int(st.id[s]).is_equal(e)
		# Cada entidad conserva su posición original (x = id - 1).
		assert_float(st.pos_x[s]).is_equal(float(e - 1))
