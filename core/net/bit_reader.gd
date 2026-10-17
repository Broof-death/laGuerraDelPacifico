class_name BitReader
extends RefCounted
## Lectura por bits de lo que escribió BitWriter (LSB primero). Si se intenta leer más allá del
## final, devuelve 0 y marca `error`: el llamador descarta el paquete entero.

var data: PackedByteArray
var error: bool = false
var _byte_pos: int = 0
var _acc: int = 0
var _acc_bits: int = 0


func _init(p_data: PackedByteArray = PackedByteArray()) -> void:
	data = p_data


## Lee `bits` bits sin signo (1..32).
func read_bits(bits: int) -> int:
	while _acc_bits < bits:
		if _byte_pos >= data.size():
			error = true
			return 0
		_acc |= data[_byte_pos] << _acc_bits
		_byte_pos += 1
		_acc_bits += 8
	var v: int = _acc & ((1 << bits) - 1)
	_acc >>= bits
	_acc_bits -= bits
	return v


func read_bool() -> bool:
	return read_bits(1) == 1


## Entero con signo en complemento a dos de `bits` bits.
func read_signed(bits: int) -> int:
	var v: int = read_bits(bits)
	if v >= (1 << (bits - 1)):
		v -= 1 << bits
	return v


## Lee un varint. Marca error si es más largo de 5 grupos (valores de más de 35 bits).
func read_varint() -> int:
	var result: int = 0
	var shift: int = 0
	while true:
		var b: int = read_bits(8)
		if error:
			return 0
		result |= (b & 0x7F) << shift
		if b < 0x80:
			break
		shift += 7
		if shift > 28:
			error = true
			return 0
	return result


## Bits que quedan sin leer (incluye el relleno del último byte).
func bits_left() -> int:
	return (data.size() - _byte_pos) * 8 + _acc_bits
