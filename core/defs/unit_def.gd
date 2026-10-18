class_name UnitDef
extends EntityDef
## Definición de una unidad móvil (ADR-007).

enum Domain { LAND, SEA }
enum Category { WORKER, INFANTRY, CAVALRY, ARTILLERY, SHIP }

@export var domain: Domain = Domain.LAND
@export var category: Category = Category.INFANTRY
## Velocidad táctica en m/s (en combate y cerca del enemigo).
@export var speed: float = 5.0
## Velocidad de marcha en m/s (ADR-011/ADR-012, Q-010): desplazamientos largos sin enemigos cerca.
## 0 = igual a speed.
@export var march_speed: float = 0.0
## Giro en grados/s.
@export var turn_rate: float = 180.0
## Radio en metros, para colisión y espacio.
@export var radius: float = 1.0
@export var pop_cost: int = 1
@export var can_gather: Array[ResourceDef] = []
@export var can_build: Array[BuildingDef] = []
