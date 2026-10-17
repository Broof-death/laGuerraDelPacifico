class_name TickAccumulator
extends RefCounted
## Acumulador de tiempo para el tick fijo de 20 Hz (ADR-006 punto 1), independiente de los FPS
## y del tick de física de Godot. Lo usa MatchServer (T-005) en cada frame:
##     for i in accumulator.advance(delta): simulation.step()
## Ejecuta como máximo MAX_TICKS_PER_FRAME ticks por llamada; el tiempo sobrante se descarta y se
## cuenta en dropped_ticks ("sim atrasada").

var tick_dt: float = SimConstants.TICK_DT
var max_ticks_per_frame: int = SimConstants.MAX_TICKS_PER_FRAME
## Escala de tiempo (pausa = 0, x2 = 2): solo en el modo de un jugador.
var time_scale: float = 1.0
## Ticks descartados por atraso desde el inicio.
var dropped_ticks: int = 0
var _accum: float = 0.0


## Suma el tiempo real del frame y devuelve cuántos ticks hay que ejecutar ahora.
func advance(frame_delta: float) -> int:
	_accum += maxf(frame_delta, 0.0) * time_scale
	var ticks: int = int(floor(_accum / tick_dt))
	if ticks > max_ticks_per_frame:
		dropped_ticks += ticks - max_ticks_per_frame
		push_warning("Simulación atrasada: se descartan %d ticks" % (ticks - max_ticks_per_frame))
		ticks = max_ticks_per_frame
		_accum = 0.0
	else:
		_accum -= ticks * tick_dt
	return ticks


## Fracción del tick en curso [0, 1), útil para depurar.
func alpha() -> float:
	return _accum / tick_dt
