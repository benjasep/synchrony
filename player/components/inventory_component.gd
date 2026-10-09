class_name InventoryComponent
extends PlayerComponent

## Items que lleva el jugador y cuál empuña. Pertenece al SERVIDOR: el cliente pide
## ([code]request_*[/code]) y el servidor valida y difunde ([code]_apply_*[/code]). El índice en
## [code]items[/code] es la identidad del item en la red; cuadra porque todos los peers aplican
## las mismas operaciones en el mismo orden, desde un loadout inicial determinista.

signal item_added(item: Equipment)
signal item_removed(item: Equipment)
signal item_equipped(item: Equipment)
signal item_dropped(item: Equipment, drop_transform: Transform3D)

@export var hand_anchor: Node3D
@export var max_slots: int = 4
@export var drop_distance: float = 1.2
@export var drop_height: float = 0.6

var items: Array[Equipment] = []
var active_item: Equipment = null


## Activa el input de uso solo en el dueño, entrega el loadout inicial del rol y empuña el
## primer item si las manos quedan vacías. Corre en todos los peers, en el mismo orden, para
## que los índices coincidan.
## Recibe: [param profile] — perfil del rol; con [code]null[/code] no entrega nada.
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


## Instancia cada escena y la añade guardada al inventario, en orden; salta las nulas y las
## que no son [Equipment]. Es local y no comprueba [code]max_slots[/code].
## Recibe: [param scenes] — escenas del loadout inicial.
func give_starting_equipment(scenes: Array[PackedScene]) -> void:
	for scene: PackedScene in scenes:
		if not scene:
			continue
		var item: Equipment = scene.instantiate() as Equipment
		if item:
			_attach_item(item)


## Devuelve [code]true[/code] si lleva menos items que [code]max_slots[/code].
func has_free_slot() -> bool:
	return items.size() < max_slots


## Devuelve el índice de [param item] en [code]items[/code], o [code]-1[/code] si no lo lleva.
func get_item_index(item: Equipment) -> int:
	return items.find(item)


## Devuelve [code]true[/code] si lleva algún item de la familia [param tag].
func has_tag(tag: Statics.EquipmentTag) -> bool:
	for item: Equipment in items:
		if item.tag == tag:
			return true
	return false


## Pide al servidor empuñar un item. Solo tiene efecto en el cliente dueño.
## Recibe: [param index] — posición del item en [code]items[/code].
func request_equip(index: int) -> void:
	if is_owner():
		_request_equip.rpc_id(Statics.SERVER_ID, index)


## Pide al servidor soltar un item. Solo tiene efecto en el cliente dueño.
## Recibe: [param index] — posición del item en [code]items[/code].
func request_drop(index: int) -> void:
	if is_owner():
		_request_drop.rpc_id(Statics.SERVER_ID, index)


## Añade en todos los peers un item recogido del mundo, que se empuña si las manos estaban
## vacías. Solo actúa en el servidor; lo llama [code]EquipmentPickup.perform()[/code].
## Recibe: [param scene_path] — escena del [Equipment]; [param state] — estado del item
## (munición, batería) tal como lo devolvió [code]Equipment.get_state()[/code].
## Devuelve: [code]true[/code] si se añadió; [code]false[/code] fuera del servidor, sin hueco
## libre o si la escena no existe.
func add_item_from_scene(scene_path: String, state: Dictionary) -> bool:
	if not multiplayer.is_server() or not has_free_slot():
		return false
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return false
	_apply_add.rpc(scene_path, state)
	return true


## Suelta todos los items, del último al primero para no desplazar los índices pendientes, y
## los deja en juego como pickups. Solo actúa en el servidor; lo llama [Player] al morir.
func drop_all() -> void:
	if not multiplayer.is_server():
		return
	for index: int in range(items.size() - 1, -1, -1):
		_apply_drop.rpc(index, _get_drop_transform())


## Valida en el servidor que lo pide el dueño, que el índice existe y que el jugador puede usar
## el item, y difunde [code]_apply_equip[/code]. [code]call_local[/code] es obligatorio: el host
## se lo envía a sí mismo y sin él Godot rechaza la llamada.
## Recibe: [param index] — posición del item en [code]items[/code].
@rpc("any_peer", "call_local", "reliable")
func _request_equip(index: int) -> void:
	if not multiplayer.is_server() or not _is_sender_the_owner():
		return
	if index < 0 or index >= items.size():
		return
	if not items[index].can_be_equipped_by(player):
		return
	_apply_equip.rpc(index)


## Valida en el servidor que lo pide el dueño y que el índice existe, y difunde
## [code]_apply_drop[/code] con el punto de caída. [code]call_local[/code] obligatorio por la
## misma razón que en [code]_request_equip[/code].
## Recibe: [param index] — posición del item en [code]items[/code].
@rpc("any_peer", "call_local", "reliable")
func _request_drop(index: int) -> void:
	if not multiplayer.is_server() or not _is_sender_the_owner():
		return
	if index < 0 or index >= items.size():
		return
	_apply_drop.rpc(index, _get_drop_transform())


## Instancia el item en todos los peers, le restaura el estado y lo empuña si no había item
## activo. Lo difunde el servidor desde [code]add_item_from_scene()[/code].
## Recibe: [param scene_path] — escena del [Equipment]; [param state] — estado del item.
@rpc("authority", "call_local", "reliable")
func _apply_add(scene_path: String, state: Dictionary) -> void:
	var scene: PackedScene = load(scene_path) as PackedScene
	if not scene:
		return
	var item: Equipment = scene.instantiate() as Equipment
	if not item:
		return
	_attach_item(item, state)

	# Sin esto el item recogido se queda guardado y sin forma de sacarlo: no hay
	# acción de cambio de slot, así que con las manos vacías hay que equiparlo.
	if not active_item:
		_apply_equip(items.size() - 1)


## Desequipa el item activo y empuña el indicado; emite [code]item_equipped[/code]. Si
## [code]Equipment.equip()[/code] lo rechaza, [code]active_item[/code] no cambia aunque el
## anterior ya quedó desequipado. Lo difunde el servidor y también se llama en local.
## Recibe: [param index] — posición del item en [code]items[/code]; fuera de rango no hace nada.
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


## Quita el item del inventario en todos los peers (desequipándolo si era el activo), emite
## [code]item_removed[/code] e [code]item_dropped[/code], libera el nodo y empuña el primero si
## las manos quedan vacías. Solo el servidor crea el pickup, vía [PlayerSpawner].
## Recibe: [param index] — posición del item; [param drop_transform] — dónde cae el pickup.
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


## Añade el item al final de [code]items[/code], lo cuelga de [code]hand_anchor[/code], le
## restaura el estado y lo guarda oculto; emite [code]item_added[/code].
## Recibe: [param item] — item recién instanciado; [param state] — estado a restaurar, vacío
## para quedarse con el que inicializa su [code]_ready()[/code].
func _attach_item(item: Equipment, state: Dictionary = {}) -> void:
	items.append(item)
	if hand_anchor:
		hand_anchor.add_child(item)
	# set_state DESPUÉS de add_child: el _ready() del item inicializa su munición
	# o su batería, así que aplicarlo antes de entrar al árbol se pierde y el
	# arma recogida volvía siempre con el cargador lleno.
	if not state.is_empty():
		item.set_state(state)
	item.stow()
	item_added.emit(item)


## Calcula dónde cae un item soltado: delante del jugador y elevado sobre sus pies, no en la
## mano, que cuelga desplazada de la cámara y lo dejaría fuera del punto de mira.
## Devuelve: un transform sin rotación; [code]IDENTITY[/code] si el jugador no está en el árbol.
func _get_drop_transform() -> Transform3D:
	if not player or not player.is_inside_tree():
		return Transform3D.IDENTITY
	var forward: Vector3 = -player.global_basis.z
	var origin: Vector3 = player.global_position + forward * drop_distance + Vector3.UP * drop_height
	return Transform3D(Basis.IDENTITY, origin)


## Devuelve [code]true[/code] si el RPC en curso lo envió el dueño de este jugador o es una
## llamada local del host (emisor [code]0[/code]).
func _is_sender_the_owner() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	return sender_id == 0 or (player.data != null and sender_id == player.data.id)


## Con un item activo, traduce [code]use_item[/code], [code]alt_use_item[/code] y
## [code]drop_item[/code] en usarlo, su uso alternativo o pedir soltarlo. Solo corre en el dueño.
func _unhandled_input(_event: InputEvent) -> void:
	if not active_item:
		return
	if Input.is_action_just_pressed(&"use_item"):
		active_item.use()
	elif Input.is_action_just_pressed(&"alt_use_item"):
		active_item.alt_use()
	elif Input.is_action_just_pressed(&"drop_item"):
		request_drop(get_item_index(active_item))
