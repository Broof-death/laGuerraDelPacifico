class_name FactionDef
extends Resource
## Facción jugable (ADR-003, ADR-007). Las bonificaciones propias se agregan cuando el GDD las defina.

@export var id: StringName = &""
@export var display_name: String = ""
## Color del bando para lo provisional (ADR-005).
@export var color: Color = Color.WHITE
@export var flag: Texture2D
@export var units: Array[UnitDef] = []
@export var buildings: Array[BuildingDef] = []
@export var start_resources: Dictionary[ResourceDef, int] = {}
@export var start_units: Array[UnitDef] = []
@export var start_building: BuildingDef
