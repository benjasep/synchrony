class_name Firearm
extends Equipment

## Arma de fuego, efectiva contra enemigos físicos y etéreos. No hay un solo if sobre el rol:
## el temblor en manos inexpertas es un [ViewModifier] construido desde la
## [FirearmProficiency] del portador. El cliente da el feedback al instante, pero el disparo
## lo resuelve el servidor con un rayo contra el mundo y las [Hitbox]: si cada cliente
## calculase el daño, se desincronizarían.

signal fired(origin: Vector3, direction: Vector3)
signal reloaded
signal ammo_changed(in_magazine: int, reserve: int)

const SWAY_SOURCE: StringName = &"firearm_sway"
## Máscara del rayo del disparo: capa 1 (mundo, que lo bloquea) más la de las [Hitbox]. Nunca la
## 4, la caja de movimiento de los enemigos, que envuelve sus hitboxes y se tragaría el tiro, ni
## la 3, la de los interactuables.
const SHOT_COLLISION_MASK: int = 1 | Hitbox.HITBOX_LAYER
## Metros que puede separarse el origen que declara el cliente del punto de mira del tirador
## según el servidor. Holgado a propósito: absorbe el retraso de la posición replicada y solo
## descarta peticiones imposibles.
const MAX_ORIGIN_OFFSET: float = 3.0
## Zona que difunde [code]_play_fire_effects()[/code] cuando el tiro no dio en ninguna [Hitbox].
const NO_ZONE: int = -1

## Boca del cañón: de aquí sale el rayo azul del modo debug de combate. Sin ella, el propio arma.
@export var muzzle: Node3D

@export_group("Balística")
@export var damage: float = 25.0
@export var damage_types: int = Statics.DamageType.PHYSICAL | Statics.DamageType.ETHEREAL
@export var range_meters: float = 60.0
@export var base_spread: float = 0.01
@export var base_recoil: float = 0.03
@export var fire_rate: float = 4.0

@export_group("Munición")
@export var magazine_size: int = 8
@export var base_reload_time: float = 2.0

var in_magazine: int = 0
var reserve_ammo: int = 40

var _cooldown_left: float = 0.0
var _is_reloading: bool = false
## Rayo azul del modo debug de combate; solo existe en el peer del portador y con el modo
## encendido.
var _debug_aim: FirearmDebugAim = null


## Resultado de un disparo resuelto en el servidor: lo que difunde
## [code]_play_fire_effects()[/code].
class ShotResult:
	## Donde acabó el tiro: el impacto o, si no tocó nada, el final del alcance.
	var end: Vector3 = Vector3.ZERO
	## [Hitbox] que paró el tiro, o [code]null[/code] si fue el mundo o nada.
	var hitbox: Hitbox = null
	## Daño que hizo: [code]0[/code] si no dio en una hitbox o esta no lo aceptó.
	var damage: float = 0.0


## Empieza con el cargador lleno y escucha el modo debug de combate para su rayo azul.
func _ready() -> void:
	in_magazine = magazine_size
	Debug.combat_debug_toggled.connect(_on_combat_debug_toggled)


## Devuelve la munición del cargador y de la reserva, que sobrevive a soltar y recoger.
func get_state() -> Dictionary:
	return {"in_magazine": in_magazine, "reserve_ammo": reserve_ammo}


## Restaura la munición guardada (si falta una clave: cargador lleno y reserva actual) y
## emite [code]ammo_changed[/code].
## Recibe: [param state] — el diccionario que devolvió [code]get_state()[/code].
func set_state(state: Dictionary) -> void:
	in_magazine = state.get("in_magazine", magazine_size)
	reserve_ammo = state.get("reserve_ammo", reserve_ammo)
	ammo_changed.emit(in_magazine, reserve_ammo)


## Aplica al portador el temblor de vista que dicta su competencia y, con el modo debug de
## combate encendido y un portador local, crea el rayo azul.
func _on_equipped() -> void:
	_apply_proficiency_modifiers()
	_update_debug_aim(_wants_debug_aim())


## Quita el temblor de vista del portador, baja la marca de recarga y libera el rayo azul. Ojo:
## el temporizador de una recarga ya empezada no se cancela y, al vencer, carga igualmente.
func _on_unequipped() -> void:
	if wielder and wielder.view:
		wielder.view.remove_modifier(SWAY_SOURCE)
	_is_reloading = false
	_update_debug_aim(false)


## Devuelve la posición global de la boca del cañón, o la del arma si no tiene
## [code]muzzle[/code].
func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle else global_position


## Dispara si está empuñada, sin cooldown ni recarga en curso; con el cargador vacío recarga
## en su lugar. Gasta una bala, aplica dispersión y retroceso escalados por la competencia,
## emite [code]ammo_changed[/code], [code]fired[/code] y [code]used[/code] en local y pide al
## servidor que resuelva el disparo.
func use() -> void:
	if not is_equipped() or _cooldown_left > 0.0 or _is_reloading:
		return
	if in_magazine <= 0:
		reload()
		return

	in_magazine -= 1
	_cooldown_left = 1.0 / maxf(fire_rate, 0.01)
	ammo_changed.emit(in_magazine, reserve_ammo)

	var origin: Vector3 = wielder.get_aim_origin()
	var direction: Vector3 = _apply_spread(wielder.get_aim_direction())

	# Feedback local inmediato: no esperamos al servidor para el fogonazo.
	wielder.view.apply_recoil(base_recoil * _get_recoil_multiplier(), 0.0)
	fired.emit(origin, direction)
	used.emit()

	_request_fire.rpc_id(Statics.SERVER_ID, origin, direction)


## Acción secundaria: recarga.
func alt_use() -> void:
	reload()


## Corrutina: espera [code]base_reload_time[/code] escalado por la competencia, pasa balas de
## la reserva al cargador y emite [code]ammo_changed[/code] y [code]reloaded[/code]. No hace
## nada si ya está recargando, el cargador está lleno o no queda reserva.
func reload() -> void:
	if _is_reloading or in_magazine >= magazine_size or reserve_ammo <= 0:
		return
	_is_reloading = true
	await get_tree().create_timer(base_reload_time * _get_reload_multiplier()).timeout
	if not is_instance_valid(self):
		return
	var needed: int = magazine_size - in_magazine
	var loaded: int = mini(needed, reserve_ammo)
	in_magazine += loaded
	reserve_ammo -= loaded
	_is_reloading = false
	ammo_changed.emit(in_magazine, reserve_ammo)
	reloaded.emit()


## Descuenta el cooldown entre disparos.
## Recibe: [param delta] — segundos desde el frame anterior.
func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Registra en la vista del portador un [ViewModifier] de temblor con la amplitud y la
## frecuencia de su [FirearmProficiency]. No hace nada sin portador, vista o competencia de
## arma.
func _apply_proficiency_modifiers() -> void:
	if not wielder or not wielder.view:
		return
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	if not firearm_proficiency:
		return
	var modifier: ViewModifier = ViewModifier.new()
	modifier.sway_amplitude = firearm_proficiency.sway_amplitude
	modifier.sway_frequency = firearm_proficiency.sway_frequency
	wielder.view.add_modifier(SWAY_SOURCE, modifier)


## Solo el servidor resuelve el disparo: comprueba que el arma esté empuñada, que el emisor sea
## el portador y que el origen declarado quede cerca de él; en el siguiente frame de física
## lanza el rayo y difunde los efectos hasta donde acabó. [code]call_local[/code] es
## obligatorio: el host se lo envía a sí mismo y sin él Godot rechaza la llamada.
## Recibe: [param origin] — origen del rayo; [param direction] — dirección ya con dispersión.
@rpc("any_peer", "call_local", "reliable")
func _request_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or not wielder:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != wielder.data.id:
		return
	# Validación barata: no frena la trampa fina, solo disparos desde otro lado.
	if origin.distance_to(wielder.get_aim_origin()) > MAX_ORIGIN_OFFSET:
		return
	var aim: Vector3 = direction.normalized()
	if aim.is_zero_approx():
		return
	var shooter: Player = wielder
	# Los RPC llegan en el frame de proceso, y el espacio de física solo es
	# seguro de consultar dentro del de física.
	await get_tree().physics_frame
	if not is_inside_tree() or not is_instance_valid(shooter):
		return
	_resolve_and_broadcast(shooter, origin, aim)


## Resuelve el disparo en el servidor y difunde sus efectos a todos los peers: dónde acabó, la
## ruta y la zona de la hitbox que lo paró (vacía y [constant NO_ZONE] si ninguna) y el daño
## que hizo. Tiene que correr dentro de un frame de física.
## Recibe: lo mismo que [code]_resolve_shot()[/code].
func _resolve_and_broadcast(shooter: Player, origin: Vector3, aim: Vector3) -> void:
	var shot: ShotResult = _resolve_shot(shooter, origin, aim)
	var hitbox_path: NodePath = NodePath()
	var zone: int = NO_ZONE
	if shot.hitbox:
		hitbox_path = shot.hitbox.get_path()
		zone = shot.hitbox.zone
	_play_fire_effects.rpc(origin, shot.end, hitbox_path, zone, shot.damage)


## Lanza en el servidor el rayo del disparo, de [param origin] hasta [code]range_meters[/code],
## contra el mundo y las [Hitbox] y sin el tirador. Lo primero que toca lo para: una hitbox
## recibe el daño en su zona y el mundo se lo come.
## Recibe: [param shooter] — quien dispara, causante del daño; [param origin] — origen del
## rayo; [param aim] — dirección normalizada.
## Devuelve: dónde acabó el tiro (el impacto o, si no tocó nada, el final del alcance), qué
## hitbox lo paró y cuánto daño hizo.
func _resolve_shot(shooter: Player, origin: Vector3, aim: Vector3) -> ShotResult:
	var shot: ShotResult = ShotResult.new()
	shot.end = origin + aim * range_meters
	var exclude: Array[RID] = [shooter.get_rid()]
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, shot.end, SHOT_COLLISION_MASK, exclude)
	# Las hitboxes son Area3D, y un rayo las ignora salvo que se le pida.
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return shot
	shot.end = hit["position"]
	shot.hitbox = hit["collider"] as Hitbox
	if shot.hitbox and shot.hitbox.receive_hit(damage, damage_types, shooter):
		# Solo para mostrarlo: es la misma cuenta que hace receive_hit().
		shot.damage = damage * shot.hitbox.damage_multiplier
	return shot


## Efectos del disparo visibles para todos los peers, difundidos por el servidor una vez
## resuelto el tiro. Hoy solo el trazo del modo debug de combate, si este peer lo tiene
## encendido.
## Recibe: [param origin] — origen del disparo; [param end] — donde acabó: el impacto o el
## final del alcance; [param hitbox_path] — ruta absoluta de la [Hitbox] golpeada, vacía si
## ninguna; [param zone] — su [enum Statics.HitZone], o [constant NO_ZONE];
## [param damage_dealt] — daño que hizo.
@rpc("authority", "call_local", "reliable")
func _play_fire_effects(origin: Vector3, end: Vector3, hitbox_path: NodePath, zone: int,
		damage_dealt: float) -> void:
	# TODO: sonido, trazador y partículas visibles para todos los peers.
	if Debug.combat_debug:
		Debug.combat_debug.add_shot(origin, end, hitbox_path, zone, damage_dealt)


## Crea o libera el rayo azul al encender o apagar el modo debug de combate.
## Recibe: [param _enabled] — sin usar: lo decide [code]_wants_debug_aim()[/code].
func _on_combat_debug_toggled(_enabled: bool) -> void:
	_update_debug_aim(_wants_debug_aim())


## Devuelve [code]true[/code] si toca dibujar el rayo azul: modo debug de combate encendido y
## empuñada por el jugador de este peer.
func _wants_debug_aim() -> bool:
	return Debug.is_combat_debug_enabled() and wielder != null and wielder.is_local_player()


## Crea o libera el rayo azul. Va como hijo interno: [code]Statics.force_visual_layer()[/code],
## que [code]equip()[/code] aplica al arma entera, no lo saca de la capa 4.
## Recibe: [param wanted] — [code]true[/code] para que exista.
func _update_debug_aim(wanted: bool) -> void:
	if wanted and not _debug_aim:
		_debug_aim = FirearmDebugAim.new(self)
		add_child(_debug_aim, false, Node.INTERNAL_MODE_BACK)
	elif not wanted and _debug_aim:
		_debug_aim.queue_free()
		_debug_aim = null


## Desvía la dirección un ángulo aleatorio de hasta ±dispersión radianes alrededor de los
## ejes Y y X globales; la dispersión es [code]base_spread[/code] por el multiplicador de la
## competencia.
## Recibe: [param direction] — dirección de apuntado.
## Devuelve: la dirección desviada y normalizada, o la original si la dispersión es 0.
func _apply_spread(direction: Vector3) -> Vector3:
	var spread: float = base_spread * _get_spread_multiplier()
	if spread <= 0.0:
		return direction
	return direction.rotated(Vector3.UP, randf_range(-spread, spread)) \
		.rotated(Vector3.RIGHT, randf_range(-spread, spread)).normalized()


## Devuelve el multiplicador de dispersión de la competencia, o 1.0 si no es de arma.
func _get_spread_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.spread_multiplier if firearm_proficiency else 1.0


## Devuelve el multiplicador de retroceso de la competencia, o 1.0 si no es de arma.
func _get_recoil_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.recoil_multiplier if firearm_proficiency else 1.0


## Devuelve el multiplicador del tiempo de recarga de la competencia, o 1.0 si no es de arma.
func _get_reload_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.reload_time_multiplier if firearm_proficiency else 1.0
