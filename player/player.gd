class_name Player
extends CharacterBody3D

## Jugador único para los tres roles: cablea sus componentes y les reparte el [RoleProfile].

signal setup_completed
signal revived
signal died
signal equipment_changed(item: Equipment)

@export_group("Nodos")
@export var head: Node3D
@export var camera: Camera3D
@export var hand_anchor: Node3D
@export var collision: CollisionShape3D
@export var body: Node3D
@export var body_placeholder: MeshInstance3D
@export var hud_layer: CanvasLayer
@export var synchronizer: MultiplayerSynchronizer
## Escena del HUD de inventario.
@export var inventory_hud_scene: PackedScene

@export_group("Componentes")
@export var movement: MovementComponent
@export var view: ViewComponent
@export var interaction: InteractionComponent
@export var inventory: InventoryComponent
@export var health: HealthComponent
@export var perception: PerceptionComponent
@export var capture: CaptureComponent
@export var noise: NoiseComponent

var data: Statics.PlayerData
var profile: RoleProfile
var ability: PlayerAbility
var hud: Node
var inventory_hud: InventoryHUD

var player_body: PlayerBody = null

var _is_configured: bool = false
var _authority_assigned: bool = false


## Guarda los datos del jugador, resuelve su [RoleProfile] y reparte la autoridad.
func setup(player_data: Statics.PlayerData) -> void:
	data = player_data
	profile = RoleDatabase.get_profile(player_data.role)
	_assign_authority()
	if is_node_ready():
		_apply_setup()


## Aplica la configuración si [code]setup()[/code] llegó antes de entrar al árbol.
func _ready() -> void:
	if data:
		_apply_setup()


## Devuelve [code]true[/code] si este peer controla al jugador.
func is_local_player() -> bool:
	return is_multiplayer_authority()


## Devuelve [code]true[/code] si algo lo tiene atrapado.
func is_captured() -> bool:
	return capture != null and capture.is_captured()


## Devuelve el nombre de sesión del jugador.
func get_display_name() -> String:
	return data.name if data else ""


## Devuelve el origen global del apuntado.
func get_aim_origin() -> Vector3:
	return camera.global_position if camera else global_position


## Devuelve la dirección global hacia la que apunta.
func get_aim_direction() -> Vector3:
	if view:
		return -view.get_aim_basis().z
	return -global_basis.z


## Configura el jugador una sola vez y emite [code]setup_completed[/code].
func _apply_setup() -> void:
	if _is_configured:
		return
	_is_configured = true

	if not profile:
		push_error("Player %d sin RoleProfile para el rol %d" % [data.id, data.role])
		return

	_assign_authority()
	_configure_components()
	_apply_body_dimensions()
	_spawn_body()
	_configure_local_only()
	_spawn_ability()
	_spawn_hud()
	_connect_signals()

	setup_completed.emit()


## Reparte la autoridad nodo a nodo entre el cliente dueño y el servidor.
func _assign_authority() -> void:
	if _authority_assigned:
		return
	_authority_assigned = true

	set_multiplayer_authority(data.id, false)

	var client_owned: Array[Node] = [movement, view, interaction, perception, synchronizer]
	for node: Node in client_owned:
		if node:
			node.set_multiplayer_authority(data.id, false)

	var server_owned: Array[Node] = [health, inventory, hand_anchor, capture, noise]
	for node: Node in server_owned:
		if node:
			node.set_multiplayer_authority(Statics.SERVER_ID, false)


## Asigna el jugador y el [RoleProfile] a cada componente.
func _configure_components() -> void:
	if health:
		health.configure(profile)
	for component: PlayerComponent in [movement, view, interaction, inventory, perception, capture,
			noise]:
		if component:
			component.player = self
			component.configure(profile)


## Activa la cámara solo en el peer dueño y le oculta su propio cuerpo.
func _configure_local_only() -> void:
	if camera:
		camera.current = is_multiplayer_authority()
	_show_live_body(true)


## Ajusta los ojos, la cápsula de colisión y el placeholder a las medidas del rol.
func _apply_body_dimensions() -> void:
	if head:
		head.position.y = profile.eye_height

	var height: float = maxf(profile.body_height, profile.body_radius * 2.0)
	if collision:
		var shape: CapsuleShape3D = collision.shape.duplicate() as CapsuleShape3D
		if shape:
			shape.height = height
			shape.radius = profile.body_radius
			collision.shape = shape
			collision.position.y = height * 0.5

	if body_placeholder:
		var mesh: CapsuleMesh = body_placeholder.mesh.duplicate() as CapsuleMesh
		if mesh:
			mesh.height = height
			mesh.radius = profile.body_radius
			body_placeholder.mesh = mesh
			body_placeholder.position.y = height * 0.5


## Instancia el modelo del rol y oculta el placeholder.
func _spawn_body() -> void:
	if not body or not profile.body_scene:
		return
	var model: Node3D = profile.body_scene.instantiate() as Node3D
	if not model:
		push_error("body_scene de %s no es un Node3D" % profile.display_name)
		return
	body.add_child(model)
	player_body = model as PlayerBody
	Statics.force_visual_layer(model, Statics.BODY_VISUAL_LAYER)
	if body_placeholder:
		body_placeholder.hide()


## Instancia la [PlayerAbility] del rol y la vincula a este jugador.
func _spawn_ability() -> void:
	if not profile.ability_scene:
		return
	ability = profile.ability_scene.instantiate() as PlayerAbility
	if not ability:
		push_error("ability_scene de %s no es un PlayerAbility" % profile.display_name)
		return
	add_child(ability)
	ability.setup(self)


"""
func _spawn_hud() -> void:
	if not is_multiplayer_authority() or not profile.hud_scene or not hud_layer:
		return
	hud = profile.hud_scene.instantiate()
	hud_layer.add_child(hud)
"""


## Instancia el HUD del rol y el de inventario en el peer dueño.
func _spawn_hud() -> void:
	if not is_multiplayer_authority() or not hud_layer:
		return
	if profile.hud_scene:
		hud = profile.hud_scene.instantiate()
		hud_layer.add_child(hud)
	_spawn_inventory_hud()


## Instancia el HUD de inventario y lo conecta al inventario.
func _spawn_inventory_hud() -> void:
	if not inventory_hud_scene or not inventory:
		return
	inventory_hud = inventory_hud_scene.instantiate() as InventoryHUD
	if not inventory_hud:
		push_error("inventory_hud_scene no es un InventoryHUD")
		return
	hud_layer.add_child(inventory_hud)
	inventory_hud.setup(inventory, ability, interaction)


## Conecta las señales de salud, captura e inventario.
func _connect_signals() -> void:
	if health:
		health.revived.connect(_handle_revived)
		health.died.connect(_handle_died)
	if capture:
		capture.captured.connect(_handle_captured)
		capture.released.connect(_handle_released)
		capture.separated.connect(_handle_separated)
	if inventory:
		inventory.item_equipped.connect(func(item: Equipment) -> void: equipment_changed.emit(item))


## Retira sus restos, muestra el cuerpo vivo y le devuelve los controles.
func _handle_revived() -> void:
	if capture:
		capture.discard_remains()
	_show_live_body(true)
	if collision:
		collision.disabled = false
	if not is_captured():
		if player_body:
			player_body.set_struggling(false)
		_set_controls_enabled(true)
	revived.emit()


## Suelta el inventario en el servidor, le quita los controles y emite [code]died[/code].
func _handle_died() -> void:
	if multiplayer.is_server() and inventory and not is_captured():
		inventory.drop_all()
	_set_controls_enabled(false)
	if ability:
		ability.deactivate()
	if view:
		view.release_mouse()
	died.emit()


## Le quita los controles y hace forcejear su cuerpo.
func _handle_captured() -> void:
	_set_controls_enabled(false)
	if player_body:
		player_body.set_struggling(true)


## Oculta el cuerpo vivo y apaga su colisión.
func _handle_separated() -> void:
	_show_live_body(false)
	if collision:
		collision.disabled = true


## Deja de forcejear y, si sigue vivo, le devuelve los controles.
func _handle_released(as_remains: bool) -> void:
	if player_body:
		player_body.set_struggling(false)
	if health and health.is_dead:
		if multiplayer.is_server() and inventory:
			inventory.drop_all()
		return
	if not as_remains:
		_set_controls_enabled(true)


## Muestra u oculta el cuerpo vivo.
func _show_live_body(shown: bool) -> void:
	if body:
		body.visible = shown and not is_multiplayer_authority()


## Activa o desactiva el movimiento, la interacción, el uso de items y el ratón.
func _set_controls_enabled(enabled: bool) -> void:
	var is_owner: bool = is_multiplayer_authority()
	if movement:
		movement.set_physics_process(enabled and is_owner)
	if interaction:
		interaction.set_physics_process(enabled and is_owner)
	if inventory:
		inventory.set_process_unhandled_input(enabled and is_owner)
	if view:
		if enabled and is_owner:
			view.capture_mouse()
		else:
			view.release_mouse()
