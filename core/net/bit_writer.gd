class_name BitWriter
extends RefCounted
## Escritura por bits sobre un PackedByteArray (ADR-006 punto 5). Nunca usa var_to_bytes.
## Orden: el bit 0 del flujo es el bit menos significativo del byte 0 (LSB primero).
## Cada write_bits() admite hasta 32 bits; los enteros con signo se escriben en complemento a dos.

var data: PackedByteArray = PackedByteArray()
var _acc: int = 0
var _acc_bits: int = 0


## Escribe los `bits` bits bajos de `value` (1..32).
func write_bits(value: int, bits: int) -> void:
	_acc |= (value & ((1 << bits) - 1)) << _acc_bits
	_acc_bits += bits
	while _acc_bits >= 8:
		data.append(_acc & 0xFF)
		_acc >>= 8
		_acc_bits -= 8


func write_bool(value: bool) -> void:
	write_bits(1 if value else 0, 1)


## Entero con signo en `bits` bits (complemento a dos). El llamador garantiza el rango.
func write_signed(value: int, bits: int) -> void:
	write_bits(value, bits)


## Entero sin signo de tamaño variable: grupos de 7 bits con bit de continuación (8 bits cada uno).
func write_varint(value: int) -> void:
	var v: int = value
	while v >= 0x80:
		write_bits((v & 0x7F) | 0x80, 8)
		v >>= 7
	write_bits(v, 8)


## Bits escritos hasta ahora.
func bit_length() -> int:
	return data.size() * 8 + _acc_bits


## Bytes que ocupará el resultado.
func byte_length() -> int:
	return data.size() + (1 if _acc_bits > 0 else 0)


## Sobrescribe `bits` bits a partir de la posición `bit_pos` (ya escrita). Sirve para rellenar
## contadores que se conocen al final (cantidad de registros, cantidad de partes).
func patch_bits(bit_pos: int, value: int, bits: int) -> void:
	for i: int in bits:
		var p: int = bit_pos + i
		var bit: int = (value >> i) & 1
		var byte_i: int = p >> 3
		var mask: int = 1 << (p & 7)
		if byte_i < data.size():
			data[byte_i] = (data[byte_i] & ~mask) | (mask if bit == 1 else 0)
		else:
			var acc_i: int = p - data.size() * 8
			_acc = (_acc & ~(1 << acc_i)) | (bit << acc_i)


## Devuelve los bytes (con el último byte parcial completado con ceros). No altera el escritor.
func get_bytes() -> PackedByteArray:
	if _acc_bits == 0:
		return data.duplicate()
	var out := data.duplicate()
	out.append(_acc & 0xFF)
	return out


## Bits que ocupa un varint (múltiplo de 8).
static func varint_bits(value: int) -> int:
	var n: int = 8
	var v: int = value
	while v >= 0x80:
		v >>= 7
		n += 8
	return n
