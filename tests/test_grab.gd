extends Node3D

## Escena de prueba del golpe, el agarre y la reacción al daño de la pesadilla: ábrela y pulsa
## F6. Genera sin lobby un jugador local (militar, con arma) delante de la pesadilla y un maniquí
## con arma a su costado izquierdo, y añade teclas de depuración leídas como [InputEventKey], sin
## tocar el mapa de input:
## - [code]F1[/code]: la pesadilla ataca al jugador más cercano con la regla del remate: golpe si
##   le sobra vida (se encara con él y suena su clip), agarre si el golpe lo dejaría a 0 o menos.
## - [code]F2[/code]: fuerza el agarre sobre el jugador más cercano, esté donde esté.
## - [code]F3[/code]: disparo de rescate: un rayo real del maniquí hacia la posición global de
##   [code]canilla_1.L[/code], por la ruta de resolución del servidor del arma. Rescata si llega
##   durante el mordisco.
## - [code]F4[/code]: revive al jugador local o le llena la vida.
## - [code]F5[/code]: deja al jugador local con 15 de vida, para ver el agarre con [code]F1[/code].
## Son F1–F5 y no 1–5 porque 1–4 cambian de item. [code]F9[/code] (de [code]Debug[/code], vale en
## cualquier escena) enciende el modo debug de combate: hitboxes, rayo de apuntado y disparos.
## Para ver la reacción al daño basta con disparar a la pesadilla con el clic izquierdo: cualquier
## zona la hace reaccionar (la cabeza y las rodillas, con la del cuerpo mientras no tengan la
## suya), como mucho una vez cada [code]min_interval[/code] y nunca durante el agarre.
## El resto de controles son los del jugador (ver CLAUDE.md). Todo se anuncia con
## [code]Debug.log[/code]: los eventos del golpe y del agarre y cada reacción.

const FIREARM_SCENE: String = "res://equipment/firearm.tscn"
## Hueso al que apunta el disparo de rescate: nace en la rodilla izquierda.
const RESCUE_BONE: StringName = &"canilla_1.L"
const LOW_HEALTH: float = 15.0

@export var pesadilla: Enemy
@export var spawner: PlayerSpawner

var _combat: EnemyCombat
var _melee: MeleeAttack
var _grab: GrabAttack
var _reaction: HitReaction


## Busca los componentes de ataque y de reacción, arma a los maniquíes y anuncia las teclas. El
## spawner, hijo de esta escena, ya generó a los jugadores en su propio [code]_ready()[/code].
func _ready() -> void:
	_combat = pesadilla.get_node_or_null("Combat") as EnemyCombat
	_melee = pesadilla.get_node_or_null("Melee") as MeleeAttack
	_grab = pesadilla.get_node_or_null("Grab") as GrabAttack
	_reaction = pesadilla.get_node_or_null("HitReaction") as HitReaction
	if not _combat or not _melee or not _grab or not _reaction:
		push_error("test_grab: la pesadilla no trae Combat, Melee, Grab y HitReaction")
		return
	_arm_dummies()
	_melee.strike_started.connect(func(target: Player) -> void:
		Debug.log("Golpe iniciado contra %s" % _describe(target)))
	_melee.strike_event.connect(func(event: StringName, _target: Player) -> void:
		Debug.log("Golpe: %s" % event))
	_melee.strike_resolved.connect(func(target: Player, hit: bool) -> void:
		Debug.log("Golpe %s: %s" % ["acierta" if hit else "falla", _describe(target)]))
	_reaction.reacted.connect(func(reaction: StringName) -> void:
		Debug.log("Pesadilla reacciona: %s" % reaction))
	_grab.sequence_event.connect(func(event: StringName, _victim: Player) -> void:
		Debug.log("Agarre: %s" % event))
	_grab.grab_finished.connect(func() -> void: Debug.log("Agarre terminado"))
	pesadilla.health.damaged.connect(func(amount: float, zone: Statics.HitZone, _source: Node) -> void:
		Debug.log("Pesadilla: -%d en %s" % [int(amount), Statics.HitZone.keys()[zone]]))
	Debug.log("F1 atacar | F2 forzar agarre | F3 disparo de rescate | F4 revivir | F5 dejar a 15"
		+ " | F9 debug de combate | clic: disparar (reacciona)", 8.0)


## Atiende las teclas de depuración. Solo en el servidor: es quien decide los ataques.
## Recibe: [param event] — evento de input no consumido.
func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not key or not key.pressed or key.echo or not multiplayer.is_server():
		return
	match key.physical_keycode:
		KEY_F1:
			_attack_nearest()
		KEY_F2:
			_force_grab()
		KEY_F3:
			_rescue_shot()
		KEY_F4:
			_restore_local_player()
		KEY_F5:
			_set_local_health(LOW_HEALTH)


## La pesadilla ataca al jugador vivo más cercano con [code]EnemyCombat.attack()[/code].
func _attack_nearest() -> void:
	var target: Player = _get_nearest_player()
	if not target:
		Debug.log("No hay jugadores vivos")
		return
	var kind: String = "agarre" if _combat.wants_grab(target) else "golpe"
	if _combat.attack(target):
		Debug.log("Ataque (%s) a %s" % [kind, _describe(target)])
	else:
		Debug.log("Le toca %s, pero no puede: lejos, ocupada o en enfriamiento" % kind)


## Fuerza el agarre sobre el jugador vivo más cercano, sin mirar la regla ni el alcance.
func _force_grab() -> void:
	var target: Player = _get_nearest_player()
	if not target or not _grab.start(target, true):
		Debug.log("No puede agarrar ahora (ocupada, en enfriamiento o retirada)")


## Corrutina: el primer jugador libre con un arma empuñada que no sea la víctima dispara un rayo
## real hacia la posición global de [constant RESCUE_BONE], resuelto en un frame de física por
## [code]Firearm._resolve_and_broadcast()[/code], que además difunde sus efectos (el trazo del
## modo debug de combate, F9). No pasa por [code]_request_fire()[/code]: el maniquí no tiene
## peer y la validación del emisor lo rechazaría.
func _rescue_shot() -> void:
	var rig: GrabRig = pesadilla.grab_rig
	var shooter: Player = _get_free_shooter()
	if not rig or not shooter:
		Debug.log("Nadie libre con un arma para disparar")
		return
	var gun: Firearm = shooter.inventory.active_item as Firearm
	var skeleton: Skeleton3D = rig.skeleton
	var bone: Transform3D = skeleton.global_transform \
		* skeleton.get_bone_global_pose(skeleton.find_bone(RESCUE_BONE))
	var origin: Vector3 = shooter.get_aim_origin()
	await get_tree().physics_frame
	if not is_instance_valid(gun) or not is_instance_valid(shooter):
		return
	gun._resolve_and_broadcast(shooter, origin, (bone.origin - origin).normalized())
	Debug.log("Disparo de rescate de %s" % _describe(shooter))


## Revive al jugador local si está muerto o, si no, le llena la vida.
func _restore_local_player() -> void:
	var player: Player = spawner.get_player(multiplayer.get_unique_id())
	if not player:
		return
	if player.health.is_dead:
		player.health.revive()
	else:
		player.health.heal(player.health.max_health)
	Debug.log("Jugador local: %d de vida" % int(player.health.current_health))


## Deja la vida del jugador local en [param value], si está vivo.
func _set_local_health(value: float) -> void:
	var player: Player = spawner.get_player(multiplayer.get_unique_id())
	if not player or player.health.is_dead:
		return
	player.health.heal(player.health.max_health)
	player.health.apply_damage(player.health.max_health - value)
	Debug.log("Jugador local: %d de vida" % int(player.health.current_health))


## Da un arma empuñada a cada maniquí que no la tenga: alguien tiene que poder rescatar.
func _arm_dummies() -> void:
	for player: Player in _get_players():
		if player.data.id == multiplayer.get_unique_id() \
				or player.inventory.has_tag(Statics.EquipmentTag.FIREARM):
			continue
		player.inventory.add_item_from_scene(FIREARM_SCENE, {})
		if not (player.inventory.active_item is Firearm):
			player.inventory._apply_equip.rpc(player.inventory.items.size() - 1)


## Devuelve el jugador vivo más cercano a la pesadilla, o [code]null[/code].
func _get_nearest_player() -> Player:
	var nearest: Player = null
	var best: float = INF
	for player: Player in _get_players():
		if player.health.is_dead:
			continue
		var distance: float = player.global_position.distance_to(pesadilla.global_position)
		if distance < best:
			nearest = player
			best = distance
	return nearest


## Devuelve un jugador vivo, libre y con un arma empuñada que no sea la víctima del agarre, o
## [code]null[/code]. Prefiere a los maniquíes, que no tienen a nadie a los mandos.
func _get_free_shooter() -> Player:
	var fallback: Player = null
	for player: Player in _get_players():
		if player.health.is_dead or player.is_captured():
			continue
		if player == _grab.get_victim() or not (player.inventory.active_item is Firearm):
			continue
		if player.data.id != multiplayer.get_unique_id():
			return player
		fallback = player
	return fallback


## Devuelve los jugadores de [PlayerSpawner] que siguen existiendo: el spawner no quita las
## entradas ya liberadas.
func _get_players() -> Array[Player]:
	var found: Array[Player] = []
	for value: Variant in spawner.players.values():
		if is_instance_valid(value):
			var player: Player = value as Player
			if player:
				found.append(player)
	return found


## Devuelve un nombre legible de [param player] para los mensajes.
func _describe(player: Player) -> String:
	if not is_instance_valid(player):
		return "(nadie)"
	return "%s (%d de vida)" % [player.get_display_name(), int(player.health.current_health)]
