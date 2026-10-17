class_name EntityViewPool
extends RefCounted
## Pool limitado de vistas individuales (ADR-006 punto 7: como máximo 256). Solo cliente.
## Las vistas se crean bajo demanda con `factory` (def_index, color de bando -> EntityView), se
## agregan como hijas de `parent` y, al liberarse, quedan ocultas en una lista libre por def_index
## para reutilizarlas. Si se llega al máximo y no hay ninguna libre del mismo def_index, se
## destruye una libre de otra definición; si no hay ninguna libre, acquire() devuelve null y la
## entidad se queda en los lotes.

const DEFAULT_MAX_VIEWS: int = 256

var parent: Node
var factory: Callable
var max_views: int = DEFAULT_MAX_VIEWS
## Vistas creadas en total (en uso y libres).
var total: int = 0
## Vistas creadas desde el inicio (para medir la reutilización).
var created: int = 0

var _by_id: Dictionary[int, EntityView] = {}
var _free: Dictionary[int, Array] = {}
var _free_count: int = 0


func _init(p_parent: Node, p_factory: Callable, p_max_views: int = DEFAULT_MAX_VIEWS) -> void:
	parent = p_parent
	factory = p_factory
	max_views = p_max_views


func in_use() -> int:
	return _by_id.size()


func free_count() -> int:
	return _free_count


func get_view(entity_id: int) -> EntityView:
	return _by_id.get(entity_id)


func has_view(entity_id: int) -> bool:
	return _by_id.has(entity_id)


## Ids de las entidades que tienen vista.
func assigned_ids() -> PackedInt32Array:
	return PackedInt32Array(_by_id.keys())


## Vista para `entity_id` (la que ya tenía, una libre del mismo def o una nueva). null si el pool
## está lleno.
func acquire(entity_id: int, def_index: int, team_color: Color) -> EntityView:
	var v: EntityView = _by_id.get(entity_id)
	if v != null:
		return v
	var list: Array = _free.get(def_index, [])
	if not list.is_empty():
		v = list.pop_back()
		_free_count -= 1
	else:
		if total >= max_views and not _evict_one_free():
			return null
		v = factory.call(def_index, team_color)
		if v == null:
			return null
		total += 1
		created += 1
		parent.add_child(v)
	v.set_meta(&"def_index", def_index)
	v.reset_for(entity_id, team_color)
	v.visible = true
	_by_id[entity_id] = v
	return v


## Devuelve la vista de `entity_id` a la lista libre (oculta).
func release(entity_id: int) -> void:
	var v: EntityView = _by_id.get(entity_id)
	if v == null:
		return
	_by_id.erase(entity_id)
	v.visible = false
	v.set_details_visible(false)
	v.entity_id = 0
	var d: int = v.get_meta(&"def_index", -1)
	if not _free.has(d):
		_free[d] = []
	_free[d].append(v)
	_free_count += 1


## Libera las vistas cuyas entidades no están en `keep` (id -> cualquier valor).
func release_except(keep: Dictionary) -> void:
	for id: int in _by_id.keys():
		if not keep.has(id):
			release(id)


func release_all() -> void:
	for id: int in _by_id.keys():
		release(id)


func _evict_one_free() -> bool:
	for d: int in _free:
		var list: Array = _free[d]
		if list.is_empty():
			continue
		var v: EntityView = list.pop_back()
		_free_count -= 1
		total -= 1
		v.queue_free()
		return true
	return false
