class_name InteractionComponent
extends PlayerComponent

## Detecta el Interactable al que apunta el jugador y solicita la interacción.
##
## Regla de autoridad: el cliente detecta y pide, el SERVIDOR valida y ejecuta.
## Nunca ejecutar el efecto localmente, o el estado del mundo se desincroniza.

signal target_changed(target: Interactable)

@export var ray: RayCast3D
@export var max_distance: float = 2.5
## Muestra el prompt del objetivo con Debug.log mientras no exista el HUD.
## Apagar cuando el HUD lo dibuje de verdad.
@export var debug_show_prompt: bool = true

var current_target: Interactable = null


func configure(profile: RoleProfile) -> void:
	super(profile)
	if not ray:
		return
	ray.target_position = Vector3(0.0, 0.0, -max_distance)
	ray.enabled = is_owner()
	# Imprescindible: los Interactable son Area3D y RayCast3D los ignora por
	# defecto (collide_with_areas viene en false). Sin esto no se detecta nada.
	ray.collide_with_areas = true
	ray.collide_with_bodies = true


func _physics_process(_delta: float) -> void:
	_update_target()
	if Input.is_action_just_pressed(&"interact"):
		request_interact()


## Pide al servidor interactuar con el objetivo actual.
func request_interact() -> void:
	if not current_target or not player:
		return
	if not current_target.can_interact(player):
		return
	_perform_interaction.rpc_id(Statics.SERVER_ID, current_target.get_path())


## call_local: el host se dirige esto a sí mismo. Ver Firearm._request_fire.
@rpc("any_peer", "call_local", "reliable")
func _perform_interaction(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != player.data.id:
		# Un peer intentando interactuar en nombre de otro jugador.
		return
	var target: Interactable = get_node_or_null(target_path) as Interactable
	if not target or not target.can_interact(player):
		return
	target.perform(player)


func _update_target() -> void:
	var found: Interactable = null
	if ray and ray.is_colliding():
		found = ray.get_collider() as Interactable
	if found == current_target:
		return
	current_target = found
	target_changed.emit(current_target)
	if debug_show_prompt and current_target and is_owner():
		Debug.log("[%s]" % current_target.prompt)
