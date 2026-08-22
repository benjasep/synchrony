class_name Player
extends CharacterBody3D

## Clase ÚNICA de jugador. No hay subclases por rol: lo que distingue al vidente
## del técnico y del militar es su RoleProfile (datos) y su PlayerAbility
## (comportamiento), no su tipo.
##
## Player no tiene lógica de juego. Solo cablea componentes y reparte el
## RoleProfile. Si aparece un if sobre Statics.Role fuera de setup(), el diseño
## se rompió: eso pertenece a un .tres, a un Equipment o a un PlayerAbility.

signal setup_completed
signal downed
signal revived
signal died
signal equipment_changed(item: Equipment)

@export_group("Nodos")
@export var head: Node3D
@export var camera: Camera3D
@export var hand_anchor: Node3D
@export var body: Node3D
@export var hud_layer: CanvasLayer
@export var synchronizer: MultiplayerSynchronizer

@export_group("Componentes")
@export var movement: MovementComponent
@export var view: ViewComponent
@export var interaction: InteractionComponent
@export var inventory: InventoryComponent
@export var health: HealthComponent
@export var perception: PerceptionComponent

var data: Statics.PlayerData
var profile: RoleProfile
var ability: PlayerAbility
var hud: Node

var _is_configured: bool = false


## Llamado por PlayerSpawner antes o después de entrar al árbol. Sigue el mismo
## patrón que LobbyPlayer.set_player() para tolerar ambos casos.
func setup(player_data: Statics.PlayerData) -> void:
	data = player_data
	profile = RoleDatabase.get_profile(player_data.role)
	# No recursivo: cada nodo recibe la autoridad de quien manda sobre él.
	set_multiplayer_authority(data.id, false)
	if is_node_ready():
		_apply_setup()


func _ready() -> void:
	if data:
		_apply_setup()


func is_local_player() -> bool:
	return is_multiplayer_authority()


func get_display_name() -> String:
	return data.name if data else ""


func get_aim_origin() -> Vector3:
	return camera.global_position if camera else global_position


func get_aim_direction() -> Vector3:
	if view:
		return -view.get_aim_basis().z
	return -global_basis.z


func _apply_setup() -> void:
	if _is_configured:
		return
	_is_configured = true

	if not profile:
		push_error("Player %d sin RoleProfile para el rol %d" % [data.id, data.role])
		return

	_assign_authority()
	_configure_components()
	_configure_local_only()
	_spawn_ability()
	_spawn_hud()
	_connect_signals()

	setup_completed.emit()


## Reparto de autoridad según a quién pertenece cada cosa.
##
## OJO: set_multiplayer_authority() es recursivo por defecto y eso rompería los
## RPC de estado del mundo — el servidor dejaría de ser la autoridad de Health y
## sus @rpc("authority") serían rechazados. Por eso se asigna nodo a nodo:
##
##   cliente dueño -> transform, mirada, interacción, percepción, synchronizer
##   servidor      -> salud, inventario y el equipamiento que cuelga del anchor
func _assign_authority() -> void:
	var client_owned: Array[Node] = [movement, view, interaction, perception, synchronizer]
	for node: Node in client_owned:
		if node:
			node.set_multiplayer_authority(data.id, false)

	var server_owned: Array[Node] = [health, inventory, hand_anchor]
	for node: Node in server_owned:
		if node:
			node.set_multiplayer_authority(Statics.SERVER_ID, false)


func _configure_components() -> void:
	# HealthComponent es genérico (no extiende PlayerComponent) para poder
	# reutilizarlo en enemigos, por eso no recibe la referencia al Player.
	if health:
		health.configure(profile)
	for component: PlayerComponent in [movement, view, interaction, inventory, perception]:
		if component:
			component.player = self
			component.configure(profile)


func _configure_local_only() -> void:
	var is_owner: bool = is_multiplayer_authority()
	if camera:
		camera.current = is_owner
	# En primera persona el dueño no debe ver su propio cuerpo.
	if body:
		body.visible = not is_owner


func _spawn_ability() -> void:
	if not profile.ability_scene:
		return
	ability = profile.ability_scene.instantiate() as PlayerAbility
	if not ability:
		push_error("ability_scene de %s no es un PlayerAbility" % profile.display_name)
		return
	add_child(ability)
	ability.setup(self)


func _spawn_hud() -> void:
	if not is_multiplayer_authority() or not profile.hud_scene or not hud_layer:
		return
	hud = profile.hud_scene.instantiate()
	hud_layer.add_child(hud)


func _connect_signals() -> void:
	if health:
		health.downed.connect(_handle_downed)
		health.revived.connect(_handle_revived)
		health.died.connect(_handle_died)
	if inventory:
		inventory.item_equipped.connect(func(item: Equipment) -> void: equipment_changed.emit(item))


func _handle_downed() -> void:
	_set_controls_enabled(false)
	downed.emit()


func _handle_revived() -> void:
	_set_controls_enabled(true)
	revived.emit()


func _handle_died() -> void:
	# El equipamiento del muerto no se pierde: cae al suelo y sigue en juego.
	if multiplayer.is_server() and inventory:
		inventory.drop_all()
	_set_controls_enabled(false)
	if ability:
		ability.deactivate()
	if view:
		view.release_mouse()
	died.emit()


func _set_controls_enabled(enabled: bool) -> void:
	var is_owner: bool = is_multiplayer_authority()
	if movement:
		movement.set_physics_process(enabled and is_owner)
	if interaction:
		interaction.set_physics_process(enabled and is_owner)
	if view:
		if enabled and is_owner:
			view.capture_mouse()
		else:
			view.release_mouse()
