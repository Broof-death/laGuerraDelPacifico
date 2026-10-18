class_name SelectionHud
extends CanvasLayer
## Interfaz mínima de la selección (T-007): el rectángulo de arrastre y un panel con el número y
## el tipo de las unidades seleccionadas, más el último aviso (orden enviada o rechazada). El HUD
## completo es de T-030. No consume el ratón: la entrada la maneja SelectionController.

## Dibuja el rectángulo de arrastre.
class DragRect:
	extends Control
	const FILL := Color(0.35, 1.0, 0.45, 0.12)
	const BORDER := Color(0.35, 1.0, 0.45, 0.9)
	var rect := Rect2()

	func _draw() -> void:
		if rect.size.x < 1.0 and rect.size.y < 1.0:
			return
		draw_rect(rect, FILL, true)
		draw_rect(rect, BORDER, false, 1.5)


var _drag: DragRect
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 5
	_drag = DragRect.new()
	_drag.name = "Arrastre"
	_drag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_drag)
	_panel = PanelContainer.new()
	_panel.name = "PanelSeleccion"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 12
	_panel.offset_bottom = -12
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)


func set_drag_rect(rect: Rect2) -> void:
	if _drag == null:
		return
	_drag.rect = rect.abs()
	_drag.queue_redraw()


func set_info(text: String) -> void:
	if _label == null:
		return
	_label.text = text
	_panel.visible = not text.is_empty()


## Texto del panel: "N seleccionadas" y el desglose por tipo (o la entidad inspeccionada).
static func describe(selection: UnitSelection, state: ClientState, game_data: GameData, my_player: int) -> String:
	if selection.is_empty():
		return ""
	var counts: Dictionary[int, int] = {}
	var order := PackedInt32Array()
	var first_slot: int = -1
	for id: int in selection.ids():
		var s: int = state.slot_of(id)
		if s < 0:
			continue
		if first_slot < 0:
			first_slot = s
		var d: int = state.def_index[s]
		if not counts.has(d):
			counts[d] = 0
			order.append(d)
		counts[d] += 1
	if first_slot < 0:
		return ""
	if selection.inspecting:
		var def: EntityDef = game_data.get_def(state.def_index[first_slot])
		var o: int = state.owner[first_slot]
		var who: String = "neutral" if o == SimConstants.NEUTRAL_PLAYER else ("aliado" if o == my_player else "jugador %d" % o)
		return "Inspección: %s (%s) · vida %d %%\nNo se le pueden dar órdenes" % [
			_name_of(def), who, roundi(state.hp_ratio[first_slot] * 100.0)]
	var total: int = 0
	var parts := PackedStringArray()
	for d: int in order:
		total += counts[d]
		parts.append("%d %s" % [counts[d], _name_of(game_data.get_def(d))])
	return "%d seleccionada%s: %s" % [total, "" if total == 1 else "s", ", ".join(parts)]


static func _name_of(def: EntityDef) -> String:
	if def == null:
		return "?"
	return def.display_name if not def.display_name.is_empty() else String(def.id)
