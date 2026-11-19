class_name Firearm
extends Equipment

## Arma de fuego, efectiva contra enemigos físicos y etéreos.

signal fired(origin: Vector3, direction: Vector3)
signal reloaded
signal ammo_changed(in_magazine: int, reserve: int)

const SWAY_SOURCE: StringName = &"firearm_sway"
const SHOT_COLLISION_MASK: int = 1 | Hitbox.HITBOX_LAYER
const MAX_ORIGIN_OFFSET: float = 3.0
const NO_ZONE: int = -1

@export var muzzle: Node3D

@export_group("Balística")
## Daño por disparo.
@export var damage: float = 25.0
## Tipos de daño que hace ([enum Statics.DamageType]).
@export var damage_types: int = Statics.DamageType.PHYSICAL | Statics.DamageType.ETHEREAL
## Metros de alcance del disparo.
@export var range_meters: float = 60.0
## Radianes de dispersión base del disparo.
@export var base_spread: float = 0.01
## Retroceso base de la vista por disparo.
@export var base_recoil: float = 0.03
## Disparos por segundo.
@export var fire_rate: float = 4.0
## Metros hasta donde se oye cada disparo.
@export var noise_radius: float = 40.0

@export_group("Munición")
## Balas por cargador.
@export var magazine_size: int = 8
## Segundos de recarga base.
@export var base_reload_time: float = 2.0

var in_magazine: int = 0
var reserve_ammo: int = 40

var _cooldown_left: float = 0.0
var _is_reloading: bool = false
var _debug_aim: FirearmDebugAim = null


## Resultado de un disparo resuelto en el servidor.
class ShotResult:
	var end: Vector3 = Vector3.ZERO
	var hitbox: Hitbox = null
	var damage: float = 0.0


## Llena el cargador y escucha el modo debug de combate.
func _ready() -> void:
	in_magazine = magazine_size
	Debug.combat_debug_toggled.connect(_on_combat_debug_toggled)


## Devuelve la munición del cargador y de la reserva.
func get_state() -> Dictionary:
	return {"in_magazine": in_magazine, "reserve_ammo": reserve_ammo}


## Restaura la munición guardada y emite [code]ammo_changed[/code].
func set_state(state: Dictionary) -> void:
	in_magazine = state.get("in_magazine", magazine_size)
	reserve_ammo = state.get("reserve_ammo", reserve_ammo)
	ammo_changed.emit(in_magazine, reserve_ammo)


## Aplica el temblor de vista al portador y, si toca, crea el rayo de depuración.
func _on_equipped() -> void:
	_apply_proficiency_modifiers()
	_update_debug_aim(_wants_debug_aim())


## Quita el temblor de vista, cancela la recarga y libera el rayo de depuración.
func _on_unequipped() -> void:
	if wielder and wielder.view:
		wielder.view.remove_modifier(SWAY_SOURCE)
	_is_reloading = false
	_update_debug_aim(false)


## Devuelve la posición global de la boca del cañón.
func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle else global_position


## Dispara, o recarga si el cargador está vacío.
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

	wielder.view.apply_recoil(base_recoil * _get_recoil_multiplier(), 0.0)
	fired.emit(origin, direction)
	used.emit()

	_request_fire.rpc_id(Statics.SERVER_ID, origin, direction)


## Recarga.
func alt_use() -> void:
	reload()


## Espera el tiempo de recarga y pasa balas de la reserva al cargador.
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
func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Añade a la vista del portador el temblor de su [FirearmProficiency].
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


## Valida en el servidor el disparo pedido y lo resuelve en el siguiente frame de física.
@rpc("any_peer", "call_local", "reliable")
func _request_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or not wielder:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != wielder.data.id:
		return
	if origin.distance_to(wielder.get_aim_origin()) > MAX_ORIGIN_OFFSET:
		return
	var aim: Vector3 = direction.normalized()
	if aim.is_zero_approx():
		return
	var shooter: Player = wielder
	await get_tree().physics_frame
	if not is_inside_tree() or not is_instance_valid(shooter):
		return
	_resolve_and_broadcast(shooter, origin, aim)


## Resuelve el disparo, emite su ruido y difunde los efectos a todos los peers.
func _resolve_and_broadcast(shooter: Player, origin: Vector3, aim: Vector3) -> void:
	var shot: ShotResult = _resolve_shot(shooter, origin, aim)
	StimulusBus.broadcast(Statics.StimulusKind.NOISE, Stimulus.CAUSE_SHOT, origin, noise_radius,
		shooter)
	var hitbox_path: NodePath = NodePath()
	var zone: int = NO_ZONE
	if shot.hitbox:
		hitbox_path = shot.hitbox.get_path()
		zone = shot.hitbox.zone
	_play_fire_effects.rpc(origin, shot.end, hitbox_path, zone, shot.damage)


## Lanza el rayo del disparo contra el mundo y las [Hitbox] y aplica el daño.
func _resolve_shot(shooter: Player, origin: Vector3, aim: Vector3) -> ShotResult:
	var shot: ShotResult = ShotResult.new()
	shot.end = origin + aim * range_meters
	var exclude: Array[RID] = [shooter.get_rid()]
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, shot.end, SHOT_COLLISION_MASK, exclude)
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return shot
	shot.end = hit["position"]
	shot.hitbox = hit["collider"] as Hitbox
	if shot.hitbox and shot.hitbox.receive_hit(damage, damage_types, shooter):
		shot.damage = damage * shot.hitbox.damage_multiplier
	return shot


## Muestra en cada peer los efectos del disparo resuelto.
@rpc("authority", "call_local", "reliable")
func _play_fire_effects(origin: Vector3, end: Vector3, hitbox_path: NodePath, zone: int,
		damage_dealt: float) -> void:
	if Debug.combat_debug:
		Debug.combat_debug.add_shot(origin, end, hitbox_path, zone, damage_dealt)


## Crea o libera el rayo de depuración al cambiar el modo debug de combate.
func _on_combat_debug_toggled(_enabled: bool) -> void:
	_update_debug_aim(_wants_debug_aim())


## Devuelve [code]true[/code] si toca dibujar el rayo de depuración.
func _wants_debug_aim() -> bool:
	return Debug.is_combat_debug_enabled() and wielder != null and wielder.is_local_player()


## Crea o libera el rayo de depuración.
func _update_debug_aim(wanted: bool) -> void:
	if wanted and not _debug_aim:
		_debug_aim = FirearmDebugAim.new(self)
		add_child(_debug_aim, false, Node.INTERNAL_MODE_BACK)
	elif not wanted and _debug_aim:
		_debug_aim.queue_free()
		_debug_aim = null


## Desvía [param direction] un ángulo aleatorio según la dispersión.
func _apply_spread(direction: Vector3) -> Vector3:
	var spread: float = base_spread * _get_spread_multiplier()
	if spread <= 0.0:
		return direction
	return direction.rotated(Vector3.UP, randf_range(-spread, spread)) \
		.rotated(Vector3.RIGHT, randf_range(-spread, spread)).normalized()


## Devuelve el multiplicador de dispersión de la competencia.
func _get_spread_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.spread_multiplier if firearm_proficiency else 1.0


## Devuelve el multiplicador de retroceso de la competencia.
func _get_recoil_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.recoil_multiplier if firearm_proficiency else 1.0


## Devuelve el multiplicador del tiempo de recarga de la competencia.
func _get_reload_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.reload_time_multiplier if firearm_proficiency else 1.0
