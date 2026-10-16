class_name RemainsQueue
extends Node3D

## Cola local de los restos de jugadores. Los guarda colgando de la escena, nunca del [Player], y
## no deja que se acumulen sin límite: los restos no desaparecen solos, pero al pasar de
## [code]max_corpses[/code] cadáveres se libera el más antiguo con todas sus piezas. Es cosmética
## y local a cada peer, como la física de los restos: nada de esto se replica. Se crea bajo
## demanda bajo la escena actual (ver [code]get_or_create()[/code]), así que se va con ella al
## cambiar de escena.

const DEFAULT_MAX_CORPSES: int = 20

## Un cadáver: el jugador al que pertenece y sus piezas.
class Corpse:
	var player: Player
	var pieces: Array[Node3D] = []


static var instance: RemainsQueue = null

## Cadáveres que caben a la vez. La cola se crea en código, así que vale
## [constant DEFAULT_MAX_CORPSES] salvo que alguien la cambie en ejecución.
@export var max_corpses: int = DEFAULT_MAX_CORPSES

var _corpses: Array[Corpse] = []


## Se registra como la cola de la escena.
func _enter_tree() -> void:
	instance = self


## Deja de ser la cola de la escena al salir del árbol.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Devuelve la cola de la escena actual y, si aún no hay, la crea como hija de
## [code]current_scene[/code] (o de la raíz, si no hay escena).
## Recibe: [param tree] — el árbol del que cuelga quien la pide.
static func get_or_create(tree: SceneTree) -> RemainsQueue:
	if is_instance_valid(instance) and instance.is_inside_tree() \
			and not instance.is_queued_for_deletion():
		return instance
	var queue: RemainsQueue = RemainsQueue.new()
	queue.name = "RemainsQueue"
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	parent.add_child(queue)
	return queue


## Guarda el cadáver de [param player]: sus [param pieces] pasan a colgar de la cola. Si ya tenía
## uno, lo sustituye; si con él se pasa de [code]max_corpses[/code], libera los más antiguos.
func add(player: Player, pieces: Array[Node3D]) -> void:
	remove_for(player)
	var corpse: Corpse = Corpse.new()
	corpse.player = player
	for piece: Node3D in pieces:
		if not piece:
			continue
		if piece.get_parent():
			piece.reparent(self)
		else:
			add_child(piece)
		corpse.pieces.append(piece)
	_corpses.append(corpse)
	while _corpses.size() > maxi(max_corpses, 0):
		_free_corpse(_corpses.pop_front())


## Libera el cadáver de [param player], si tiene. Lo usa revivir.
## Devuelve: [code]true[/code] si tenía uno.
func remove_for(player: Player) -> bool:
	for i: int in _corpses.size():
		if _corpses[i].player == player:
			_free_corpse(_corpses[i])
			_corpses.remove_at(i)
			return true
	return false


## Devuelve [code]true[/code] si [param player] tiene un cadáver en la cola.
func has_corpse(player: Player) -> bool:
	for corpse: Corpse in _corpses:
		if corpse.player == player:
			return true
	return false


## Devuelve cuántos cadáveres hay en la cola.
func get_count() -> int:
	return _corpses.size()


## Libera las piezas de [param corpse] que sigan existiendo. Las recorre como [Variant]: una
## pieza ya liberada no cabe en una variable tipada.
func _free_corpse(corpse: Corpse) -> void:
	for piece: Variant in corpse.pieces:
		if is_instance_valid(piece):
			(piece as Node).queue_free()
	corpse.pieces.clear()
