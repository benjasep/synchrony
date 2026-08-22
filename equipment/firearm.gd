class_name Firearm
extends Equipment

## Arma de fuego. Efectiva contra enemigos físicos y etéreos.
##
## Es el caso que valida todo el modelo de competencia: en manos del militar el
## pulso es firme; en manos de cualquier otro, la vista tiembla al apuntar.
## Fíjate en que no hay un solo if sobre el rol — el temblor es un ViewModifier
## construido desde el FirearmProficiency del portador.
##
## Autoridad: el cliente reproduce el feedback local de inmediato y pide al
## servidor que resuelva el disparo. Si cada cliente calculase el daño, los
## enemigos se desincronizarían en la primera partida.

signal fired(origin: Vector3, direction: Vector3)
signal reloaded
signal ammo_changed(in_magazine: int, reserve: int)

const SWAY_SOURCE: StringName = &"firearm_sway"

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


func _ready() -> void:
	in_magazine = magazine_size


func get_state() -> Dictionary:
	return {"in_magazine": in_magazine, "reserve_ammo": reserve_ammo}


func set_state(state: Dictionary) -> void:
	in_magazine = state.get("in_magazine", magazine_size)
	reserve_ammo = state.get("reserve_ammo", reserve_ammo)
	ammo_changed.emit(in_magazine, reserve_ammo)


func _on_equipped() -> void:
	_apply_proficiency_modifiers()


func _on_unequipped() -> void:
	if wielder and wielder.view:
		wielder.view.remove_modifier(SWAY_SOURCE)
	_is_reloading = false


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

	_request_fire.rpc_id(1, origin, direction)


func alt_use() -> void:
	reload()


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


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Construye el temblor de vista desde la competencia del portador.
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


## call_local es obligatorio: el host se envía esto a sí mismo (rpc_id(1) siendo
## el peer 1) y sin él Godot lo rechaza, así que el anfitrión no podría disparar.
@rpc("any_peer", "call_local", "reliable")
func _request_fire(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and (not wielder or sender_id != wielder.data.id):
		return
	# TODO: raycast contra el mundo y aplicar daño cuando existan los enemigos.
	# El servidor es quien resuelve el impacto; el cliente solo pidió disparar.
	_play_fire_effects.rpc(origin, direction)


@rpc("authority", "call_local", "reliable")
func _play_fire_effects(_origin: Vector3, _direction: Vector3) -> void:
	# TODO: sonido y partículas visibles para todos los peers.
	pass


func _apply_spread(direction: Vector3) -> Vector3:
	var spread: float = base_spread * _get_spread_multiplier()
	if spread <= 0.0:
		return direction
	return direction.rotated(Vector3.UP, randf_range(-spread, spread)) \
		.rotated(Vector3.RIGHT, randf_range(-spread, spread)).normalized()


func _get_spread_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.spread_multiplier if firearm_proficiency else 1.0


func _get_recoil_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.recoil_multiplier if firearm_proficiency else 1.0


func _get_reload_multiplier() -> float:
	var firearm_proficiency: FirearmProficiency = proficiency as FirearmProficiency
	return firearm_proficiency.reload_time_multiplier if firearm_proficiency else 1.0
