class_name FormationLayout
extends RefCounted
## Posiciones relativas de las unidades de un grupo de movimiento (ADR-006 punto 3).
## Es código compartido: el servidor lo usa para repartir destinos y el cliente puede usarlo
## para dibujar el marcador de la orden. Solo hay una formación (0 = bloque) por ahora.


## Desplazamientos (x, z) en metros para `count` unidades, en un bloque centrado en el destino
## y orientado según `forward` (dirección de marcha, no hace falta normalizarla).
## La primera fila es la del frente; dentro de cada fila, de izquierda a derecha.
static func offsets(count: int, spacing: float, forward: Vector2, _formation: int = 0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	out.resize(count)
	var fwd := forward.normalized() if forward.length_squared() > 0.0001 else Vector2(0.0, 1.0)
	# Derecha respecto de la marcha en el plano x,z.
	var right := Vector2(-fwd.y, fwd.x)
	# Bloque más ancho que profundo: unas 2 columnas por fila.
	var cols: int = maxi(1, ceili(sqrt(count * 2.0)))
	var rows: int = ceili(float(count) / cols)
	var half_w: float = (cols - 1) * 0.5
	var half_d: float = (rows - 1) * 0.5
	for i: int in count:
		var r: int = i / cols
		var c: int = i % cols
		var lateral: float = (c - half_w) * spacing
		var depth: float = (half_d - r) * spacing
		out[i] = right * lateral + fwd * depth
	return out
