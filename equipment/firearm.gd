class_name Firearm
extends Equipment

## Arma de fuego, efectiva contra enemigos físicos y etéreos. No hay un solo if sobre el rol:
## el temblor en manos inexpertas es un [ViewModifier] construido desde la
## [FirearmProficiency] del portador. El cliente da el feedback al instante, pero el disparo
## lo resuelve el servidor: si cada cliente calculase el daño, se desincronizarían.

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


## Empieza con el cargador lleno.
func _ready() -> void:
	in_magazine = magazine_size


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


## Aplica al portador el temblor de vista que dicta su competencia.
func _on_equipped() -> void:
	_apply_proficiency_modifiers()


## Quita el temblor de vista del portador y baja la marca de recarga. Ojo: el temporizador de
## una recarga ya empezada no se cancela y, al vencer, carga igualmente.
func _on_unequipped() -> void:
	if wielder and wielder.view:
		wielder.view.remove_modifier(SWAY_SOURCE)
	_is_reloading = false


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

	_request_fire.rpc_id(1, origin, direction)


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


## Solo el servidor resuelve el disparo: valida que el emisor sea el portador y difunde los
## efectos a todos los peers; el impacto aún no se calcula. [code]call_local[/code] es
## obligatorio: el host se lo envía a sí mismo y sin él Godot rechaza la llamada.
## Recibe: [param origin] — origen del rayo; [param direction] — dirección ya con dispersión.
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


## Efectos del disparo visibles para todos los peers, difundidos por el servidor. Aún vacío.
## Recibe: [param _origin] — origen del disparo; [param _direction] — su dirección.
@rpc("authority", "call_local", "reliable")
func _play_fire_effects(_origin: Vector3, _direction: Vector3) -> void:
	# TODO: sonido y partículas visibles para todos los peers.
	pass


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
