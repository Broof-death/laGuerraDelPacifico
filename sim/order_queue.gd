class_name OrderQueue
extends RefCounted
## Órdenes encoladas con Shift (Command.queued, T-018). Solo servidor.
##
## - Cola por unidad: cada unidad con órdenes pendientes tiene la lista de ids de orden en el
##   orden en que llegaron (como mucho SimConstants.MAX_QUEUED_ORDERS).
## - Una orden encolada guarda el comando y cuántas unidades la tienen todavía en su cola.
## - Una orden arranca para las unidades que la tienen PRIMERA y están libres (IDLE) cuando lo
##   están todas las que la siguen esperando, o cuando pasaron QUEUE_REGROUP_TICKS desde que la
##   primera quedó libre: el grupo se reagrupa en cada punto de paso y sigue con UNA ruta (y una
##   formación si son 8 o más), como una orden normal. Si alguna se atrasa mucho, arranca sola
##   después.
## - Una orden sin Shift (MOVE, ATTACK_MOVE, ATTACK o STOP) vacía la cola de sus unidades. Con
##   Shift, a una unidad libre y sin cola se le aplica en el acto.
## Los ids de orden son internos y se reutilizan (0 = ninguno). Determinista: los diccionarios se
## recorren en orden de inserción, que depende solo de la secuencia de comandos.

## Órdenes: comando, jugador, unidades que la tienen en su cola y tick en que la primera quedó
## lista (-1 = ninguna). Índice 0 reservado.
var commands: Array[Command] = [null]
var player: PackedInt32Array = PackedInt32Array([0])
var holders: PackedInt32Array = PackedInt32Array([0])
var first_ready: PackedInt32Array = PackedInt32Array([-1])
## id de entidad -> ids de orden pendientes (la primera es la siguiente).
var _queues: Dictionary[int, PackedInt32Array] = {}
var _free: PackedInt32Array = PackedInt32Array()


## Crea una orden encolada (todavía sin unidades).
func create(p_player: int, cmd: Command) -> int:
	var oid: int
	if _free.is_empty():
		oid = commands.size()
		commands.append(null)
		player.append(0)
		holders.append(0)
		first_ready.append(-1)
	else:
		oid = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	commands[oid] = cmd
	player[oid] = p_player
	holders[oid] = 0
	first_ready[oid] = -1
	return oid


## Agrega la orden al final de la cola de la entidad. false si la cola está llena.
func push(entity_id: int, oid: int) -> bool:
	var q: PackedInt32Array = _queues.get(entity_id, PackedInt32Array())
	if q.size() >= SimConstants.MAX_QUEUED_ORDERS:
		return false
	q.append(oid)
	_queues[entity_id] = q
	holders[oid] += 1
	return true


## Libera una orden que no quedó en ninguna cola (todas estaban llenas).
func release_if_unused(oid: int) -> void:
	if holders[oid] == 0:
		holders[oid] = 1
		_drop(oid)


func has_queue(entity_id: int) -> bool:
	return _queues.has(entity_id)


## Órdenes pendientes de una entidad (copia).
func queue_of(entity_id: int) -> PackedInt32Array:
	return _queues.get(entity_id, PackedInt32Array()).duplicate()


## Primera orden pendiente de la entidad (0 = ninguna).
func head(entity_id: int) -> int:
	var q: PackedInt32Array = _queues.get(entity_id, PackedInt32Array())
	return q[0] if not q.is_empty() else 0


## Saca la primera orden de la cola de la entidad.
func pop(entity_id: int) -> void:
	var q: PackedInt32Array = _queues.get(entity_id, PackedInt32Array())
	if q.is_empty():
		return
	_drop(q[0])
	q.remove_at(0)
	if q.is_empty():
		_queues.erase(entity_id)
	else:
		_queues[entity_id] = q


## Vacía la cola de la entidad (nueva orden sin Shift, o murió).
func clear(entity_id: int) -> void:
	if not _queues.has(entity_id):
		return
	for oid: int in _queues[entity_id]:
		_drop(oid)
	_queues.erase(entity_id)


## Entidades con cola, en orden de inserción.
func entities() -> Array[int]:
	return _queues.keys()


func active_orders() -> int:
	return commands.size() - 1 - _free.size()


func _drop(oid: int) -> void:
	holders[oid] -= 1
	if holders[oid] <= 0:
		commands[oid] = null
		first_ready[oid] = -1
		_free.append(oid)
