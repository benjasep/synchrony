class_name EquipmentPickup
extends Interactable

## Un Equipment tirado en el mundo, esperando a que alguien lo recoja.
##
## Es lo que cierra el bucle del diseño: muere el militar, su arma cae aquí, y
## el técnico puede recogerla — con el temblor de su competencia, resuelto solo
## al equiparla.
##
## Se replica con el MultiplayerSpawner de PlayerSpawner, así que se identifica
## por la ruta de su escena y lleva el estado del item (munición, batería) como
## Dictionary, no como referencia al nodo original.

## Ruta de la escena del Equipment que contiene.
@export var scene_path: String = ""
## Estado del item en el momento de soltarlo.
@export var item_state: Dictionary = {}

var _preview: Node3D


func _ready() -> void:
	super()
	_build_preview()


func setup(equipment_scene_path: String, state: Dictionary) -> void:
	scene_path = equipment_scene_path
	item_state = state
	if is_node_ready():
		_build_preview()


func can_interact(player: Player) -> bool:
	if not super(player) or scene_path.is_empty():
		return false
	return player.inventory != null and player.inventory.has_free_slot()


## Solo servidor: InteractionComponent ya validó al emisor.
func perform(player: Player) -> void:
	if not player.inventory.add_item_from_scene(scene_path, item_state):
		return
	interacted.emit(player)
	queue_free()


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
