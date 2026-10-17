extends GdUnitTestSuite
## BitWriter / BitReader: ida y vuelta, varint, signo, relleno y lectura fuera de rango.


func test_roundtrip_mixed_widths() -> void:
	var w := BitWriter.new()
	var values := [[1, 1], [0, 1], [5, 3], [1023, 10], [0xFFFFF, 20], [123456, 20], [0xFFFFFFFF, 32], [7, 4], [200, 8]]
	for v: Array in values:
		w.write_bits(v[0], v[1])
	var bits: int = 0
	for v: Array in values:
		bits += v[1]
	assert_int(w.bit_length()).is_equal(bits)
	assert_int(w.byte_length()).is_equal((bits + 7) / 8)
	var r := BitReader.new(w.get_bytes())
	for v: Array in values:
		assert_int(r.read_bits(v[1])).is_equal(v[0])
	assert_bool(r.error).is_false()


func test_signed_and_varint() -> void:
	var w := BitWriter.new()
	for v: int in [-128, -1, 0, 1, 127]:
		w.write_signed(v, 8)
	for v: int in [0, 1, 127, 128, 300, 16383, 16384, 2147483647]:
		w.write_varint(v)
	var r := BitReader.new(w.get_bytes())
	for v: int in [-128, -1, 0, 1, 127]:
		assert_int(r.read_signed(8)).is_equal(v)
	for v: int in [0, 1, 127, 128, 300, 16383, 16384, 2147483647]:
		assert_int(r.read_varint()).is_equal(v)
	assert_bool(r.error).is_false()
	assert_int(BitWriter.varint_bits(127)).is_equal(8)
	assert_int(BitWriter.varint_bits(128)).is_equal(16)


func test_patch_bits() -> void:
	var w := BitWriter.new()
	w.write_bits(0xAB, 8)
	var pos: int = w.bit_length()
	w.write_bits(0, 16)
	w.write_bits(3, 2)
	w.patch_bits(pos, 0xBEEF, 16)
	w.patch_bits(pos + 16, 1, 2)  # todavía en el acumulador
	var r := BitReader.new(w.get_bytes())
	assert_int(r.read_bits(8)).is_equal(0xAB)
	assert_int(r.read_bits(16)).is_equal(0xBEEF)
	assert_int(r.read_bits(2)).is_equal(1)


func test_read_past_end_sets_error() -> void:
	var r := BitReader.new(PackedByteArray([1]))
	r.read_bits(8)
	assert_bool(r.error).is_false()
	assert_int(r.read_bits(1)).is_equal(0)
	assert_bool(r.error).is_true()
	# Varint sin terminar.
	var r2 := BitReader.new(PackedByteArray([0x80, 0x80]))
	r2.read_varint()
	assert_bool(r2.error).is_true()
