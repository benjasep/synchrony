class_name EnemyLocomotion
extends Node

## Base de la locomoción de un enemigo: ejecuta en el servidor las órdenes de ir, frenar y parar.

signal arrived
signal blocked


## Lo que separa al enemigo de un sitio al que solo llegaría de una manera que no sabe.
class Barrier:
	extends RefCounted

	enum Kind {
		SQUEEZE,
		CLOSED_DOOR,
	}

	var kind: Kind = Kind.SQUEEZE
	var passage: Passage = null
	var mouth: Vector3 = Vector3.ZERO

@export var enemy: Enemy
@export var combat: EnemyCombat

@export_group("Velocidad")
## Velocidad, en m/s, al andar.
@export var walk_speed: float = 1.5
## Velocidad, en m/s, al correr.
@export var run_speed: float = 4.0
## Aceleración, en m/s², hacia la velocidad pedida.
@export var acceleration: float = 10.0
## Deceleración, en m/s², al frenar hasta pararse.
@export var braking: float = 5.0
## Radianes por segundo con que gira hacia donde avanza.
@export var turn_speed: float = 6.0

@export_group("Destino")
## Metros, en planta, a los que da el destino por alcanzado.
@export var arrive_distance: float = 0.4
## Metros: un destino nuevo más cerca que esto del actual no replantea el camino.
@export var retarget_distance: float = 0.5

@export_group("Modelo")
## Eje local hacia el que mira el modelo.
@export var forward: Vector3 = Vector3.FORWARD

var is_moving: bool = false

var _target: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _braking: bool = false
var _released: bool = false
var _released_frame: int = 0
var _squeeze: bool = true


## Se detiene en seco cuando el enemigo se retira o reaparece.
func _ready() -> void:
	if enemy:
		enemy.retreated.connect(halt)
		enemy.returned.connect(halt)


## Pide ir a [param target] a [param speed] m/s.
func move_to(target: Vector3, speed: float, squeeze: bool = true) -> bool:
	if not _is_server() or not enemy or speed <= 0.0:
		return false
	_released = false
	_braking = false
	_speed = speed
	if is_moving and squeeze == _squeeze and _target.distance_to(target) <= retarget_distance:
		_target = target
		_on_retargeted()
		return true
	_squeeze = squeeze
	if not _plan(target):
		stop()
		return false
	_target = target
	is_moving = true
	return true


## Va a [param target] andando.
func walk_to(target: Vector3, squeeze: bool = true) -> bool:
	return move_to(target, walk_speed, squeeze)


## Va a [param target] corriendo.
func run_to(target: Vector3, squeeze: bool = true) -> bool:
	return move_to(target, run_speed, squeeze)


## Olvida el destino y frena hasta pararse.
func stop() -> void:
	is_moving = false
	_released = false
	_on_stopped()
	_start_braking()


## Olvida el destino y se detiene en el acto.
func halt() -> void:
	is_moving = false
	_released = false
	_braking = false
	_on_stopped()
	if enemy and not is_crossing():
		enemy.velocity = Vector3.ZERO


## Suelta la orden en curso: si nadie la retoma en el próximo frame, frena.
func release() -> void:
	if not is_moving:
		return
	_released = true
	_released_frame = Engine.get_physics_frames()


## Devuelve [code]true[/code] mientras frena sin destino.
func is_braking() -> bool:
	return _braking


## Devuelve [code]true[/code] si soltó la orden y nadie la ha retomado.
func is_released() -> bool:
	return _released


## Devuelve [code]true[/code] si la orden en curso puede colarse por huecos.
func get_order_squeeze() -> bool:
	return _squeeze


## Devuelve [code]true[/code] si sabe llegar a [param target] desde donde está.
func can_reach(target: Vector3, squeeze: bool = true) -> bool:
	return enemy != null and _can_reach(target, squeeze)


## Devuelve lo que costaría llegar a [param target], en metros, o [code]INF[/code] si no llega.
func measure_path(target: Vector3, squeeze: bool = true) -> float:
	if not can_reach(target, squeeze):
		return INF
	return enemy.global_position.distance_to(target)


## Devuelve el punto más cercano a [param target] por el que podría moverse.
func get_nearest_reachable_point(target: Vector3) -> Vector3:
	return target


## Devuelve el punto más cercano a [param target] al que llega desde donde está.
func get_closest_reachable_point(target: Vector3, _squeeze_allowed: bool = true) -> Vector3:
	return target


## Devuelve la barrera que le impide llegar a un punto, o [code]null[/code] si no hay.
func find_barrier(_target_point: Vector3) -> Barrier:
	return null


## Devuelve el enlace de navegación por el que cruzaría un [Passage], o [code]null[/code].
func get_passage_link(_passage: Passage) -> LevelNavigation.PassageLink:
	return null


## Gira al enemigo sin desplazarlo para que mire hacia [param point].
func face_towards(point: Vector3, delta: float) -> void:
	if not enemy or not _is_server() or is_suspended():
		return
	_turn_towards(point - enemy.global_position, delta)


## Devuelve [code]true[/code] mientras atraviesa un hueco.
func is_crossing() -> bool:
	return false


## Devuelve el destino actual.
func get_target() -> Vector3:
	return _target


## Devuelve los metros que le quedan hasta el destino de la orden en curso.
func get_remaining_distance() -> float:
	if not enemy or not is_moving:
		return 0.0
	return get_flat_distance_to(_target)


## Devuelve los metros, en planta, hasta [param point].
func get_flat_distance_to(point: Vector3) -> float:
	var offset: Vector3 = point - enemy.global_position
	offset.y = 0.0
	return offset.length()


## Devuelve [code]true[/code] si no debe moverse: retirado o atacando.
func is_suspended() -> bool:
	if not enemy or enemy.is_retreated:
		return true
	return combat != null and combat.is_busy()


## Devuelve hacia dónde mira el modelo, en planta y normalizado.
func get_facing() -> Vector3:
	var facing: Vector3 = enemy.global_basis * forward
	facing.y = 0.0
	return facing.normalized()


## Avanza o frena un frame en el servidor.
func _physics_process(delta: float) -> void:
	if not enemy or not _is_server():
		return
	if _released and Engine.get_physics_frames() > _released_frame:
		stop()
	if is_suspended():
		enemy.velocity = Vector3.ZERO
		_braking = false
		return
	if _braking and not is_moving and not is_crossing():
		_brake(delta)
		return
	_advance(delta)


## Da el destino por alcanzado: frena y emite [code]arrived[/code].
func _finish_arrived() -> void:
	stop()
	arrived.emit()


## Abandona el destino: frena y emite [code]blocked[/code].
func _finish_blocked() -> void:
	stop()
	blocked.emit()


## Empieza a frenar si aún lleva velocidad en planta.
func _start_braking() -> void:
	_braking = enemy != null and not is_crossing() \
		and Vector2(enemy.velocity.x, enemy.velocity.z).length_squared() > 0.0001


## Frena un frame, cayendo si no pisa suelo.
func _brake(delta: float) -> void:
	var velocity: Vector3 = enemy.velocity
	if not enemy.is_on_floor():
		velocity += enemy.get_gravity() * delta
	var flat: Vector2 = Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, braking * delta)
	enemy.velocity = Vector3(flat.x, velocity.y, flat.y)
	enemy.move_and_slide()
	if flat.length_squared() < 0.0001 and enemy.is_on_floor():
		_braking = false
		enemy.velocity = Vector3.ZERO


## Gira al enemigo sobre el eje vertical hacia [param direction].
func _turn_towards(direction: Vector3, delta: float) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	var facing: Vector3 = get_facing()
	if flat.length_squared() < 0.0001 or facing.length_squared() < 0.0001:
		return
	var angle: float = facing.signed_angle_to(flat.normalized(), Vector3.UP)
	var step: float = clampf(angle, -turn_speed * delta, turn_speed * delta)
	enemy.rotate_y(step)


## Devuelve [code]true[/code] en el servidor o sin peer.
func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


## Prepara el viaje a un punto; lo implementa la subclase.
func _plan(_target_point: Vector3) -> bool:
	return false


## Devuelve [code]true[/code] si sabría llegar a un punto; lo implementa la subclase.
func _can_reach(_target_point: Vector3, _squeeze_allowed: bool) -> bool:
	return false


## Mueve al enemigo un frame; lo implementa la subclase.
func _advance(_delta: float) -> void:
	pass


## Se llama cuando el destino cambia poco y se mantiene el plan.
func _on_retargeted() -> void:
	pass


## Se llama al detenerse, por la razón que sea.
func _on_stopped() -> void:
	pass
