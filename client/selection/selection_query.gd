class_name SelectionQuery
extends RefCounted
## Consultas de selección sobre el estado del cliente (ClientState), por proyección de posiciones
## a la pantalla: sin colisionadores ni nodos por unidad (ADR-006 punto 7, T-007). Solo cliente.
## - in_rect(): las entidades de un jugador cuyo centro proyectado cae en un rectángulo de pantalla.
##   Si hay unidades, los edificios se descartan (como en cualquier RTS).
## - pick(): la entidad más cercana a un punto de la pantalla, dentro de un radio.
## - same_type_on_screen(): las de un jugador y una definición que se ven en pantalla.
## Las tablas por def_index (altura del centro, radio, si se mueve) salen de GameData; en las
## pruebas se pueden llenar a mano. Un def_index sin datos usa los valores por defecto.
##
## El bucle de in_rect() no divide: compara las coordenadas de recorte con los bordes del
## rectángulo en NDC multiplicados por w (ver la medición en tests/client/test_selection.gd).

## Radio mínimo, en píxeles, para acertar a una entidad con un clic.
const PICK_RADIUS_PX: float = 14.0
const DEFAULT_HEIGHT: float = 1.0
const DEFAULT_RADIUS: float = 1.0

## Altura (m) del punto que se proyecta: el centro del cuerpo.
var height_by_def := PackedFloat32Array()
## Radio (m) en el plano, para el clic sobre entidades grandes (buques, edificios).
var radius_by_def := PackedFloat32Array()
## 1 = unidad (se mueve y recibe órdenes), 0 = edificio.
var mobile_by_def := PackedByteArray()


static func from_game_data(gd: GameData) -> SelectionQuery:
	var q := SelectionQuery.new()
	var n: int = gd.def_count()
	q.height_by_def.resize(n)
	q.radius_by_def.resize(n)
	q.mobile_by_def.resize(n)
	for d: int in n:
		var def: EntityDef = gd.get_def(d)
		var size: Vector3 = def.placeholder_size if def != null else Vector3.ONE
		var mobile: bool = def is UnitDef
		var h: float = size.y * 0.5
		if mobile and (def as UnitDef).domain == UnitDef.Domain.SEA:
			h = size.y * (0.5 - PlaceholderMeshes.HULL_DRAFT)
		q.height_by_def[d] = maxf(h, 0.2)
		q.radius_by_def[d] = maxf(maxf(size.x, size.z) * 0.5, 0.5)
		q.mobile_by_def[d] = 1 if mobile else 0
	return q


func height_of(def_index: int) -> float:
	return height_by_def[def_index] if def_index >= 0 and def_index < height_by_def.size() else DEFAULT_HEIGHT


func radius_of(def_index: int) -> float:
	return radius_by_def[def_index] if def_index >= 0 and def_index < radius_by_def.size() else DEFAULT_RADIUS


func is_mobile(def_index: int) -> bool:
	return mobile_by_def[def_index] == 1 if def_index >= 0 and def_index < mobile_by_def.size() else true


## Ids de las entidades de `owner_id` cuyo centro proyectado cae dentro de `rect` (píxeles). Si
## entre ellas hay unidades, se devuelven solo las unidades; si no, los edificios.
func in_rect(state: ClientState, proj: ScreenProjector, rect: Rect2, owner_id: int) -> PackedInt32Array:
	var r := rect.abs()
	var sx: float = proj.size.x
	var sy: float = proj.size.y
	# Bordes del rectángulo en NDC (y hacia arriba).
	var x0: float = r.position.x / sx * 2.0 - 1.0
	var x1: float = r.end.x / sx * 2.0 - 1.0
	var y_top: float = 1.0 - r.position.y / sy * 2.0
	var y_bot: float = 1.0 - r.end.y / sy * 2.0
	var m: Projection = proj.m
	var mxx: float = m.x.x; var myx: float = m.y.x; var mzx: float = m.z.x; var mwx: float = m.w.x
	var mxy: float = m.x.y; var myy: float = m.y.y; var mzy: float = m.z.y; var mwy: float = m.w.y
	var mxw: float = m.x.w; var myw: float = m.y.w; var mzw: float = m.z.w; var mww: float = m.w.w
	var owners := state.owner
	var defs := state.def_index
	var rx := state.render_x
	var rz := state.render_z
	var heights := height_by_def
	var nh: int = heights.size()
	var mobile := mobile_by_def
	var ids := state.ids
	var units := PackedInt32Array()
	var buildings := PackedInt32Array()
	for s: int in state.count:
		if owners[s] != owner_id:
			continue
		var d: int = defs[s]
		var px: float = rx[s]
		var pz: float = rz[s]
		var py: float = heights[d] if d < nh else DEFAULT_HEIGHT
		var cw: float = mxw * px + myw * py + mzw * pz + mww
		if cw <= 0.0:
			continue
		var cx: float = mxx * px + myx * py + mzx * pz + mwx
		if cx < x0 * cw or cx > x1 * cw:
			continue
		var cy: float = mxy * px + myy * py + mzy * pz + mwy
		if cy > y_top * cw or cy < y_bot * cw:
			continue
		if d >= nh or mobile[d] == 1:
			units.append(ids[s])
		else:
			buildings.append(ids[s])
	return units if not units.is_empty() else buildings


## Slot de la entidad (de cualquier jugador) más cercana a `point` en pantalla, si su centro
## proyectado está a menos de max(min_radius_px, radio proyectado). -1 si no hay ninguna.
func pick(state: ClientState, proj: ScreenProjector, point: Vector2, min_radius_px: float = PICK_RADIUS_PX) -> int:
	var best: int = -1
	var best_d2: float = INF
	var defs := state.def_index
	var rx := state.render_x
	var rz := state.render_z
	for s: int in state.count:
		var d: int = defs[s]
		var sp: Vector3 = proj.project(Vector3(rx[s], height_of(d), rz[s]))
		if sp.z <= 0.0:
			continue
		var r: float = maxf(min_radius_px, radius_of(d) * proj.focal_px / sp.z)
		var dx: float = sp.x - point.x
		var dy: float = sp.y - point.y
		var d2: float = dx * dx + dy * dy
		if d2 <= r * r and d2 < best_d2:
			best_d2 = d2
			best = s
	return best


## Ids de las entidades de `owner_id` con `def_index` cuyo centro se ve en pantalla.
func same_type_on_screen(state: ClientState, proj: ScreenProjector, def_index: int, owner_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var h: float = height_of(def_index)
	for s: int in state.count:
		if state.owner[s] != owner_id or state.def_index[s] != def_index:
			continue
		var sp: Vector3 = proj.project(Vector3(state.render_x[s], h, state.render_z[s]))
		if sp.z > 0.0 and sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= proj.size.x and sp.y <= proj.size.y:
			out.append(state.ids[s])
	return out
