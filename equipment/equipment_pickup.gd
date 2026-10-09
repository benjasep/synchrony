class_name EquipmentPickup
extends Interactable

## [Equipment] tirado en el mundo, esperando a que alguien lo recoja. Lo replica el
## [MultiplayerSpawner] de [PlayerSpawner], así que guarda la ruta de escena y el estado del
## item (munición, batería), nunca una referencia al nodo original.

@export var scene_path: String = ""
@export var item_state: Dictionary = {}

var _preview: Node3D


## Fuerza la capa de interacción (vía [code]super()[/code]) y construye la vista previa.
func _ready() -> void:
	super()
	_build_preview()


## Configura qué item contiene. Lo llama [PlayerSpawner] al crear el pickup, antes de que
## entre al árbol; si ya estaba listo, reconstruye la vista previa al momento.
## Recibe: [param equipment_scene_path] — ruta de la escena del [Equipment];
## [param state] — lo que devolvió su [code]get_state()[/code] al soltarlo.
func setup(equipment_scene_path: String, state: Dictionary) -> void:
	scene_path = equipment_scene_path
	item_state = state
	if is_node_ready():
		_build_preview()


## Comprueba si [param player] puede recogerlo.
## Devuelve: [code]true[/code] si está habilitado, contiene un item y el inventario de
## [param player] tiene un hueco libre.
func can_interact(player: Player) -> bool:
	if not super(player) or scene_path.is_empty():
		return false
	return player.inventory != null and player.inventory.has_free_slot()


## Solo servidor ([InteractionComponent] ya validó al emisor): mete el item en el inventario
## de [param player], emite [code]interacted[/code] y libera el pickup. Si el inventario lo
## rechaza, no hace nada.
## Recibe: [param player] — quien lo recoge.
func perform(player: Player) -> void:
	if not player.inventory.add_item_from_scene(scene_path, item_state):
		return
	interacted.emit(player)
	queue_free()


## Instancia la escena del item como hijo solo para mostrar su modelo y, si el prompt es el
## genérico, lo cambia a "Recoger <nombre>". Libera la vista previa anterior; si la ruta no
## existe o no es un [Equipment], se queda sin ninguna.
func _build_preview() -> void:
	if _preview:
		_preview.queue_free()
		_preview = null
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var scene: PackedScene = load(scene_path) as PackedScene
	if not scene:
		return
	var instance: Equipment = scene.instantiate() as Equipment
	if not instance:
		return
	# Solo queremos el modelo: el item real vive en el inventario de quien lo
	# recoja, no aquí.
	_preview = instance
	add_child(_preview)
	if instance.model:
		instance.model.show()
	if prompt == "Interactuar" and instance.display_name:
		prompt = "Recoger %s" % instance.display_name
