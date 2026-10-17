class_name WeaponDef
extends Resource
## Arma de una unidad o edificio (ADR-007). Puede ir incrustada como subrecurso.

@export var id: StringName = &""
@export var damage: int = 10
## Alcance en metros.
@export var range: float = 50.0
@export var min_range: float = 0.0
## Segundos entre disparos.
@export var cooldown: float = 1.0
## Dominios que puede atacar (valores de UnitDef.Domain).
@export var target_domains: Array[int] = [0]
