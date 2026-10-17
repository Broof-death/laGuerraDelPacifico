class_name EntityDef
extends Resource
## Base común de UnitDef y BuildingDef (ADR-007). Solo lectura durante la partida:
## el estado cambiante vive en el EntityStore de la simulación.

enum PlaceholderShape { BOX, CYLINDER, CAPSULE, HULL }

## Igual al nombre del archivo y único en todo el juego (snake_case en español).
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var max_hp: int = 100
@export var armor: int = 0
## Alcance de visión en metros.
@export var vision_range: float = 100.0
@export var cost: Dictionary[ResourceDef, int] = {}
## Tiempo de construcción o entrenamiento en segundos.
@export var build_time: float = 10.0
@export var weapons: Array[WeaponDef] = []

@export_group("Solo visual")
## Escena de la vista individual; vacío = representación provisional. El servidor no la usa.
@export_file("*.tscn") var view_scene_path: String = ""
@export var placeholder_shape: PlaceholderShape = PlaceholderShape.BOX
@export var placeholder_size: Vector3 = Vector3.ONE
@export var placeholder_label: String = ""
@export var icon: Texture2D
