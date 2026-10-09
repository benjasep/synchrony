class_name InteractionComponent
extends PlayerComponent

## Detecta el [Interactable] al que apunta el jugador y pide al servidor interactuar con él.
## El efecto nunca se ejecuta en el cliente: lo valida y lo aplica el servidor.

signal target_changed(target: Interactable)

@export var ray: RayCast3D
@export var max_distance: float = 2.5
@export var debug_show_prompt: bool = true

var current_target: Interactable = null


## Apunta el rayo hacia delante hasta [code]max_distance[/code], lo activa solo en el dueño y
## lo hace detectar áreas además de cuerpos. Sin rayo solo aplica el gating de la base.
## Recibe: [param profile] — perfil del rol, que se pasa a la clase base.
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


## Actualiza el objetivo y pide la interacción al pulsar [code]interact[/code]. Solo corre en
## el dueño.
func _physics_process(_delta: float) -> void:
	_update_target()
	if Input.is_action_just_pressed(&"interact"):
		request_interact()


## Pide al servidor interactuar con el objetivo actual, si lo hay y su
## [code]can_interact()[/code] lo permite.
func request_interact() -> void:
	if not current_target or not player:
		return
	if not current_target.can_interact(player):
		return
	_perform_interaction.rpc_id(Statics.SERVER_ID, current_target.get_path())


## Ejecuta la interacción en el servidor tras comprobar que la pide el dueño de este jugador y
## que el objetivo existe y la sigue aceptando. [code]call_local[/code] es obligatorio: el host
## se lo envía a sí mismo y sin él Godot rechaza la llamada.
## Recibe: [param target_path] — ruta del [Interactable] en el árbol.
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


## Toma como objetivo el [Interactable] que toca el rayo ([code]null[/code] si no toca ninguno)
## y, si cambió, emite [code]target_changed[/code]. Con [code]debug_show_prompt[/code] muestra
## su prompt por [code]Debug.log[/code] en el dueño, mientras no exista el HUD.
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
