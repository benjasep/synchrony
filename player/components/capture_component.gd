class_name CaptureComponent
extends PlayerComponent

## Estado "atrapado" del jugador. Es genérico: no sabe qué lo agarra, solo qué dos nodos tiene
## que seguir. Mientras dura, el jugador sigue cada frame al nodo del cuerpo en TODOS los peers,
## por encima de lo que traiga el [MultiplayerSynchronizer] (que en los remotos sobrescribiría
## la posición), y en el dueño la cámara sigue al de la cabeza en posición y rotación. Quién
## atrapa y cuándo suelta lo decide el servidor; esto lo aplica cada peer en local. [Player]
## escucha sus señales para quitar y devolver los controles.

signal captured
## Recibe: [param as_remains] — [code]true[/code] si se soltó el cuerpo de un muerto y no a una
## víctima viva.
signal released(as_remains: bool)

## Después del [AnimationTree] (prioridad 0): así sigue la pose de este frame y no la del
## anterior.
const FOLLOW_PROCESS_PRIORITY: int = 100
## Es una máscara: capa 1, el mundo. Es donde se buscan el suelo para los restos.
const FLOOR_COLLISION_MASK: int = 1

## Metros por debajo del cuerpo hasta los que se busca suelo al soltar los restos.
@export var floor_search_depth: float = 10.0

var _is_captured: bool = false
var _body_anchor: Node3D = null
var _head_anchor: Node3D = null
var _last_body: Transform3D = Transform3D.IDENTITY
var _last_head: Transform3D = Transform3D.IDENTITY
var _camera_rest: Transform3D = Transform3D.IDENTITY


## A diferencia del resto de componentes, el seguimiento corre en todos los peers, pero solo
## mientras está atrapado: arranca apagado.
## Recibe: [param profile] — perfil del rol, que solo usa la clase base.
func configure(profile: RoleProfile) -> void:
	super(profile)
	process_priority = FOLLOW_PROCESS_PRIORITY
	set_process(_is_captured)
	set_physics_process(false)
	set_process_unhandled_input(false)


## Devuelve [code]true[/code] mientras el jugador está atrapado.
func is_captured() -> bool:
	return _is_captured


## Atrapa al jugador: lo pega ya al nodo del cuerpo, anula su velocidad y emite
## [code]captured[/code]. No hace nada si ya está atrapado o falta algún nodo.
## Recibe: [param body_anchor] — nodo cuyo transform global toman sus pies;
## [param head_anchor] — nodo cuyo transform global toma la cámara del dueño.
func capture(body_anchor: Node3D, head_anchor: Node3D) -> void:
	if _is_captured or not player or not body_anchor or not head_anchor:
		return
	_is_captured = true
	_body_anchor = body_anchor
	_head_anchor = head_anchor
	if player.camera:
		_camera_rest = player.camera.transform
	player.velocity = Vector3.ZERO
	set_process(true)
	_follow()
	captured.emit()


## Suelta a una víctima viva: la deja de pie bajo el centro de lo que sujetaba, mirando a quien
## la tenía, para que caiga sobre los pies; devuelve la cámara y emite [code]released[/code].
## No hace nada si no está atrapado.
func release() -> void:
	if not _is_captured:
		return
	_follow()
	var held_center: Vector3 = (_last_body.origin + _last_head.origin) * 0.5
	held_center.y = minf(_last_body.origin.y, _last_head.origin.y)
	_stop_following()
	player.global_transform = Transform3D(_get_upright_basis(), held_center)
	released.emit(false)


## Corrutina: suelta el cuerpo de un muerto. Deja de seguir y devuelve la cámara en el acto, lo
## pone de pie bajo el nodo del cuerpo y, en el siguiente frame de física, lo baja al suelo
## (todavía sin física de restos); solo entonces emite [code]released[/code], para que lo que
## caiga con él (el inventario) caiga en el suelo y no en el aire. Nunca devuelve los
## controles. No hace nada si no está atrapado.
func release_remains() -> void:
	if not _is_captured:
		return
	_follow()
	var spot: Vector3 = _last_body.origin
	_stop_following()
	player.global_transform = Transform3D(_get_upright_basis(), spot)
	await _drop_to_floor()
	if _is_captured or not player or not player.is_inside_tree():
		return
	released.emit(true)


## Sigue a los nodos cada frame. Si alguno desaparece (el captor salió del juego), suelta al
## jugador vivo donde estaba.
func _process(_delta: float) -> void:
	if not _is_captured:
		return
	if not _are_anchors_valid():
		release()
		return
	_follow()


## Copia el transform del nodo del cuerpo al jugador y, en el dueño, el de la cabeza a su
## cámara; recuerda los dos para soltarlo aunque los nodos ya no existan.
func _follow() -> void:
	if _are_anchors_valid():
		_last_body = _body_anchor.global_transform.orthonormalized()
		_last_head = _head_anchor.global_transform.orthonormalized()
	player.global_transform = _last_body
	player.velocity = Vector3.ZERO
	if is_owner() and player.camera:
		player.camera.global_transform = _last_head


## Deja de seguir y devuelve la cámara del dueño a su sitio en la cabeza.
func _stop_following() -> void:
	_is_captured = false
	_body_anchor = null
	_head_anchor = null
	set_process(false)
	if is_owner() and player.camera:
		player.camera.transform = _camera_rest
	player.velocity = Vector3.ZERO


## Devuelve [code]true[/code] si los dos nodos siguen existiendo dentro del árbol.
func _are_anchors_valid() -> bool:
	return is_instance_valid(_body_anchor) and is_instance_valid(_head_anchor) \
		and _body_anchor.is_inside_tree() and _head_anchor.is_inside_tree()


## Devuelve una base vertical que mira hacia donde miraba la cabeza (-Z de la presa: hacia el
## captor), o hacia donde miraba el cuerpo si la cabeza apuntaba arriba o abajo.
func _get_upright_basis() -> Basis:
	for candidate: Vector3 in [-_last_head.basis.z, -_last_body.basis.z, -player.global_basis.z]:
		var forward: Vector3 = Vector3(candidate.x, 0.0, candidate.z)
		if forward.length_squared() > 0.0001:
			return Basis.looking_at(forward.normalized(), Vector3.UP)
	return Basis.IDENTITY


## Corrutina: en el siguiente frame de física, el único en el que es seguro consultar el espacio,
## baja al jugador hasta el suelo que haya bajo él. No lo mueve si entretanto lo atraparon otra
## vez o salió del árbol, ni si no hay suelo a menos de [code]floor_search_depth[/code].
func _drop_to_floor() -> void:
	await get_tree().physics_frame
	if _is_captured or not player or not player.is_inside_tree():
		return
	var from: Vector3 = player.global_position + Vector3.UP * 0.5
	var to: Vector3 = player.global_position + Vector3.DOWN * floor_search_depth
	var exclude: Array[RID] = [player.get_rid()]
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, FLOOR_COLLISION_MASK, exclude)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var floor_point: Vector3 = hit["position"]
	player.global_position = floor_point
