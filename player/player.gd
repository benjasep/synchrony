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
@export var collision: CollisionShape3D
@export var body: Node3D
## Cápsula gris de referencia. Solo se ve si el rol no trae body_scene.
@export var body_placeholder: MeshInstance3D
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
var _authority_assigned: bool = false


## Llamado por PlayerSpawner antes o después de entrar al árbol. Sigue el mismo
## patrón que LobbyPlayer.set_player() para tolerar ambos casos.
func setup(player_data: Statics.PlayerData) -> void:
	data = player_data
	profile = RoleDatabase.get_profile(player_data.role)
	# La autoridad se reparte AQUÍ y no en _apply_setup(): el MultiplayerSpawner
	# procesa el spawn al añadir el nodo al árbol, y un MultiplayerSynchronizer
	# cuya autoridad cambie después (o sea, desde _ready) se queda sin network id
	# —"unable to process the pending spawn"— y pierde el estado inicial marcado
	# `spawn = true` en su SceneReplicationConfig.
	#
	# Es seguro hacerlo antes de entrar al árbol: las referencias @export
	# declaradas con node_paths= ya están resueltas al salir de instantiate().
	_assign_authority()
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
	_apply_body_dimensions()
	_spawn_body()
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
##
## Idempotente: la llama setup() (antes del árbol) y también _apply_setup(), que
## puede ejecutarse un frame más tarde desde _ready(). Reasignar la autoridad de
## un MultiplayerSynchronizer ya sincronizando es justo lo que rompe su spawn.
func _assign_authority() -> void:
	if _authority_assigned:
		return
	_authority_assigned = true

	# No recursivo: cada nodo recibe la autoridad de quien manda sobre él.
	set_multiplayer_authority(data.id, false)

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


## Ajusta cámara y cápsula a la altura del modelo del rol.
##
## Las medidas viven en el RoleProfile porque player.tscn es una sola escena
## compartida: en cuanto dos roles tengan modelos de distinta altura, cablearlas
## en la escena obligaría a un if sobre el rol, que es justo lo que el diseño
## prohíbe.
func _apply_body_dimensions() -> void:
	if head:
		head.position.y = profile.eye_height

	# duplicate() obligatorio: los sub-recursos de un .tscn se COMPARTEN entre
	# todas las instancias de esa escena, así que redimensionar la cápsula de un
	# jugador se la redimensionaría a los tres.
	var height: float = maxf(profile.body_height, profile.body_radius * 2.0)
	if collision:
		var shape: CapsuleShape3D = collision.shape.duplicate() as CapsuleShape3D
		if shape:
			shape.height = height
			shape.radius = profile.body_radius
			collision.shape = shape
			collision.position.y = height * 0.5

	# El placeholder solo se ve si el rol no trae modelo, pero si se ve tiene
	# que medir lo que mide la colisión.
	if body_placeholder:
		var mesh: CapsuleMesh = body_placeholder.mesh.duplicate() as CapsuleMesh
		if mesh:
			mesh.height = height
			mesh.radius = profile.body_radius
			body_placeholder.mesh = mesh
			body_placeholder.position.y = height * 0.5


## Instancia el modelo del rol. Cuelga de Body y no del Player porque
## _configure_local_only() apaga Body entero: en primera persona el dueño no
## debe verse a sí mismo, pero los demás peers sí tienen que verlo.
func _spawn_body() -> void:
	if not body or not profile.body_scene:
		return
	var model: Node3D = profile.body_scene.instantiate() as Node3D
	if not model:
		push_error("body_scene de %s no es un Node3D" % profile.display_name)
		return
	body.add_child(model)
	# El vidente no dibuja la capa del mundo: en la 1 sus compañeros serían
	# invisibles para él.
	Statics.force_visual_layer(model, Statics.BODY_VISUAL_LAYER)
	if body_placeholder:
		body_placeholder.hide()


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
