extends GdUnitTestSuite
## Command: normalización y codificación de entity_ids en deltas varint.


func test_normalize_sorts_and_dedupes() -> void:
	var ids := Command.normalize_ids(PackedInt32Array([9, 3, 3, 0, 7, 1, 9]))
	assert_array(ids).is_equal(PackedInt32Array([1, 3, 7, 9]))
	assert_bool(Command.ids_are_sorted(ids)).is_true()
	assert_bool(Command.ids_are_sorted(PackedInt32Array([1, 1]))).is_false()
	assert_bool(Command.ids_are_sorted(PackedInt32Array([0, 1]))).is_false()


func test_varint_roundtrip() -> void:
	var ids := PackedInt32Array([1, 2, 3, 130, 131, 20000, 70000, 2000000000])
	var data := Command.encode_entity_ids(ids)
	assert_array(Command.decode_entity_ids(data)).is_equal(ids)


func test_full_selection_size_is_small() -> void:
	# 500 unidades casi consecutivas: unos 1-1,5 B por id (ADR-006: ~750 B).
	var ids := PackedInt32Array()
	for i: int in 500:
		ids.append(1000 + i * 2)
	var data := Command.encode_entity_ids(ids)
	assert_int(data.size()).is_less_equal(750)
	assert_array(Command.decode_entity_ids(data)).is_equal(ids)


func test_decode_rejects_too_many_ids() -> void:
	var ids := PackedInt32Array()
	for i: int in SimConstants.MAX_IDS_PER_COMMAND + 1:
		ids.append(i + 1)
	assert_array(Command.decode_entity_ids(Command.encode_entity_ids(ids))).is_empty()


func test_decode_rejects_malformed() -> void:
	# Truncado.
	var data := Command.encode_entity_ids(PackedInt32Array([5, 300]))
	data.resize(data.size() - 1)
	assert_array(Command.decode_entity_ids(data)).is_empty()
	# Delta 0 (id repetido).
	assert_array(Command.decode_entity_ids(PackedByteArray([2, 5, 0]))).is_empty()
	# Bytes sobrantes.
	assert_array(Command.decode_entity_ids(PackedByteArray([1, 5, 9]))).is_empty()


func test_make_move_normalizes() -> void:
	var cmd := Command.make_move(7, PackedInt32Array([4, 2, 2]), Vector2(10, 20), true)
	assert_int(cmd.type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(cmd.seq).is_equal(7)
	assert_array(cmd.entity_ids).is_equal(PackedInt32Array([2, 4]))
