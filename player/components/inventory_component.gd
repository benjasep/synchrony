class_name InventoryComponent
extends PlayerComponent

## Items que lleva el jugador y cuál tiene en la mano.
##
## El equipamiento es transferible por diseño: si muere el militar, su arma cae
## y cualquiera puede recogerla (con los debuffs de su competencia). Por eso el
## inventario no sabe nada de roles; solo llama a Equipment.equip(), que resuelve
## la competencia del portador.
##
## AUTORIDAD: este componente pertenece al SERVIDOR, no al cliente dueño. La
## posesión de items es estado del mundo. El cliente pide (request_*) y el
## servidor decide y difunde (_apply_*).
##
## Los índices de `items` son la identidad de un item en la red. Se mantienen
## coherentes porque todos los peers aplican las mismas operaciones en el mismo
## orden, empezando por un loadout inicial determinista.

signal item_added(item: Equipment)
signal item_removed(item: Equipment)
signal item_equipped(item: Equipment)
signal item_dropped(item: Equipment, drop_transform: Transform3D)

## Dónde se monta visualmente el item activo. Compartido por linterna y arma.
@export var hand_anchor: Node3D
@export var max_slots: int = 4
## Dónde cae un item soltado, relativo al jugador.
@export var drop_distance: float = 1.2
@export var drop_height: float = 0.6

var items: Array[Equipment] = []
var active_item: Equipment = null


func configure(profile: RoleProfile) -> void:
	super(profile)
	# El estado del inventario lo necesitan todos los peers; solo el input de
	# uso es exclusivo del dueño.
	set_process_unhandled_input(is_owner())
	if not profile:
		return
	# Determinista en todos los peers: mismo orden, mismos índices.
	give_starting_equipment(profile.starting_equipment)
	if not active_item and not items.is_empty():
		_apply_equip(0)


func give_starting_equipment(scenes: Array[PackedScene]) -> void:
	for scene: PackedScene in scenes:
		if not scene:
			continue
		var item: Equipment = scene.instantiate() as Equipment
		if item:
			_attach_item(item)


func has_free_slot() -> bool:
	return items.size() < max_slots


func get_item_index(item: Equipment) -> int:
	return items.find(item)


func has_tag(tag: Statics.EquipmentTag) -> bool:
	for item: Equipment in items:
		if item.tag == tag:
			return true
	return false


## --- Peticiones del cliente dueño ---

func request_equip(index: int) -> void:
	if is_owner():
		_request_equip.rpc_id(Statics.SERVER_ID, index)


func request_drop(index: int) -> void:
	if is_owner():
		_request_drop.rpc_id(Statics.SERVER_ID, index)


## Recoge un item del mundo. Solo servidor: lo llama EquipmentPickup.perform().
func add_item_from_scene(scene_path: String, state: Dictionary) -> bool:
	if not multiplayer.is_server() or not has_free_slot():
		return false
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return false
	_apply_add.rpc(scene_path, state)
	return true


## Suelta todo. Se llama al morir: los items del muerto siguen siendo jugables.
func drop_all() -> void:
	if not multiplayer.is_server():
		return
	for index: int in range(items.size() - 1, -1, -1):
		_apply_drop.rpc(index, _get_drop_transform())


## --- Resolución en el servidor ---

## call_local: el host se dirige estas peticiones a sí mismo. Ver _request_fire.
@rpc("any_peer", "call_local", "reliable")
func _request_equip(index: int) -> void:
	if not multiplayer.is_server() or not _is_sender_the_owner():
		return
	if index < 0 or index >= items.size():
		return
	if not items[index].can_be_equipped_by(player):
		return
	_apply_equip.rpc(index)


@rpc("any_peer", "call_local", "reliable")
func _request_drop(index: int) -> void:
	if not multiplayer.is_server() or not _is_sender_the_owner():
		return
	if index < 0 or index >= items.size():
		return
	_apply_drop.rpc(index, _get_drop_transform())


## --- Aplicación en todos los peers ---

@rpc("authority", "call_local", "reliable")
func _apply_add(scene_path: String, state: Dictionary) -> void:
	var scene: PackedScene = load(scene_path) as PackedScene
	if not scene:
		return
	var item: Equipment = scene.instantiate() as Equipment
	if not item:
		return
	item.set_state(state)
	_attach_item(item)


@rpc("authority", "call_local", "reliable")
func _apply_equip(index: int) -> void:
	if index < 0 or index >= items.size() or not player:
		return
	var item: Equipment = items[index]
	if active_item and active_item != item:
		active_item.unequip()
	if not item.equip(player):
		return
	active_item = item
	item_equipped.emit(item)


@rpc("authority", "call_local", "reliable")
func _apply_drop(index: int, drop_transform: Transform3D) -> void:
	if index < 0 or index >= items.size():
		return
	var item: Equipment = items[index]
	if active_item == item:
		item.unequip()
		active_item = null
	items.remove_at(index)

	# El servidor crea el pickup y el MultiplayerSpawner lo replica; los demás
	# peers solo destruyen su copia local del item.
	if multiplayer.is_server() and PlayerSpawner.instance:
		PlayerSpawner.instance.spawn_pickup(item.scene_file_path, item.get_state(), drop_transform)

	item_removed.emit(item)
	item_dropped.emit(item, drop_transform)
	# Sin esto el item quedaba huérfano: fuera del árbol pero vivo.
	item.queue_free()

	if not active_item and not items.is_empty():
		_apply_equip(0)


func _attach_item(item: Equipment) -> void:
	items.append(item)
	if hand_anchor:
		hand_anchor.add_child(item)
	item.stow()
	item_added.emit(item)


## Delante del jugador y a media altura, no en la mano: el HandAnchor cuelga de
## la cámara y está desplazado, así que el item quedaba flotando fuera del punto
## de mira y era imposible volver a señalarlo.
func _get_drop_transform() -> Transform3D:
	if not player or not player.is_inside_tree():
		return Transform3D.IDENTITY
	var forward: Vector3 = -player.global_basis.z
	var origin: Vector3 = player.global_position + forward * drop_distance + Vector3.UP * drop_height
	return Transform3D(Basis.IDENTITY, origin)


func _is_sender_the_owner() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or (player.data != null and sender_id == player.data.id)


func _unhandled_input(_event: InputEvent) -> void:
	if not active_item:
		return
	if Input.is_action_just_pressed(&"use_item"):
		active_item.use()
	elif Input.is_action_just_pressed(&"alt_use_item"):
		active_item.alt_use()
	elif Input.is_action_just_pressed(&"drop_item"):
		request_drop(get_item_index(active_item))
