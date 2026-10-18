class_name UnitSelection
extends RefCounted
## Selección actual del jugador (T-007). Solo cliente: guarda ids de entidad, no slots, porque los
## slots de ClientState cambian al borrar entidades.
## - Selección propia: unidades del jugador, se les pueden dar órdenes.
## - Inspección: UNA entidad ajena (o neutral), solo para verla; no admite órdenes.
## Marca por id en un PackedByteArray para que is_selected() sea O(1) y barato en los bucles del
## renderizador.

signal changed()

## Cómo combinar una lista nueva con la selección actual.
enum Mode {
	## Reemplaza la selección.
	REPLACE,
	## Shift: suma las que faltan; si ya estaban todas, las quita.
	TOGGLE,
	## Suma sin quitar nada.
	ADD,
}

## true si la selección es una entidad ajena en inspección (sin órdenes).
var inspecting: bool = false

var _ids: Dictionary[int, bool] = {}
var _mark := PackedByteArray()
var _sorted := PackedInt32Array()
var _dirty: bool = false


func size() -> int:
	return _ids.size()


func is_empty() -> bool:
	return _ids.is_empty()


func is_selected(id: int) -> bool:
	return id > 0 and id < _mark.size() and _mark[id] != 0


## true si hay unidades propias seleccionadas (se les pueden dar órdenes).
func can_order() -> bool:
	return not inspecting and not _ids.is_empty()


## Ids seleccionados, ordenados de menor a mayor (listos para Command).
func ids() -> PackedInt32Array:
	if _dirty:
		_sorted = PackedInt32Array(_ids.keys())
		_sorted.sort()
		_dirty = false
	return _sorted


func clear() -> void:
	if _ids.is_empty() and not inspecting:
		return
	for id: int in _ids:
		_mark[id] = 0
	_ids.clear()
	inspecting = false
	_dirty = true
	changed.emit()


## Combina `new_ids` (unidades propias) con la selección según `mode`.
func apply(new_ids: PackedInt32Array, mode: Mode) -> void:
	if mode == Mode.REPLACE or inspecting:
		for id: int in _ids:
			_mark[id] = 0
		_ids.clear()
		inspecting = false
		_add_all(new_ids)
	elif mode == Mode.ADD:
		_add_all(new_ids)
	else:
		var all_in: bool = not new_ids.is_empty()
		for id: int in new_ids:
			if not _ids.has(id):
				all_in = false
				break
		if all_in:
			for id: int in new_ids:
				_ids.erase(id)
				_mark[id] = 0
		else:
			_add_all(new_ids)
	_dirty = true
	changed.emit()


## Selecciona una entidad ajena para inspeccionarla (reemplaza la selección).
func inspect(id: int) -> void:
	for old: int in _ids:
		_mark[old] = 0
	_ids.clear()
	_add_all(PackedInt32Array([id]))
	inspecting = true
	_dirty = true
	changed.emit()


## Quita las entidades que ya no están en el estado del cliente (muertas o fuera de la vista).
## Devuelve cuántas quitó.
func prune(state: ClientState) -> int:
	var gone := PackedInt32Array()
	for id: int in _ids:
		if state.slot_of(id) < 0:
			gone.append(id)
	for id: int in gone:
		_ids.erase(id)
		_mark[id] = 0
	if not gone.is_empty():
		if _ids.is_empty():
			inspecting = false
		_dirty = true
		changed.emit()
	return gone.size()


func _add_all(new_ids: PackedInt32Array) -> void:
	for id: int in new_ids:
		if id <= 0:
			continue
		if id >= _mark.size():
			var old: int = _mark.size()
			_mark.resize(maxi(id + 1, old * 2))
			for i: int in range(old, _mark.size()):
				_mark[i] = 0
		_ids[id] = true
		_mark[id] = 1
