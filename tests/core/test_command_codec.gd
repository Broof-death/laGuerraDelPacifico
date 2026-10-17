extends GdUnitTestSuite
## CommandCodec y mensajes cortos de NetProtocol.


func test_roundtrip_all_fields() -> void:
	var cmd := Command.make_move(77, PackedInt32Array([3, 9, 10, 400, 70000]), Vector2(-1234.5, 60000.25), true)
	cmd.queued = true
	cmd.target_id = 4242
	cmd.def_id = &"infantería_línea_chile"
	cmd.formation = 2
	var data := CommandCodec.encode(cmd)
	assert_int(NetProtocol.msg_type(data)).is_equal(NetProtocol.Msg.COMMAND)
	var out := CommandCodec.decode(data)
	assert_object(out).is_not_null()
	assert_int(out.type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(out.seq).is_equal(77)
	assert_array(out.entity_ids).is_equal(cmd.entity_ids)
	assert_bool(out.queued).is_true()
	assert_int(out.target_id).is_equal(4242)
	assert_str(String(out.def_id)).is_equal("infantería_línea_chile")
	assert_int(out.formation).is_equal(2)
	# Destino cuantizado como los snapshots: error <= medio paso (0,0625 m).
	assert_float(absf(out.target_pos.x - cmd.target_pos.x)).is_less_equal(0.0625)
	assert_float(absf(out.target_pos.y - cmd.target_pos.y)).is_less_equal(0.0625)


func test_center_of_map_is_a_valid_target() -> void:
	var out := CommandCodec.decode(CommandCodec.encode(Command.make_move(1, PackedInt32Array([1]), Vector2.ZERO)))
	assert_float(out.target_pos.length()).is_less_equal(0.1)
	var stop := CommandCodec.decode(CommandCodec.encode(Command.make_stop(2, PackedInt32Array([1, 2]))))
	assert_int(stop.type).is_equal(Command.Type.STOP)
	assert_array(stop.entity_ids).is_equal(PackedInt32Array([1, 2]))


func test_full_selection_fits_in_one_kb() -> void:
	var ids := PackedInt32Array()
	for i: int in SimConstants.MAX_IDS_PER_COMMAND:
		ids.append(5000 + i * 3)
	var data := CommandCodec.encode(Command.make_move(1, ids, Vector2(10, 10)))
	assert_int(data.size()).is_less(1024)
	assert_array(CommandCodec.decode(data).entity_ids).is_equal(ids)


func test_encode_refuses_invalid() -> void:
	var cmd := Command.new()
	cmd.type = Command.Type.MOVE
	cmd.entity_ids = PackedInt32Array([5, 3])
	assert_int(CommandCodec.encode(cmd).size()).is_equal(0)
	cmd.entity_ids = PackedInt32Array([3])
	cmd.target_pos = Vector2(NAN, 0)
	assert_int(CommandCodec.encode(cmd).size()).is_equal(0)


func test_decode_rejects_malformed() -> void:
	var data := CommandCodec.encode(Command.make_move(1, PackedInt32Array([1, 2, 3]), Vector2(5, 5)))
	# Truncado.
	var cut := data.slice(0, data.size() - 3)
	assert_object(CommandCodec.decode(cut)).is_null()
	# Bytes sobrantes.
	var extra := data.duplicate()
	extra.append_array(PackedByteArray([0, 0]))
	assert_object(CommandCodec.decode(extra)).is_null()
	# Tipo fuera de rango.
	var bad := data.duplicate()
	bad[1] = 200
	assert_object(CommandCodec.decode(bad)).is_null()
	# Ids no crecientes (diferencia 0).
	var w := BitWriter.new()
	w.write_bits(NetProtocol.Msg.COMMAND, 8)
	w.write_bits(Command.Type.STOP, 8)
	w.write_varint(1)
	w.write_bits(0, 8)
	w.write_varint(2)
	w.write_varint(4)
	w.write_varint(0)
	assert_object(CommandCodec.decode(w.get_bytes())).is_null()
	# Demasiados ids.
	var w2 := BitWriter.new()
	w2.write_bits(NetProtocol.Msg.COMMAND, 8)
	w2.write_bits(Command.Type.STOP, 8)
	w2.write_varint(1)
	w2.write_bits(0, 8)
	w2.write_varint(SimConstants.MAX_IDS_PER_COMMAND + 1)
	for i: int in SimConstants.MAX_IDS_PER_COMMAND + 1:
		w2.write_varint(1)
	assert_object(CommandCodec.decode(w2.get_bytes())).is_null()
	assert_object(CommandCodec.decode(PackedByteArray())).is_null()


func test_protocol_messages_roundtrip() -> void:
	assert_array(NetProtocol.decode_hello(NetProtocol.encode_hello(0xDEADBEEF))).is_equal(
			PackedInt64Array([NetProtocol.PROTOCOL_VERSION, 0xDEADBEEF]))
	assert_array(NetProtocol.decode_welcome(NetProtocol.encode_welcome(3, 123456, 6))).is_equal(PackedInt64Array([3, 123456, 6]))
	assert_int(NetProtocol.decode_ack(NetProtocol.encode_ack(98765))).is_equal(98765)
	assert_array(NetProtocol.decode_rejected(NetProtocol.encode_rejected(300, Command.Reject.NOT_OWNER))).is_equal(
			PackedInt32Array([300, Command.Reject.NOT_OWNER]))
	assert_int(NetProtocol.decode_refused(NetProtocol.encode_refused(NetProtocol.Refuse.MATCH_FULL))).is_equal(NetProtocol.Refuse.MATCH_FULL)
	assert_int(NetProtocol.decode_ack(PackedByteArray([NetProtocol.Msg.ACK, 1]))).is_equal(-1)
