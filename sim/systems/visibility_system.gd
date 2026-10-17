class_name VisibilitySystem
extends RefCounted
## Esqueleto de la visibilidad / niebla a 5 Hz escalonada (ADR-006 puntos 1 y 2).
## La implementación (rejilla por equipo de celdas de 32 m en bloques de 64x64 con PackedByteArray)
## es de T-014. Simulation ya la llama con la fase correspondiente para fijar el orden del tick.


## phase en [0, phases): equipo o rango de slots que toca este tick.
func run(_store: EntityStore, _grid: SpatialGrid, _phase: int, _phases: int) -> void:
	pass
