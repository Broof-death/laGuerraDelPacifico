extends Control
class_name MainMenu
## Menú principal: fondo negro (reemplazable por una imagen) y botones Comenzar / Cerrar.

@export var background_texture: Texture2D:       ## Imagen de fondo; si queda vacía se ve el fondo negro
	set(value):
		background_texture = value
		if is_node_ready():
			_apply_background()
@export_file("*.tscn") var start_scene: String = "res://node_3d.tscn"  ## Escena que carga "Comenzar"

@onready var _background_image: TextureRect = $BackgroundImage
@onready var _start_button: Button = $Buttons/StartButton
@onready var _quit_button: Button = $Buttons/QuitButton


func _ready() -> void:
	_apply_background()
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()


func _apply_background() -> void:
	_background_image.texture = background_texture
	_background_image.visible = background_texture != null


func _on_start_pressed() -> void:
	if start_scene.is_empty():
		push_warning("MainMenu: no hay escena asignada a 'start_scene'.")
		return
	get_tree().change_scene_to_file(start_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
