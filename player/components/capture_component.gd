class_name CaptureComponent
extends PlayerComponent

## Estado "atrapado" del jugador. Es genérico: no sabe qué lo agarra, solo qué dos nodos tiene
## que seguir. Mientras dura, el jugador sigue cada frame al nodo del cuerpo en TODOS los peers,
## por encima de lo que traiga el [MultiplayerSynchronizer] (que en los remotos sobrescribiría
## la posición), y en el dueño la cámara sigue al de la cabeza en posición y rotación. Quién
## atrapa y cuándo suelta lo decide el servidor; esto lo aplica cada peer en local. [Player]
## escucha sus señales para quitar y devolver los controles.
##
## Si quien lo atrapa lo decapita ([code]separate()[/code], en todos los peers), sus restos
## sustituyen al cuerpo vivo: la cabeza y el cuerpo que da su [PlayerBody], cada uno en un
## [RigidBody3D] congelado que sigue a su nodo hasta [code]release_remains()[/code], que los
## suelta con la velocidad que llevaban esos nodos. Son cosméticos: cada peer simula los suyos
## y los guarda en la [RemainsQueue] de la escena. Desde ahí, la cámara del dueño va con la
## cabeza hasta que revive ([code]discard_remains()[/code]). Sin [PlayerBody] no hay restos y el
## cuerpo se suelta entero, como siempre.

signal captured
## Recibe: [param as_remains] — [code]true[/code] si se soltó el cuerpo de un muerto y no a una
## víctima viva.
signal released(as_remains: bool)
## Se emite en todos los peers al crear los restos: el cuerpo vivo tiene que desaparecer.
signal separated

## Después del [AnimationTree] (prioridad 0): así sigue la pose de este frame y no la del
## anterior.
const FOLLOW_PROCESS_PRIORITY: int = 100
## Es una máscara: capa 1, el mundo. Es donde se buscan el suelo para los restos.
const FLOOR_COLLISION_MASK: int = 1
## Es una máscara: capa 1, el mundo, lo único con lo que chocan los restos. No empujan a los
## jugadores ni paran disparos ni la interacción.
const REMAINS_COLLISION_MASK: int = 1

## Metros por debajo del cuerpo hasta los que se busca suelo al soltar los restos.
@export var floor_search_depth: float = 10.0

var _is_captured: bool = false
var _body_anchor: Node3D = null
var _head_anchor: Node3D = null
var _last_body: Transform3D = Transform3D.IDENTITY
var _last_head: Transform3D = Transform3D.IDENTITY
var _camera_rest: Transform3D = Transform3D.IDENTITY
## Frame de proceso de la última lectura de los nodos: las velocidades se miden entre dos
## frames seguidos.
var _last_read_frame: int = -1
var _body_velocity: Vector3 = Vector3.ZERO
var _body_spin: Vector3 = Vector3.ZERO
var _head_velocity: Vector3 = Vector3.ZERO
var _head_spin: Vector3 = Vector3.ZERO
## Desde [code]separate()[/code] hasta revivir.
var _separated: bool = false
var _body_piece: RigidBody3D = null
var _head_piece: RigidBody3D = null
## En el dueño, desde que se sueltan los restos hasta revivir: la cámara va con la cabeza.
var _camera_on_head: bool = false
var _last_camera: Transform3D = Transform3D.IDENTITY


## A diferencia del resto de componentes, el seguimiento corre en todos los peers, pero solo
## mientras está atrapado: arranca apagado.
## Recibe: [param profile] — perfil del rol, que solo usa la clase base.
func configure(profile: RoleProfile) -> void:
	super(profile)
	process_priority = FOLLOW_PROCESS_PRIORITY
	_update_processing()
	set_physics_process(false)
	set_process_unhandled_input(false)


## Devuelve [code]true[/code] mientras el jugador está atrapado.
func is_captured() -> bool:
	return _is_captured


## Devuelve [code]true[/code] desde que lo decapitan hasta que revive, aunque la cola ya haya
## liberado sus piezas.
func has_remains() -> bool:
	return _separated


## Devuelve el cuerpo de sus restos, o [code]null[/code] si no tiene o la cola lo liberó.
func get_body_piece() -> RigidBody3D:
	return _body_piece if _is_piece_valid(_body_piece) else null


## Devuelve la cabeza de sus restos, o [code]null[/code] si no tiene o la cola la liberó.
func get_head_piece() -> RigidBody3D:
	return _head_piece if _is_piece_valid(_head_piece) else null


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
	_last_read_frame = -1
	_body_velocity = Vector3.ZERO
	_body_spin = Vector3.ZERO
	_head_velocity = Vector3.ZERO
	_head_spin = Vector3.ZERO
	if player.camera:
		_camera_rest = player.camera.transform
	player.velocity = Vector3.ZERO
	_update_processing()
	_follow()
	captured.emit()


## En todos los peers, en el instante del corte: crea los restos con el [PlayerBody] del
## jugador, cada pieza congelada sobre su nodo (el cuerpo donde van los pies, la cabeza con los
## ojos sobre el de la cabeza), los guarda en la [RemainsQueue] y emite [code]separated[/code]
## para que [Player] oculte el cuerpo vivo. El dueño no ve la cabeza: su cámara va dentro. No hace
## nada si no está atrapado, ya se separó o no tiene [PlayerBody].
func separate() -> void:
	if not _is_captured or _separated or not player or not player.player_body:
		return
	var body_model: PlayerBody = player.player_body
	var remains: PlayerBody.Remains = body_model.create_remains()
	if not remains:
		return
	_follow()
	# El modelo visto desde los pies y desde los ojos. Los ojos, sin el cabeceo de la mirada:
	# el modelo no lo sigue, así que la cabeza no cambia de pose al cortarla.
	var model: Transform3D = player.global_transform.affine_inverse() * body_model.global_transform
	var eyes: Transform3D = Transform3D(Basis.IDENTITY,
		player.head.position if player.head else Vector3.ZERO)
	var bounds: AABB = model * remains.body_bounds
	var box: BoxShape3D = BoxShape3D.new()
	box.size = bounds.size
	_body_piece = _make_piece("RestosCuerpo%s" % player.name, remains.body, model, box,
		bounds.get_center(), body_model.body_mass)
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = body_model.head_radius
	_head_piece = _make_piece("RestosCabeza%s" % player.name, remains.head,
		eyes.affine_inverse() * model, sphere, Vector3.ZERO, body_model.head_mass)
	# Pequeña y rápida: sin CCD puede atravesar el suelo en un solo paso de física.
	_head_piece.continuous_cd = true
	_head_piece.angular_damp = body_model.head_angular_damp
	_head_piece.visible = not is_owner()
	_separated = true
	var pieces: Array[Node3D] = [_body_piece, _head_piece]
	RemainsQueue.get_or_create(get_tree()).add(player, pieces)
	_follow()
	separated.emit()


## Suelta a una víctima viva: la deja de pie bajo el centro de lo que sujetaba, mirando a quien
## la tenía, para que caiga sobre los pies; devuelve la cámara y emite [code]released[/code].
## Si ya la habían decapitado, suelta sus restos ([code]release_remains()[/code]): aunque la
## muerte aún no haya llegado a este peer, ya no hay víctima viva que soltar. No hace nada si no
## está atrapado.
func release() -> void:
	if not _is_captured:
		return
	if _separated:
		release_remains()
		return
	_follow()
	var held_center: Vector3 = (_last_body.origin + _last_head.origin) * 0.5
	held_center.y = minf(_last_body.origin.y, _last_head.origin.y)
	_stop_following(true)
	player.global_transform = Transform3D(_get_upright_basis(), held_center)
	released.emit(false)


## Corrutina: suelta el cuerpo de un muerto. Deja de seguir; si tiene restos, los suelta con la
## velocidad que llevaban sus nodos y la cámara del dueño pasa a ir con la cabeza; si no, la
## devuelve a su sitio. Pone al jugador de pie bajo el nodo del cuerpo (ver
## [code]_get_remains_basis()[/code]) y, en el siguiente frame de física, lo baja al suelo; solo
## entonces emite [code]released[/code], para que lo que caiga con él (el inventario) caiga en el
## suelo y no en el aire. Nunca devuelve los controles. No hace nada si no está atrapado.
func release_remains() -> void:
	if not _is_captured:
		return
	_follow()
	var spot: Vector3 = _last_body.origin
	_stop_following(not _separated)
	player.global_transform = Transform3D(_get_remains_basis(), spot)
	# Después de mover al jugador: la cámara cuelga de él.
	_drop_pieces()
	await _drop_to_floor()
	if _is_captured or not player or not player.is_inside_tree():
		return
	released.emit(true)


## En todos los peers, al revivir: retira sus restos de la cola y, en el dueño, devuelve la
## cámara a su sitio. Volver a mostrar el cuerpo vivo es cosa de [Player]. No hace nada si no
## tiene restos.
func discard_remains() -> void:
	if not _separated:
		return
	var queue: RemainsQueue = RemainsQueue.instance
	if is_instance_valid(queue):
		queue.remove_for(player)
	_separated = false
	_body_piece = null
	_head_piece = null
	if _camera_on_head:
		_camera_on_head = false
		if is_owner() and player.camera and not _is_captured:
			player.camera.transform = _camera_rest
	_update_processing()


## Atrapado, sigue a los nodos cada frame; si alguno desaparece (el captor salió del juego),
## suelta al jugador (o a sus restos) donde estaba. Con los restos sueltos, la cámara del dueño
## sigue a la cabeza.
func _process(_delta: float) -> void:
	if _is_captured:
		if not _are_anchors_valid():
			release()
			return
		_follow()
	elif _camera_on_head:
		_follow_head_piece()


## Copia el transform del nodo del cuerpo al jugador y, en el dueño, el de la cabeza a su
## cámara; recuerda los dos para soltarlo aunque los nodos ya no existan. Las piezas de los
## restos, mientras siguen congeladas, van con su nodo.
func _follow() -> void:
	if _are_anchors_valid():
		_read_anchors()
	player.global_transform = _last_body
	player.velocity = Vector3.ZERO
	if is_owner() and player.camera:
		player.camera.global_transform = _last_head
	if _is_piece_valid(_body_piece) and _body_piece.freeze:
		_body_piece.global_transform = _last_body
	if _is_piece_valid(_head_piece) and _head_piece.freeze:
		_head_piece.global_transform = _last_head


## Lee el transform de los dos nodos y, si la lectura anterior fue en el frame anterior, mide la
## velocidad lineal y de giro de cada uno: la que heredan los restos al soltarlos. Así no depende
## de cómo se muevan los nodos.
func _read_anchors() -> void:
	var body_now: Transform3D = _body_anchor.global_transform.orthonormalized()
	var head_now: Transform3D = _head_anchor.global_transform.orthonormalized()
	var frame: int = Engine.get_process_frames()
	var delta: float = get_process_delta_time()
	if _last_read_frame >= 0 and frame == _last_read_frame + 1 and delta > 0.0:
		_body_velocity = (body_now.origin - _last_body.origin) / delta
		_body_spin = _get_spin(_last_body.basis, body_now.basis, delta)
		_head_velocity = (head_now.origin - _last_head.origin) / delta
		_head_spin = _get_spin(_last_head.basis, head_now.basis, delta)
	_last_read_frame = frame
	_last_body = body_now
	_last_head = head_now


## Devuelve la velocidad angular (eje por radianes por segundo, en ejes globales) que lleva de
## [param from] a [param to] en [param delta] segundos, por el camino más corto.
static func _get_spin(from: Basis, to: Basis, delta: float) -> Vector3:
	var turn: Quaternion = (to * from.inverse()).get_rotation_quaternion()
	if turn.w < 0.0:
		turn = -turn
	var angle: float = turn.get_angle()
	if angle < 0.00001:
		return Vector3.ZERO
	return turn.get_axis().normalized() * angle / delta


## Deja de seguir y, si [param restore_camera], devuelve la cámara del dueño a su sitio en la
## cabeza.
func _stop_following(restore_camera: bool) -> void:
	_is_captured = false
	_body_anchor = null
	_head_anchor = null
	_update_processing()
	if restore_camera and is_owner() and player.camera:
		player.camera.transform = _camera_rest
	player.velocity = Vector3.ZERO


## Procesa mientras está atrapado o, ya suelto, mientras la cámara del dueño va con la cabeza.
func _update_processing() -> void:
	set_process(_is_captured or _camera_on_head)


## Construye una pieza de los restos: un [RigidBody3D] congelado (cinemático) que solo choca con
## el mundo, con [param content] dentro en [param content_transform] y una forma centrada en
## [param center], que también es su centro de masas.
## Recibe: [param piece_name] — nombre del nodo; [param shape] — su forma de colisión;
## [param mass] — kilos.
func _make_piece(piece_name: String, content: Node3D, content_transform: Transform3D,
		shape: Shape3D, center: Vector3, mass: float) -> RigidBody3D:
	var piece: RigidBody3D = RigidBody3D.new()
	piece.name = piece_name
	piece.collision_layer = 0
	piece.collision_mask = REMAINS_COLLISION_MASK
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	piece.freeze = true
	piece.mass = maxf(mass, 0.01)
	piece.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	piece.center_of_mass = center
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position = center
	piece.add_child(collision_shape)
	content.transform = content_transform
	piece.add_child(content)
	return piece


## Descongela las piezas con la velocidad medida de su nodo (en el centro de masas: la del
## origen más la del giro) y, en el dueño, pone la cámara a seguir a la cabeza. No hace nada sin
## restos.
func _drop_pieces() -> void:
	if not _separated:
		return
	if _is_piece_valid(_body_piece):
		_drop_piece(_body_piece, _last_body, _body_velocity, _body_spin)
	if _is_piece_valid(_head_piece):
		_drop_piece(_head_piece, _last_head, _head_velocity, _head_spin)
	if is_owner() and player.camera:
		_camera_on_head = true
		_last_camera = player.camera.global_transform
		_follow_head_piece()
	_update_processing()


## Descongela [param piece], que existe, en [param at] con [param velocity] y [param spin] (las
## de su nodo).
func _drop_piece(piece: RigidBody3D, at: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if not piece.freeze:
		return
	piece.freeze = false
	# Congelada (cinemática), el último transform se aplica en el siguiente paso de física y el
	# cambio de modo lo descarta: se repite ya en modo rígido, que lo aplica en el acto.
	piece.global_transform = at
	var center: Vector3 = at * piece.center_of_mass
	piece.linear_velocity = velocity + spin.cross(center - at.origin)
	piece.angular_velocity = spin


## Pone la cámara del dueño en la cabeza de los restos o, si la cola ya la liberó, la deja donde
## estaba la última vez (aunque el jugador se mueva: la cámara cuelga de él).
func _follow_head_piece() -> void:
	if not player or not player.camera:
		return
	if _is_piece_valid(_head_piece):
		_last_camera = _head_piece.global_transform
	player.camera.global_transform = _last_camera


## Devuelve [code]true[/code] si [param piece] existe, sigue en el árbol y nadie la ha mandado
## liberar. Recibe un [Variant]: la cola puede haber liberado la pieza, y pasar un objeto liberado
## a un parámetro tipado es un error.
func _is_piece_valid(piece: Variant) -> bool:
	if not is_instance_valid(piece):
		return false
	var node: Node = piece as Node
	return node != null and node.is_inside_tree() and not node.is_queued_for_deletion()


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


## Devuelve la base vertical del muerto al soltar su cuerpo. Con restos, mira hacia donde sale
## despedido el cuerpo: el inventario cae delante del jugador, así que cae de camino a sus restos
## y no al otro lado. Sin restos, o si el cuerpo apenas se mueve en horizontal, la de
## [code]_get_upright_basis()[/code].
func _get_remains_basis() -> Basis:
	var flight: Vector3 = Vector3(_body_velocity.x, 0.0, _body_velocity.z)
	if _separated and flight.length_squared() > 0.01:
		return Basis.looking_at(flight.normalized(), Vector3.UP)
	return _get_upright_basis()


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
