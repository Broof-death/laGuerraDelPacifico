class_name BuildingDef
extends EntityDef
## Definición de un edificio (ADR-007).

enum Placement { LAND, COAST }

## Huella en celdas.
@export var footprint: Vector2i = Vector2i.ONE
@export var placement: Placement = Placement.LAND
@export var trains: Array[UnitDef] = []
@export var pop_provided: int = 0
@export var drop_off: Array[ResourceDef] = []
