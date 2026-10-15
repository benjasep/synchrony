class_name GrabAttack
extends Node

## Agarre de un enemigo: las reglas, la red y la víctima. La anatomía (animación, huesos de la
## presa, tabla de tiempos) la pone el [GrabRig] de su modelo, que le encuentra [Enemy]; esto no
## sabe qué modelo es. El servidor decide cuándo empieza, cuánto dura el mordisco, si hay
## rescate y cuándo muere la víctima, y lo difunde por RPC; cada peer reproduce la animación en
## local y mueve a la víctima desde sus propios huesos. Lo lanza [EnemyCombat] como remate.
##
## Secuencia: alinear → alcance ([code]contacto[/code]: la víctima queda atrapada) → levantar →
## mordisco durante [code]bite_duration[/code] → remate ([code]separacion[/code]: muere;
## [code]soltar_restos[/code]: se suelta su cuerpo) o, si en el mordisco le dañan una zona de
## rescate, salida que suelta a la víctima viva ([code]soltar_victima[/code]). Si el enemigo se
## retira a mitad, la víctima queda libre y viva.

## Se emite en todos los peers al empezar, tras alinear al enemigo.
signal grab_started(victim: Player)
## Se emite en todos los peers en cada evento de la animación, también los que solo son sonido
## ([code]cabeza_agarrada[/code], [code]mordida[/code], [code]crujido[/code],
## [code]golpe_suelo[/code]): el gancho para sonidos y efectos.
signal sequence_event(event: StringName, victim: Player)
## Se emite en todos los peers al soltar a la víctima.
## Recibe: [param alive] — [code]false[/code] si lo que se soltó fue su cuerpo.
signal victim_released(victim: Player, alive: bool)
## Se emite en todos los peers al terminar o cortarse la secuencia.
signal grab_finished

## Eventos de la tabla del [GrabRig] que cambian el estado de la víctima. Son el contrato entre
## el modelo y estas reglas.
const EVENT_CONTACT: StringName = &"contacto"
const EVENT_SEPARATION: StringName = &"separacion"
const EVENT_DROP_REMAINS: StringName = &"soltar_restos"
const EVENT_RELEASE_VICTIM: StringName = &"soltar_victima"

enum Phase {
	IDLE, ## Sin agarre.
	REACHING, ## De la alineación al contacto, y levantando a la víctima.
	BITING, ## En el mordisco: la ventana de rescate.
	ENDING, ## Rematando o soltando, ya sin vuelta atrás.
}

@export var enemy: Enemy
## Metros desde el origen del enemigo hasta los pies de la víctima. La alineación desplaza al
## enemigo lo que sobre o falte hasta dejarla sobre el hueso del cuerpo de la presa.
@export var reach: float = 2.2
## Segundos desde que termina un agarre hasta poder empezar otro.
@export var cooldown: float = 3.0
## Segundos de mordisco antes de rematar: la ventana de rescate.
@export var bite_duration: float = 3.0
@export var rescue_zones: Array[Statics.HitZone] = [Statics.HitZone.PUNTO_DEBIL]
## Daño acumulado en esas zonas durante el mordisco. 0 = cualquier impacto rescata.
@export var rescue_damage_threshold: float = 0.0

## Fase del agarre en este peer. Solo lectura.
var phase: Phase = Phase.IDLE

var _victim: Player = null
var _rig: GrabRig = null
var _cooldown_left: float = 0.0
var _rescue_damage: float = 0.0
## Se incrementa en cada agarre: un temporizador de mordisco de un agarre anterior no vale.
var _serial: int = 0


## Escucha el daño del enemigo (el rescate) y su retirada, y espera a que [Enemy] termine de
## preparar su modelo para engancharse a su [GrabRig].
func _ready() -> void:
	if not enemy:
		return
	if enemy.health:
		enemy.health.damaged.connect(_on_enemy_damaged)
	enemy.retreated.connect(_on_enemy_retreated)
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


## Devuelve [code]true[/code] desde que empieza hasta que termina la secuencia.
func is_busy() -> bool:
	return phase != Phase.IDLE


## Devuelve la víctima del agarre en curso, o [code]null[/code].
func get_victim() -> Player:
	return _victim if is_instance_valid(_victim) else null


## Devuelve [code]true[/code] si el modelo trae un [GrabRig] utilizable.
func has_rig() -> bool:
	return _rig != null and _rig.is_valid()


## Devuelve [code]true[/code] si [param target] está al alcance del agarre.
func is_in_reach(target: Player) -> bool:
	return enemy != null and target != null \
		and enemy.global_position.distance_to(target.global_position) <= reach


## Devuelve [code]true[/code] si ahora mismo podría empezar un agarre sobre [param target]: con
## [GrabRig], sin agarre ni enfriamiento en curso, con el enemigo presente y la víctima viva,
## libre, al alcance y con [CaptureComponent].
## Recibe: [param ignore_reach] — solo para depurar: alinea al enemigo esté donde esté.
func can_start(target: Player, ignore_reach: bool = false) -> bool:
	if not has_rig() or is_busy() or _cooldown_left > 0.0 or not enemy or enemy.is_retreated:
		return false
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.capture:
		return false
	if not target.health or target.health.is_dead or target.is_captured():
		return false
	return ignore_reach or is_in_reach(target)


## Solo servidor: alinea al enemigo con [param target] y difunde el inicio del agarre.
## Recibe: [param ignore_reach] — solo para depurar, ver [code]can_start()[/code].
## Devuelve: [code]true[/code] si el agarre empezó.
func start(target: Player, ignore_reach: bool = false) -> bool:
	if not multiplayer.is_server() or not can_start(target, ignore_reach):
		return false
	_begin.rpc(target.get_path(), compute_aligned_transform(target))
	return true


## Calcula dónde tiene que quedar el enemigo para que [param target] quede sobre el hueso del
## cuerpo de la presa en reposo, mirando al enemigo. La dirección de la presa sale del hueso
## (en la pesadilla, -X del modelo): el enemigo gira sobre su línea central hasta encararla y se
## desliza hasta dejarla encima; conserva su altura, que es la de su suelo.
## Devuelve: el transform global alineado, o el actual si no hay [GrabRig].
func compute_aligned_transform(target: Player) -> Transform3D:
	var current: Transform3D = enemy.global_transform
	if not has_rig():
		return current
	var presa: Transform3D = current.affine_inverse() * _rig.get_rest_body_transform()
	# +Z de la presa: del enemigo hacia la víctima (su -Z mira al enemigo).
	var facing: Vector3 = Vector3(presa.basis.z.x, 0.0, presa.basis.z.z)
	if facing.length_squared() < 0.0001:
		return current
	facing = facing.normalized()
	var offset: Vector3 = presa.origin
	# Gira sobre la línea central que pasa bajo la presa, no sobre el origen: si la víctima ya
	# está donde toca, el resultado es el transform actual.
	var pivot: Vector3 = current * (offset - facing * offset.dot(facing))
	var to_target: Vector3 = target.global_position - pivot
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		to_target = current.basis * facing
		to_target.y = 0.0
	var yaw: float = atan2(to_target.x, to_target.z) - atan2(facing.x, facing.z)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var origin: Vector3 = target.global_position - basis * offset
	origin.y = current.origin.y
	return Transform3D(basis, origin)


## Busca el [GrabRig] que [Enemy] encontró en su modelo y se engancha a sus señales.
func _bind_rig() -> void:
	_rig = enemy.grab_rig
	if not _rig:
		return
	_rig.event_reached.connect(_on_rig_event)
	_rig.hold_started.connect(_on_rig_hold_started)
	_rig.finished.connect(_on_rig_finished)


## Empieza el agarre en todos los peers: coloca al enemigo alineado, recuerda a la víctima y
## arranca la animación. Lo difunde el servidor desde [code]start()[/code].
## Recibe: [param victim_path] — ruta del [Player], la misma en todos los peers;
## [param aligned] — transform global del enemigo ya alineado.
@rpc("authority", "call_local", "reliable")
func _begin(victim_path: NodePath, aligned: Transform3D) -> void:
	if not has_rig():
		return
	_serial += 1
	_victim = get_node_or_null(victim_path) as Player
	_rescue_damage = 0.0
	phase = Phase.REACHING
	enemy.global_transform = aligned
	_rig.start()
	grab_started.emit(get_victim())


## Saca al enemigo del mordisco hacia el remate en todos los peers. Lo difunde el servidor al
## acabar [code]bite_duration[/code].
@rpc("authority", "call_local", "reliable")
func _finish_bite() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.ENDING
	_rig.finish()


## Saca al enemigo del mordisco hacia la salida que suelta a la víctima viva, en todos los
## peers. Lo difunde el servidor al recibir daño suficiente en una zona de rescate.
@rpc("authority", "call_local", "reliable")
func _interrupt() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.ENDING
	_rig.interrupt()


## Corta el agarre en todos los peers. Lo difunde el servidor si al llegar el contacto la
## víctima ya no existe o está muerta.
@rpc("authority", "call_local", "reliable")
func _abort() -> void:
	_abort_locally()


## Reacciona a cada evento de la animación (en todos los peers, cada uno con la suya): atrapa,
## suelta o, en el servidor, mata a la víctima, y reemite el evento como
## [code]sequence_event[/code].
## Recibe: [param event] — nombre del evento en la tabla del [GrabRig].
func _on_rig_event(event: StringName) -> void:
	if phase == Phase.IDLE:
		return
	match event:
		EVENT_CONTACT:
			_catch_victim()
		EVENT_SEPARATION:
			if multiplayer.is_server() and get_victim():
				_victim.health.kill(enemy)
		EVENT_DROP_REMAINS:
			_release_victim(false)
		EVENT_RELEASE_VICTIM:
			_release_victim(true)
	sequence_event.emit(event, get_victim())


## Al entrar en el bucle del mordisco abre la ventana de rescate y, en el servidor, arranca la
## cuenta de [code]bite_duration[/code].
func _on_rig_hold_started() -> void:
	if phase != Phase.REACHING:
		return
	phase = Phase.BITING
	_rescue_damage = 0.0
	if multiplayer.is_server():
		_finish_bite_after_delay(_serial)


## Corrutina del servidor: espera [code]bite_duration[/code] (respetando la pausa) y remata si
## el mismo agarre sigue en el mordisco, es decir, si nadie lo rescató.
## Recibe: [param serial] — número del agarre al abrir la ventana.
func _finish_bite_after_delay(serial: int) -> void:
	await get_tree().create_timer(bite_duration, false).timeout
	if serial != _serial or phase != Phase.BITING or not is_inside_tree():
		return
	_finish_bite.rpc()


## Solo servidor: durante el mordisco, suma el daño que entra por una zona de rescate y, al
## llegar a [code]rescue_damage_threshold[/code], interrumpe el agarre.
## Recibe: [param amount] — daño del impacto; [param zone] — zona donde entró;
## [param _source] — causante (cualquiera puede rescatar).
func _on_enemy_damaged(amount: float, zone: Statics.HitZone, _source: Node) -> void:
	if not multiplayer.is_server() or phase != Phase.BITING or not rescue_zones.has(zone):
		return
	_rescue_damage += amount
	if _rescue_damage >= rescue_damage_threshold:
		_interrupt.rpc()


## Al terminar la animación: suelta a la víctima si aún la sujetaba (no debería) y da el
## agarre por terminado.
func _on_rig_finished() -> void:
	if phase == Phase.IDLE:
		return
	_release_victim(_is_victim_alive())
	_end()


## En todos los peers: si el enemigo se retira a mitad del agarre, la víctima queda libre (viva,
## si aún lo estaba) y la animación vuelve a la locomoción sin más eventos.
func _on_enemy_retreated() -> void:
	_abort_locally()


## Atrapa a la víctima con los nodos de la presa si sigue viva y libre. Si ya no lo está, el
## servidor corta el agarre.
func _catch_victim() -> void:
	var victim: Player = get_victim()
	if victim and _is_victim_alive() and victim.capture and not victim.is_captured():
		victim.capture.capture(_rig.body_anchor, _rig.head_anchor)
	elif multiplayer.is_server():
		_abort.rpc()


## Suelta a la víctima si la tiene atrapada y emite [code]victim_released[/code].
## Recibe: [param alive] — [code]true[/code] para soltarla viva y de pie; [code]false[/code]
## para soltar su cuerpo en el suelo.
func _release_victim(alive: bool) -> void:
	var victim: Player = get_victim()
	if not victim or not victim.capture or not victim.capture.is_captured():
		return
	if alive:
		victim.capture.release()
	else:
		victim.capture.release_remains()
	victim_released.emit(victim, alive)


## Corta el agarre en este peer: suelta a la víctima como esté (viva o sus restos), devuelve la
## animación a la locomoción y lo da por terminado.
func _abort_locally() -> void:
	if phase == Phase.IDLE:
		return
	_release_victim(_is_victim_alive())
	if _rig:
		_rig.stop()
	_end()


## Da el agarre por terminado: olvida a la víctima, arranca el enfriamiento y emite
## [code]grab_finished[/code].
func _end() -> void:
	phase = Phase.IDLE
	_victim = null
	_cooldown_left = cooldown
	grab_finished.emit()


## Devuelve [code]true[/code] si la víctima existe y no está muerta.
func _is_victim_alive() -> bool:
	var victim: Player = get_victim()
	return victim != null and victim.health != null and not victim.health.is_dead
