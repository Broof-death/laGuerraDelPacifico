class_name PlaceholderView
extends EntityView
## Representación provisional (ADR-005, ADR-007): la forma de placeholder_shape/size con el color
## del bando, más la etiqueta (placeholder_label) y la barra de vida de EntityView. Se usa siempre
## que view_scene_path esté vacío o no cargue.

## Materiales compartidos por color (todas las vistas del mismo bando usan el mismo).
static var _materials: Dictionary[Color, StandardMaterial3D] = {}

var _body: MeshInstance3D


func _build() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Cuerpo"
	_body.mesh = PlaceholderMeshes.build(def.placeholder_shape, def.placeholder_size, PlaceholderMeshes.Lod.FULL)
	add_child(_body)


func _apply_team_color() -> void:
	super._apply_team_color()
	if _body != null:
		_body.material_override = material_for(team_color)


## Material provisional opaco de un color (compartido).
static func material_for(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = _materials.get(color)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		_materials[color] = m
	return m


## Vacía la caché de materiales (al cerrar la partida, para no retenerlos entre escenas).
static func clear_cache() -> void:
	_materials.clear()
