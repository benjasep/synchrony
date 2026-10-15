class_name HitReaction
extends Node

## Reacción de un enemigo al daño: las reglas y la red. La anatomía (qué clip, cómo se suma) la
## pone el [HitReactionRig] de su modelo, que le encuentra [Enemy]; esto no sabe qué modelo es.
## El servidor escucha cada impacto que hace daño en una [Hitbox] del enemigo, decide si
## reacciona y con qué, y lo difunde por RPC; cada peer reproduce la reacción en local. Sin
## [HitReactionRig] no hace nada.
##
## Reglas: no reacciona retirado o muerto, ni mientras dura el agarre (las manos sujetan a la
## víctima y el respingo las movería; el rescate por las rodillas ya tiene su animación), y como
## mucho una vez cada [code]min_interval[/code]. Al empezar un agarre o al retirarse, desvanece
## la reacción que suene.

## Se emite en todos los peers al lanzar una reacción: el gancho para el sonido.
signal reacted(reaction: StringName)

@export var enemy: Enemy
## Agarre del enemigo, si tiene: mientras dura no hay reacciones.
@export var grab: GrabAttack
## Segundos mínimos entre dos reacciones: con varios jugadores disparando, cada tiro la
## relanzaría y se quedaría congelada en el pico. No debería bajar del fundido de salida de los
## OneShot del árbol, o se relanzaría uno que aún se está desvaneciendo y lo que le quedara caería
## a cero de golpe.
@export var min_interval: float = 0.2

var _rig: HitReactionRig = null
var _interval_left: float = 0.0


## Escucha la retirada del enemigo y el inicio de su agarre, y espera a que [Enemy] termine de
## preparar su modelo para engancharse a su [HitReactionRig] y a sus hitboxes.
func _ready() -> void:
	if not enemy:
		return
	enemy.retreated.connect(_on_enemy_retreated)
	if grab:
		grab.grab_started.connect(_on_grab_started)
	# Enemy es el padre: su _ready() (que instancia el modelo) corre después que el nuestro.
	if enemy.is_node_ready():
		_bind()
	else:
		enemy.ready.connect(_bind, CONNECT_ONE_SHOT)


## Descuenta el intervalo entre reacciones.
## Recibe: [param delta] — segundos desde el frame anterior.
func _process(delta: float) -> void:
	if _interval_left > 0.0:
		_interval_left = maxf(_interval_left - delta, 0.0)


## Devuelve [code]true[/code] si el modelo trae un [HitReactionRig] utilizable.
func has_rig() -> bool:
	return _rig != null and _rig.is_valid()


## Devuelve [code]true[/code] si ahora mismo el enemigo puede reaccionar: con
## [HitReactionRig], presente, vivo y sin agarre en curso. No mira [code]min_interval[/code].
func can_react() -> bool:
	if not has_rig() or not enemy or enemy.is_retreated:
		return false
	if enemy.health and enemy.health.is_dead:
		return false
	return not grab or not grab.is_busy()


## Toma el [HitReactionRig] que [Enemy] encontró en su modelo y escucha los impactos de todas
## sus hitboxes. Sin rig no escucha nada.
func _bind() -> void:
	_rig = enemy.hit_reaction_rig
	if not has_rig():
		return
	for hitbox: Hitbox in enemy.hitboxes:
		hitbox.hit_received.connect(_on_hit_received)


## Solo servidor: ante un impacto que hizo daño, si puede reaccionar y pasó
## [code]min_interval[/code] desde la última vez, elige la reacción de esa hitbox y la difunde.
## Recibe: [param hitbox] — la que recibió el impacto; [param _amount] — daño final;
## [param _source] — causante.
func _on_hit_received(hitbox: Hitbox, _amount: float, _source: Node) -> void:
	if not multiplayer.is_server() or _interval_left > 0.0 or not can_react():
		return
	var reaction: StringName = _rig.get_reaction_for(hitbox)
	if reaction == &"":
		return
	_interval_left = min_interval
	_play.rpc(reaction)


## Lanza [param reaction] en todos los peers y emite [code]reacted[/code]. Lo difunde el
## servidor. Fiable para que no adelante a un inicio de agarre que salió antes; aun así, cada peer
## vuelve a mirar si puede reaccionar.
## Recibe: [param reaction] — nombre de la reacción en el [HitReactionRig].
@rpc("authority", "call_local", "reliable")
func _play(reaction: StringName) -> void:
	if can_react() and _rig.play(reaction):
		reacted.emit(reaction)


## Al empezar un agarre (en todos los peers), desvanece la reacción que suene.
func _on_grab_started(_victim: Player) -> void:
	if _rig:
		_rig.stop()


## Al retirarse (en todos los peers), desvanece la reacción que suene.
func _on_enemy_retreated() -> void:
	if _rig:
		_rig.stop()
