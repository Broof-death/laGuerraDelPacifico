class_name EntityView
extends Node3D
## Vista INDIVIDUAL de una entidad (ADR-007 punto 2, ADR-006 punto 7). Solo cliente.
## Se usa para edificios, buques y unidades cercanas a la cámara, desde un pool de como máximo
## 256 vistas que se reasignan (EntityViewPool); el resto se dibuja por lotes (UnitBatchRenderer).
##
## Contrato:
## - setup(def, faction, team_color) una vez, al crearla. reset_for(entity_id, team_color) cada vez
##   que el pool la reasigna a otra entidad de la misma definición.
## - apply_state(action, hp_ratio, progress) en cada frame mientras está asignada.
## - La posición y el rumbo los pone quien la maneja (UnitBatchRenderer) con los valores
##   interpolados de ClientState.
## - Nunca emite comandos ni toca la simulación.
##
## El arte final es una escena nueva que hereda de esta clase (o una escena cualquiera, que el
## catálogo envuelve en una EntityView) y se indica en EntityDef.view_scene_path. La etiqueta y la
## barra de vida son de esta base: solo se muestran en las vistas cercanas o seleccionadas
## (set_details_visible).

const BAR_WIDTH_PX: int = 64
const BAR_HEIGHT_PX: int = 7
## Tamaño de la barra en metros por píxel de su textura.
const BAR_PIXEL_SIZE: float = 0.03

static var _bar_texture: ImageTexture

var def: EntityDef
var faction: FactionDef
var team_color: Color = Color.WHITE
var entity_id: int = 0
var details_visible: bool = false

var _label: Label3D
var _bar_bg: Sprite3D
var _bar_fill: Sprite3D
var _hp: float = -1.0


## Prepara la vista para una definición. `p_team_color` con alfa 0 = usar faction.color.
func setup(p_def: EntityDef, p_faction: FactionDef, p_team_color: Color = Color(0, 0, 0, 0)) -> void:
	def = p_def
	faction = p_faction
	team_color = p_team_color if p_team_color.a > 0.0 else (faction.color if faction != null else Color.WHITE)
	_build()
	_apply_team_color()
	set_details_visible(false)


## Reasigna la vista a otra entidad (mismo def). Lo llama el pool.
func reset_for(p_entity_id: int, p_team_color: Color) -> void:
	entity_id = p_entity_id
	_hp = -1.0
	if p_team_color != team_color:
		team_color = p_team_color
		_apply_team_color()


## Estado que llega del servidor (ClientState). Las subclases con animaciones lo amplían.
func apply_state(_action: int, hp_ratio: float, _progress: float) -> void:
	if details_visible and absf(hp_ratio - _hp) > 0.004:
		_hp = hp_ratio
		_update_bar()


## Etiqueta y barra de vida: solo en las vistas cercanas o seleccionadas (ADR-006 punto 7).
func set_details_visible(v: bool) -> void:
	if v and _label == null:
		_build_details()
	details_visible = v
	if _label != null:
		_label.visible = v
		_bar_bg.visible = v
		_bar_fill.visible = v
		if v:
			_hp = -1.0


## Altura de la etiqueta y la barra sobre el origen de la vista.
func overlay_height() -> float:
	if def == null:
		return 3.0
	var h: float = def.placeholder_size.y
	if def is UnitDef and (def as UnitDef).domain == UnitDef.Domain.SEA:
		h *= 1.0 - PlaceholderMeshes.HULL_DRAFT
	return h + 1.2


## Virtual: crea el cuerpo de la vista (malla, escena de arte final...).
func _build() -> void:
	pass


## Virtual: aplica team_color al cuerpo.
func _apply_team_color() -> void:
	if _label != null:
		_label.outline_modulate = team_color.darkened(0.6)


func _build_details() -> void:
	var y: float = overlay_height()
	_label = Label3D.new()
	_label.name = "Etiqueta"
	_label.text = _label_text()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.025
	_label.font_size = 28
	_label.outline_size = 8
	_label.outline_modulate = team_color.darkened(0.6)
	_label.position = Vector3(0.0, y + 0.45, 0.0)
	_label.render_priority = 2
	add_child(_label)
	_bar_bg = _make_bar_sprite(Color(0.08, 0.08, 0.08, 0.85), 0)
	_bar_bg.position = Vector3(0.0, y, 0.0)
	add_child(_bar_bg)
	_bar_fill = _make_bar_sprite(Color(0.25, 0.85, 0.3), 1)
	_bar_fill.position = Vector3(0.0, y, 0.0)
	add_child(_bar_fill)


func _label_text() -> String:
	if def == null:
		return ""
	return def.placeholder_label if not def.placeholder_label.is_empty() else def.display_name


func _make_bar_sprite(color: Color, priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _get_bar_texture()
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.centered = false
	s.offset = Vector2(-BAR_WIDTH_PX * 0.5, -BAR_HEIGHT_PX * 0.5)
	s.pixel_size = BAR_PIXEL_SIZE
	s.render_priority = priority
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, BAR_WIDTH_PX, BAR_HEIGHT_PX)
	return s


func _update_bar() -> void:
	if _bar_fill == null:
		return
	var hp: float = clampf(_hp, 0.0, 1.0)
	_bar_fill.region_rect = Rect2(0, 0, maxf(1.0, round(BAR_WIDTH_PX * hp)), BAR_HEIGHT_PX)
	_bar_fill.modulate = Color(0.85, 0.2, 0.15) if hp < 0.35 else (Color(0.9, 0.75, 0.2) if hp < 0.7 else Color(0.25, 0.85, 0.3))


## Libera la textura compartida de las barras de vida.
static func clear_cache() -> void:
	_bar_texture = null


static func _get_bar_texture() -> ImageTexture:
	if _bar_texture == null:
		var img := Image.create(BAR_WIDTH_PX, BAR_HEIGHT_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bar_texture = ImageTexture.create_from_image(img)
	return _bar_texture
