extends Control
class_name Menu
## Menú principal: fondo negro (reemplazable por una imagen) y botones Comenzar / Cerrar.
## Al hacer click en un botón queda marcado como seleccionado con borde rojo.

const BORDER_WIDTH := 3
const BORDER_COLOR := Color(0.35, 0.35, 0.35)      ## Borde de un botón no seleccionado
const SELECTED_BORDER_COLOR := Color(0.85, 0.1, 0.1) ## Borde del botón seleccionado
const BUTTON_COLOR := Color(0.12, 0.12, 0.12)
const BUTTON_HOVER_COLOR := Color(0.2, 0.2, 0.2)

@export var background_texture: Texture2D:       ## Imagen de fondo; si queda vacía se ve el fondo negro
	set(value):
		background_texture = value
		if is_node_ready():
			_apply_background()
@export_file("*.tscn") var start_scene: String = "res://node_3d.tscn"  ## Escena que carga "Comenzar"

var _selected_button: Button

@onready var _background_image: TextureRect = $BackgroundImage
@onready var _start_button: Button = $Buttons/StartButton
@onready var _quit_button: Button = $Buttons/QuitButton


func _ready() -> void:
	_apply_background()
	for button: Button in [_start_button, _quit_button]:
		_apply_button_style(button, false)
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()


func _apply_background() -> void:
	_background_image.texture = background_texture
	_background_image.visible = background_texture != null


## Marca `button` como seleccionado (borde rojo) y desmarca el anterior.
func _select(button: Button) -> void:
	if _selected_button == button:
		return
	if _selected_button:
		_apply_button_style(_selected_button, false)
	_selected_button = button
	_apply_button_style(button, true)


func _apply_button_style(button: Button, selected: bool) -> void:
	var border := SELECTED_BORDER_COLOR if selected else BORDER_COLOR
	button.add_theme_stylebox_override("normal", _make_style(BUTTON_COLOR, border))
	button.add_theme_stylebox_override("hover", _make_style(BUTTON_HOVER_COLOR, border))
	button.add_theme_stylebox_override("pressed", _make_style(BUTTON_HOVER_COLOR, SELECTED_BORDER_COLOR))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(6)
	return style


func _on_start_pressed() -> void:
	_select(_start_button)
	if start_scene.is_empty():
		push_warning("Menu: no hay escena asignada a 'start_scene'.")
		return
	get_tree().change_scene_to_file(start_scene)


func _on_quit_pressed() -> void:
	_select(_quit_button)
	# Cierra la ventana y termina el proceso del juego.
	get_tree().quit()
