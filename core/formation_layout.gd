class_name FormationLayout
extends RefCounted
## Formaciones de los grupos de movimiento (ADR-006 punto 3, T-018). Código compartido: el
## servidor reparte con él los puestos de un grupo y el cliente puede usarlo para dibujar la
## vista previa de una orden con los mismos huecos (con las posiciones que ve, que pueden diferir
## un poco de las del servidor, así que la asignación puede cambiar en algún puesto).
##
## Formación 0 (la única por ahora): BLOQUE de filas y columnas orientado hacia el destino, unas
## dos columnas por fila (más ancho que profundo). El hueco entre puestos sale del radio mayor del
## grupo (spacing_for). La última fila, si queda incompleta, va centrada.
##
## Asignación de puestos (assign): las unidades que van más adelante (proyección sobre la dirección
## de marcha) toman la primera fila, y dentro de cada fila se ordenan de izquierda a derecha. Así
## casi nadie cruza la formación para llegar a su puesto, y la evitación local tiene poco trabajo.
## Determinista: el orden se decide con claves enteras y desempate por índice.

## Hueco entre centros = SPACING_FACTOR x radio (2 radios + medio radio de aire entre unidades).
const SPACING_FACTOR: float = 2.5
## Hueco mínimo en metros (unidades muy chicas).
const MIN_SPACING: float = 1.0


## Distancia entre puestos vecinos para unidades de radio `radius`.
static func spacing_for(radius: float) -> float:
	return maxf(MIN_SPACING, radius * SPACING_FACTOR)


## Columnas del bloque para `count` unidades.
static func columns(count: int) -> int:
	return maxi(1, ceili(sqrt(count * 2.0)))


## Dirección de marcha normalizada (hacia +Z si `forward` es casi nula).
static func direction(forward: Vector2) -> Vector2:
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector2(0.0, 1.0)


## Desplazamientos (x, z) en metros de los puestos 0..count-1, en un bloque centrado en el destino
## y orientado según `forward` (dirección de marcha, no hace falta normalizarla).
## El puesto 0 es el de la izquierda de la primera fila (la del frente); luego de izquierda a
## derecha y fila por fila.
static func offsets(count: int, spacing: float, forward: Vector2, _formation: int = 0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	out.resize(count)
	var fwd := direction(forward)
	# Derecha respecto de la marcha en el plano x,z.
	var right := Vector2(-fwd.y, fwd.x)
	var cols: int = columns(count)
	var rows: int = ceili(float(count) / cols)
	var half_d: float = (rows - 1) * 0.5
	for i: int in count:
		var r: int = i / cols
		var c: int = i % cols
		var in_row: int = mini(cols, count - r * cols)
		var lateral: float = (c - (in_row - 1) * 0.5) * spacing
		var depth: float = (half_d - r) * spacing
		out[i] = right * lateral + fwd * depth
	return out


## Puesto (índice de offsets) de cada unidad según su posición actual: las de más adelante a la
## primera fila y, dentro de la fila, de izquierda a derecha. `positions[i]` es la unidad i
## (como mucho 65 536 unidades).
static func assign(positions: PackedVector2Array, forward: Vector2) -> PackedInt32Array:
	var count: int = positions.size()
	var out := PackedInt32Array()
	out.resize(count)
	if count == 0:
		return out
	var fwd := direction(forward)
	var right := Vector2(-fwd.y, fwd.x)
	var cols: int = columns(count)
	# Filas: de mayor a menor avance (clave = -avance cuantizado a 1/16 m, desempate por índice).
	var keys := PackedInt64Array()
	keys.resize(count)
	for i: int in count:
		keys[i] = (_quant(-positions[i].dot(fwd)) << 16) | i
	keys.sort()
	var row_keys := PackedInt64Array()
	for start: int in range(0, count, cols):
		var end: int = mini(start + cols, count)
		row_keys.resize(end - start)
		for k: int in range(start, end):
			var i: int = keys[k] & 0xFFFF
			row_keys[k - start] = (_quant(positions[i].dot(right)) << 16) | i
		row_keys.sort()
		for k: int in row_keys.size():
			out[row_keys[k] & 0xFFFF] = start + k
	return out


## Destinos (x, z) de cada unidad: el destino del grupo más el desplazamiento de su puesto, con la
## formación orientada desde el centro del grupo hacia el destino. Es lo que usa el servidor (y lo
## que puede dibujar el cliente como vista previa de la orden).
static func destinations(positions: PackedVector2Array, target: Vector2, radius: float, formation: int = 0) -> PackedVector2Array:
	var count: int = positions.size()
	var center := Vector2.ZERO
	for p: Vector2 in positions:
		center += p
	if count > 0:
		center /= count
	var forward := target - center
	var offs := offsets(count, spacing_for(radius), forward, formation)
	var slots := assign(positions, forward)
	var out := PackedVector2Array()
	out.resize(count)
	for i: int in count:
		out[i] = target + offs[slots[i]]
	return out


## Proyección (m) a entero no negativo con paso de 1/16 m.
static func _quant(v: float) -> int:
	return int(floor((v + 1048576.0) * 16.0))
