class_name MeleeAttack
extends Node

## Golpe simple de un enemigo: avisa, espera [code]windup[/code] y, si el objetivo sigue vivo,
## libre y al alcance, le quita [code]damage[/code]. Lo decide y lo resuelve el servidor; el
## aviso viaja por RPC a todos los peers, que encaran al enemigo con el objetivo y reproducen el
## clip. La anatomía (clip, tabla de eventos, hacia dónde golpea el modelo) la pone el [MeleeRig]
## de su modelo, que le encuentra [Enemy]; sin él (el cubo, los fantasmas) el golpe funciona
## igual, sin animación. Lo lanza [EnemyCombat], que aplica la regla del remate antes de
## elegirlo.
##
## El daño no espera al evento [code]impacto[/code] del clip: lo aplica el servidor al acabar
## [code]windup[/code], que tiene que coincidir con el tiempo de ese evento en el rig (lo avisa
## al engancharse y lo comprueba [code]tests/verify_attacks.gd[/code]).

## Se emite en todos los peers al empezar el golpe, ya encarado y con el clip lanzado.
signal strike_started(target: Player)
## Se emite en todos los peers en cada evento del clip del golpe ([code]impacto[/code],
## [code]mordida_aire[/code]): el gancho para sonidos y efectos. El daño no depende de él.
signal strike_event(event: StringName, target: Player)
## Solo se emite en el servidor, al resolver el golpe tras el windup.
## Recibe: [param hit] — [code]true[/code] si llegó a quitar vida.
signal strike_resolved(target: Player, hit: bool)

## Evento de la tabla del [MeleeRig] en el que el golpe llega al objetivo: su tiempo es el
## [code]windup[/code]. Es parte del contrato entre el modelo y estas reglas.
const EVENT_IMPACT: StringName = &"impacto"
## Hacia dónde golpea un enemigo sin [MeleeRig], en su espacio: -Z, la convención de Godot (y de
## [Player]). Sin modelo animado no se nota, pero así la futura IA puede asumir que todo golpe
## sale de frente.
const DEFAULT_FORWARD: Vector3 = Vector3.FORWARD
## Segundos de margen entre [code]windup[/code] y el tiempo del impacto en el clip: un frame a
## 30 fps, lo que redondea la importación del glb.
const WINDUP_TOLERANCE: float = 1.0 / 30.0

@export var enemy: Enemy
@export var damage: float = 25.0
## Metros desde el origen del enemigo hasta los pies del objetivo.
@export var reach: float = 2.2
## Segundos de aviso entre el inicio del golpe y el impacto. Con [MeleeRig], el tiempo del evento
## [code]impacto[/code] de su clip.
@export var windup: float = 0.5
## Segundos desde el impacto hasta poder volver a golpear.
@export var cooldown: float = 1.5

var _is_busy: bool = false
var _cooldown_left: float = 0.0
## Se incrementa en cada golpe y al cancelarlo: un windup que vuelve de su espera con otro
## número ya no vale.
var _serial: int = 0
var _rig: MeleeRig = null
## Objetivo del golpe cuyo clip suena en este peer, para [code]strike_event[/code].
var _target: Player = null


## Cancela el golpe en curso si el enemigo se retira y espera a que [Enemy] termine de preparar
## su modelo para engancharse a su [MeleeRig].
func _ready() -> void:
	if not enemy:
		return
	enemy.retreated.connect(_cancel)
	# Enemy es el padre: su _ready() (que instancia el modelo) corre después que el nuestro.
	if enemy.is_node_ready():
		_bind_rig()
	else:
		enemy.ready.connect(_bind_rig, CONNECT_ONE_SHOT)


## Descuenta el enfriamiento.
## Recibe: [param delta] — segundos desde el frame anterior.
func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Devuelve [code]true[/code] mientras dura el windup. Es estado del servidor: en los clientes
## no se mantiene.
func is_busy() -> bool:
	return _is_busy


## Devuelve [code]true[/code] si el modelo trae un [MeleeRig] utilizable.
func has_rig() -> bool:
	return _rig != null and _rig.is_valid()


## Devuelve [code]true[/code] si [param target] está al alcance del enemigo.
func is_in_reach(target: Player) -> bool:
	return enemy != null and target != null \
		and enemy.global_position.distance_to(target.global_position) <= reach


## Devuelve [code]true[/code] si ahora mismo podría empezar un golpe contra [param target]:
## sin golpe ni enfriamiento en curso, con el enemigo presente y el objetivo vivo, libre y al
## alcance.
func can_start(target: Player) -> bool:
	if _is_busy or _cooldown_left > 0.0 or not enemy or enemy.is_retreated:
		return false
	return _is_valid_target(target) and is_in_reach(target)


## Solo servidor: empieza un golpe contra [param target], avisa a todos los peers (con el
## enemigo ya encarado) y lo resuelve tras el windup.
## Devuelve: [code]true[/code] si el golpe empezó.
func start(target: Player) -> bool:
	if not multiplayer.is_server() or not can_start(target):
		return false
	_is_busy = true
	_serial += 1
	_announce_strike.rpc(target.get_path(), compute_facing_transform(target))
	_resolve_after_windup(target, _serial)
	return true


## Calcula cómo tiene que quedar el enemigo para que el golpe salga hacia [param target]: gira
## solo sobre la vertical y sin desplazarse hasta dejarlo sobre la línea del golpe, delante. La
## línea la da el [MeleeRig] (pasa por su origen, hacia su [code]forward[/code]), que no tiene
## por qué cruzar el origen del enemigo; sin rig es [constant DEFAULT_FORWARD] desde el origen.
## Si el objetivo está tan cerca que ningún giro lo pone sobre esa línea, apunta la dirección
## del golpe hacia él.
## Devuelve: el transform global encarado, o el actual si el objetivo no es válido o está justo
## encima.
func compute_facing_transform(target: Player) -> Transform3D:
	var current: Transform3D = enemy.global_transform
	if not is_instance_valid(target):
		return current
	var to_target: Vector3 = target.global_position - current.origin
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < 0.0001:
		return current
	# La línea del golpe, en planta y relativa al origen del enemigo tal como está ahora.
	var line_origin: Vector3 = Vector3.ZERO
	var line_forward: Vector3 = current.basis * DEFAULT_FORWARD
	if has_rig():
		line_origin = _rig.global_position - current.origin
		line_forward = _rig.get_forward()
	line_origin.y = 0.0
	line_forward.y = 0.0
	if line_forward.length_squared() < 0.0001:
		return current
	line_forward = line_forward.normalized()
	# El punto de la línea a la misma distancia del origen que el objetivo: girando sobre el
	# origen, ese punto es el que acaba encima de él.
	var lateral: Vector3 = line_origin - line_forward * line_origin.dot(line_forward)
	var aim: Vector3 = line_forward
	if distance > lateral.length():
		aim = lateral + line_forward * sqrt(distance * distance - lateral.length_squared())
	var yaw: float = atan2(to_target.x, to_target.z) - atan2(aim.x, aim.z)
	return Transform3D(Basis(Vector3.UP, yaw) * current.basis, current.origin)


## Avisa en todos los peers de que empieza un golpe: encara al enemigo, lanza el clip desde el
## principio y emite [code]strike_started[/code]. Lo difunde el servidor desde
## [code]start()[/code].
## Recibe: [param target_path] — ruta del [Player] objetivo, la misma en todos los peers;
## [param faced] — transform global del enemigo ya encarado.
@rpc("authority", "call_local", "reliable")
func _announce_strike(target_path: NodePath, faced: Transform3D) -> void:
	_target = get_node_or_null(target_path) as Player
	enemy.global_transform = faced
	if has_rig():
		_rig.play()
	strike_started.emit(_target)


## Corrutina del servidor: espera el windup (respetando la pausa) y, si el golpe sigue vigente,
## aplica el daño si el objetivo sigue siendo válido y al alcance; arranca el enfriamiento y
## emite [code]strike_resolved[/code].
## Recibe: [param target] — objetivo; [param serial] — número del golpe al empezar.
func _resolve_after_windup(target: Player, serial: int) -> void:
	await get_tree().create_timer(windup, false).timeout
	if serial != _serial or not is_inside_tree():
		return
	_is_busy = false
	_cooldown_left = cooldown
	var hit: bool = not enemy.is_retreated and _is_valid_target(target) and is_in_reach(target)
	if hit:
		target.health.apply_damage(damage, enemy)
	strike_resolved.emit(target if is_instance_valid(target) else null, hit)


## Busca el [MeleeRig] que [Enemy] encontró en su modelo, se engancha a sus señales y avisa si
## [code]windup[/code] no coincide con el impacto de su clip.
func _bind_rig() -> void:
	_rig = enemy.melee_rig
	if not _rig:
		return
	_rig.event_reached.connect(_on_rig_event)
	_rig.finished.connect(_on_rig_finished)
	var impact: float = _rig.get_event_time(EVENT_IMPACT)
	if impact >= 0.0 and absf(impact - windup) > WINDUP_TOLERANCE:
		push_warning("MeleeAttack de %s: windup %.3f s no coincide con %s a %.3f s"
			% [enemy.name, windup, EVENT_IMPACT, impact])


## Reemite cada evento del clip como [code]strike_event[/code], en todos los peers.
## Recibe: [param event] — nombre del evento en la tabla del [MeleeRig].
func _on_rig_event(event: StringName) -> void:
	strike_event.emit(event, _target if is_instance_valid(_target) else null)


## Al acabar el clip, olvida al objetivo.
func _on_rig_finished() -> void:
	_target = null


## Corta el golpe en curso sin aplicar daño, y su clip en todos los peers. Lo provoca la retirada
## del enemigo, que llega a todos por RPC.
func _cancel() -> void:
	if _rig:
		_rig.stop()
	_target = null
	if not _is_busy:
		return
	_is_busy = false
	_serial += 1


## Devuelve [code]true[/code] si [param target] existe, está en el árbol, vivo y no lo tiene
## atrapado nadie.
func _is_valid_target(target: Player) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.health != null \
		and not target.health.is_dead and not target.is_captured()
