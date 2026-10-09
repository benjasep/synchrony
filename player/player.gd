class_name Player
extends CharacterBody3D

## Jugador único para los tres roles, sin subclases ni lógica de juego: cablea componentes y
## les reparte el [RoleProfile]. Un [code]if[/code] sobre [code]Statics.Role[/code] fuera de
## [code]setup()[/code] rompe el diseño: eso va en un .tres, [Equipment] o [PlayerAbility].

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


## Guarda los datos del jugador, resuelve su [RoleProfile] y reparte la autoridad; aplica la
## configuración ya si el nodo está listo o, si no, la deja para [code]_ready()[/code]. La
## llama [PlayerSpawner], antes o después de que el jugador entre al árbol.
## Recibe: [param player_data] — datos de sesión del jugador (id de peer, rol, índice).
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


## Aplica la configuración si [code]setup()[/code] se llamó antes de entrar al árbol.
func _ready() -> void:
	if data:
		_apply_setup()


## Devuelve [code]true[/code] si este peer controla al jugador (es su autoridad).
func is_local_player() -> bool:
	return is_multiplayer_authority()


## Devuelve el nombre de sesión del jugador, o cadena vacía si aún no tiene datos.
func get_display_name() -> String:
	return data.name if data else ""


## Devuelve el origen global del apuntado: la cámara o, si no hay, el propio jugador.
func get_aim_origin() -> Vector3:
	return camera.global_position if camera else global_position


## Devuelve la dirección global hacia la que apunta el jugador: el -Z de la base de apuntado
## de [ViewComponent], o el frente del cuerpo si no hay vista.
func get_aim_direction() -> Vector3:
	if view:
		return -view.get_aim_basis().z
	return -global_basis.z


## Configura el jugador una sola vez: autoridad, componentes, medidas, modelo, ajustes
## locales, habilidad, HUD y señales, y al terminar emite [code]setup_completed[/code]. Sin
## [RoleProfile] registra un error y el jugador queda sin configurar.
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


## Reparte la autoridad nodo a nodo: el cliente dueño recibe el [Player], movimiento, vista,
## interacción, percepción y synchronizer; el servidor, salud, inventario y
## [code]hand_anchor[/code] (y con él el equipamiento). Nunca recursiva: el servidor dejaría
## de ser autoridad de la salud y sus [code]@rpc("authority")[/code] serían rechazados.
## Idempotente: reasignar la autoridad de un synchronizer que ya sincroniza rompe su spawn.
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


## Asigna este jugador a cada [PlayerComponent] y les pasa el [RoleProfile]; a
## [HealthComponent] solo el perfil.
func _configure_components() -> void:
	# HealthComponent es genérico (no extiende PlayerComponent) para poder
	# reutilizarlo en enemigos, por eso no recibe la referencia al Player.
	if health:
		health.configure(profile)
	for component: PlayerComponent in [movement, view, interaction, inventory, perception]:
		if component:
			component.player = self
			component.configure(profile)


## Activa la cámara solo en el peer dueño y le oculta su propio cuerpo; los demás sí lo ven.
func _configure_local_only() -> void:
	var is_owner: bool = is_multiplayer_authority()
	if camera:
		camera.current = is_owner
	# En primera persona el dueño no debe ver su propio cuerpo.
	if body:
		body.visible = not is_owner


## Ajusta la altura de los ojos, la cápsula de colisión y el placeholder a las medidas del
## [RoleProfile]. Viven en el perfil porque [code]player.tscn[/code] es común a todos los
## roles: cablearlas en la escena obligaría a un [code]if[/code] sobre el rol.
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


## Instancia el [code]body_scene[/code] del rol bajo [code]body[/code] (el nodo que se
## oculta al dueño), lo pasa a la capa visual de cuerpos y oculta el placeholder. No hace
## nada si el rol no trae modelo; si no es un [Node3D], registra un error.
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


## Instancia la [PlayerAbility] del rol como hija y la vincula a este jugador. No hace nada
## si el rol no tiene habilidad; si la escena no es una [PlayerAbility], registra un error.
func _spawn_ability() -> void:
	if not profile.ability_scene:
		return
	ability = profile.ability_scene.instantiate() as PlayerAbility
	if not ability:
		push_error("ability_scene de %s no es un PlayerAbility" % profile.display_name)
		return
	add_child(ability)
	ability.setup(self)


## Instancia el HUD del rol dentro de [code]hud_layer[/code], solo en el peer dueño.
func _spawn_hud() -> void:
	if not is_multiplayer_authority() or not profile.hud_scene or not hud_layer:
		return
	hud = profile.hud_scene.instantiate()
	hud_layer.add_child(hud)


## Conecta las señales de salud a sus manejadores y reemite como
## [code]equipment_changed[/code] cada item que equipa el inventario.
func _connect_signals() -> void:
	if health:
		health.downed.connect(_handle_downed)
		health.revived.connect(_handle_revived)
		health.died.connect(_handle_died)
	if inventory:
		inventory.item_equipped.connect(func(item: Equipment) -> void: equipment_changed.emit(item))


## Bloquea los controles al caer derribado y emite [code]downed[/code].
func _handle_downed() -> void:
	_set_controls_enabled(false)
	downed.emit()


## Devuelve los controles al ser reanimado y emite [code]revived[/code].
func _handle_revived() -> void:
	_set_controls_enabled(true)
	revived.emit()


## Al morir, el servidor suelta todo el inventario (sigue en juego); luego bloquea los
## controles, desactiva la habilidad, libera el ratón y emite [code]died[/code].
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


## Activa o desactiva movimiento e interacción y captura o libera el ratón. En las copias
## remotas el procesado queda siempre apagado.
## Recibe: [param enabled] — [code]true[/code] para devolver el control al jugador.
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
