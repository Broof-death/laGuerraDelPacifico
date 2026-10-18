extends Node3D
class_name RtsCamera
## Cámara RTS aérea e inclinada (T-006). Es SOLO del cliente: la simulación no la
## conoce ni la toca (ADR-006, ADR-007).
##
## Estructura: este nodo es el pivote, apoyado en el suelo (y = 0) en el punto que
## se mira; su rotación Y es el rumbo de la cámara. El hijo Camera3D se coloca
## detrás y arriba del pivote según el zoom.
##
## Controles (acciones camera_* del InputMap):
## - Flechas: desplazar. También el borde de la pantalla (desactivable). WASD dejó de mover la
##   cámara en T-007: A y S son órdenes (ataque en movimiento y alto).
## - Botón central + arrastrar: arrastrar el mapa.
## - Alt + botón central + arrastrar, o Q / E: rotar.
## - Rueda: zoom suavizado; la inclinación cambia con el zoom.
## La velocidad de desplazamiento es proporcional a la distancia al suelo.

signal focus_changed(focus: Vector3)  ## Para el minimapa y el streaming del terreno.

const MIN_NEAR := 0.3            ## Plano cercano mínimo (m)
const NEAR_PER_DISTANCE := 0.04  ## Plano cercano = distancia x este factor

# --- Desplazamiento -----------------------------------------------------------
## Velocidad de desplazamiento, en distancias de cámara por segundo (a 100 m de
## distancia y valor 1,0 se recorren 100 m/s). Lo ajusta la pantalla de Configuración.
@export_range(0.1, 5.0, 0.05) var pan_speed: float = 1.0
@export var edge_scroll_enabled: bool = true    ## Desplazar al acercar el ratón al borde
@export_range(1, 100) var edge_scroll_margin: int = 12  ## Ancho del borde en píxeles
## Límites del mapa en el plano XZ (x, z). Por defecto, el mundo de ADR-009
## (131 072 m centrados en el origen). El pivote nunca sale de aquí.
@export var map_bounds: Rect2 = Rect2(-65536.0, -65536.0, 131072.0, 131072.0)

# --- Zoom ---------------------------------------------------------------------
@export var min_distance: float = 15.0          ## Distancia mínima al pivote (m)
@export var max_distance: float = 1500.0        ## Distancia máxima al pivote (m)
@export_range(0.0, 1.0) var initial_zoom: float = 0.45  ## 0 = cerca, 1 = lejos
@export_range(0.01, 0.5) var zoom_step: float = 0.06    ## Avance por clic de la rueda
## Inclinación bajo el horizonte (grados) con el zoom mínimo y con el máximo.
@export_range(5.0, 89.0) var pitch_near_deg: float = 20.0
@export_range(5.0, 89.0) var pitch_far_deg: float = 65.0

# --- Rotación -----------------------------------------------------------------
@export var rotate_speed_deg: float = 90.0      ## Q / E, en grados por segundo
@export var rotate_drag_sensitivity: float = 0.3  ## Alt + arrastre, grados por píxel

# --- Suavizado ----------------------------------------------------------------
## Rapidez con que el estado actual alcanza al objetivo (1/s). Más alto = más seco.
@export var smoothing: float = 10.0

var _target_focus: Vector3
var _target_zoom: float
var _target_yaw: float
var _zoom: float
var _dragging: bool = false
var _mouse_inside: bool = false  # solo hay desplazamiento por borde si el ratón está en la ventana

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	position.y = 0.0
	position = clamp_focus(position, map_bounds)
	_target_focus = position
	_target_yaw = rotation.y
	_target_zoom = clampf(initial_zoom, 0.0, 1.0)
	_zoom = _target_zoom
	_apply_camera_transform()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_mouse_inside = false
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_inside = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clampf(_target_zoom - zoom_step, 0.0, 1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clampf(_target_zoom + zoom_step, 0.0, 1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_drag"):
		_dragging = true
	elif event.is_action_released("camera_drag"):
		_dragging = false
	elif event is InputEventMouseMotion:
		_mouse_inside = true
		if _dragging:
			_on_drag((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_handle_keyboard_and_edges(delta)

	# Acercar el estado actual al objetivo con un decaimiento exponencial:
	# suave e independiente de los FPS.
	var w := 1.0 - exp(-smoothing * delta)
	var old_focus := position
	position = position.lerp(_target_focus, w)
	rotation.y = lerp_angle(rotation.y, _target_yaw, w)
	_zoom = lerpf(_zoom, _target_zoom, w)
	_apply_camera_transform()
	if not position.is_equal_approx(old_focus):
		focus_changed.emit(position)


## Lleva la cámara a `world_pos` (para el minimapa o los saltos de cámara).
## Con `instant` no hay transición.
func focus_on(world_pos: Vector3, instant: bool = false) -> void:
	_target_focus = clamp_focus(Vector3(world_pos.x, 0.0, world_pos.z), map_bounds)
	if instant:
		position = _target_focus
		_apply_camera_transform()


## Fija el zoom (0 = cerca, 1 = lejos). Con `instant` no hay transición.
func set_zoom(t: float, instant: bool = false) -> void:
	_target_zoom = clampf(t, 0.0, 1.0)
	if instant:
		_zoom = _target_zoom
		_apply_camera_transform()


## Fija el rumbo (radianes, rotación Y). Con `instant` no hay transición.
func set_yaw(yaw: float, instant: bool = false) -> void:
	_target_yaw = yaw
	if instant:
		rotation.y = yaw


## Distancia actual de la cámara al pivote, en metros.
func get_distance() -> float:
	return distance_for_zoom(_zoom, min_distance, max_distance)


func _handle_keyboard_and_edges(delta: float) -> void:
	var dir := Input.get_vector("camera_pan_left", "camera_pan_right",
			"camera_pan_forward", "camera_pan_back")
	if edge_scroll_enabled and _mouse_inside and not _dragging:
		dir += _edge_direction()
	if dir != Vector2.ZERO:
		dir = dir.limit_length(1.0)
		var step := pan_speed * get_distance() * delta
		_move_focus(Vector3(dir.x, 0.0, dir.y) * step)

	var rot := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	if rot != 0.0:
		_target_yaw += deg_to_rad(rotate_speed_deg) * rot * delta


func _edge_direction() -> Vector2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	var dir := Vector2.ZERO
	if m.x < 0.0 or m.y < 0.0 or m.x > size.x or m.y > size.y:
		return dir
	if m.x <= edge_scroll_margin:
		dir.x -= 1.0
	elif m.x >= size.x - edge_scroll_margin:
		dir.x += 1.0
	if m.y <= edge_scroll_margin:
		dir.y -= 1.0
	elif m.y >= size.y - edge_scroll_margin:
		dir.y += 1.0
	return dir


func _on_drag(relative: Vector2) -> void:
	if Input.is_action_pressed("camera_rotate_modifier"):
		_target_yaw -= deg_to_rad(relative.x * rotate_drag_sensitivity)
		return
	# Metros de suelo por píxel en el centro de la pantalla: el mapa sigue al ratón.
	var h := get_viewport().get_visible_rect().size.y
	var meters_per_px := 2.0 * get_distance() * tan(deg_to_rad(camera.fov) * 0.5) / maxf(h, 1.0)
	_move_focus(Vector3(-relative.x, 0.0, -relative.y) * meters_per_px)
	position = _target_focus  # el arrastre va 1:1, sin suavizado


## Mueve el objetivo según un desplazamiento local (x a la derecha, z hacia atrás).
func _move_focus(local_offset: Vector3) -> void:
	var world := local_offset.rotated(Vector3.UP, _target_yaw)
	_target_focus = clamp_focus(_target_focus + world, map_bounds)


func _apply_camera_transform() -> void:
	if camera == null:
		return
	var d := distance_for_zoom(_zoom, min_distance, max_distance)
	var pitch := deg_to_rad(pitch_for_zoom(_zoom, pitch_near_deg, pitch_far_deg))
	camera.position = Vector3(0.0, sin(pitch) * d, cos(pitch) * d)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	# Plano cercano proporcional a la distancia: conserva la precisión del búfer
	# de profundidad (24 bits en GL Compatibility) entre el agua y la costa al alejarse.
	camera.near = maxf(MIN_NEAR, d * NEAR_PER_DISTANCE)


# --- Funciones puras (se pueden probar sin ventana) -----------------------------

## Acota el punto de foco a los límites del mapa (en XZ) y lo deja en y = 0.
static func clamp_focus(p: Vector3, bounds: Rect2) -> Vector3:
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(p.z, bounds.position.y, bounds.end.y))


## Distancia de la cámara para un zoom t en [0, 1]. Es exponencial, para que cada
## clic de la rueda se sienta igual de cerca y de lejos.
static func distance_for_zoom(t: float, near: float, far: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return near * pow(far / near, t)


## Inclinación bajo el horizonte (grados) para un zoom t en [0, 1].
static func pitch_for_zoom(t: float, near_deg: float, far_deg: float) -> float:
	return lerpf(near_deg, far_deg, clampf(t, 0.0, 1.0))
