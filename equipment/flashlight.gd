class_name Flashlight
extends Equipment

## Linterna. Es el único item cuyo estado es del mundo: la luz ilumina para todos, así que
## encenderla o apagarla es un RPC; el parpadeo, en cambio, es cosmético y local. En manos
## ajenas rinde menos y parpadea, según la [LightProficiency] del portador.

signal toggled(is_on: bool)
signal battery_changed(ratio: float)

@export var light: SpotLight3D

@export_group("Haz")
@export var base_range: float = 12.0
@export var base_energy: float = 4.0

@export_group("Batería")
@export var max_battery: float = 300.0
@export var base_drain: float = 1.0

var is_on: bool = false
var battery: float = 300.0

var _flicker_left: float = 0.0


## Llena la batería, aplica alcance y energía del haz y deja la luz apagada.
func _ready() -> void:
	battery = max_battery
	_apply_light_settings()
	if light:
		light.visible = false


## Devuelve la batería restante y si está encendida, para que sobrevivan a soltar y recoger.
func get_state() -> Dictionary:
	return {"battery": battery, "is_on": is_on}


## Restaura batería y encendido (si falta una clave: llena y apagada), ajusta la visibilidad
## de la luz y emite [code]battery_changed[/code].
## Recibe: [param state] — el diccionario que devolvió [code]get_state()[/code].
func set_state(state: Dictionary) -> void:
	battery = state.get("battery", max_battery)
	is_on = state.get("is_on", false)
	if light:
		light.visible = is_on
	battery_changed.emit(battery / max_battery)


## Recalcula alcance y energía del haz con la competencia del nuevo portador.
func _on_equipped() -> void:
	_apply_light_settings()


## Cancela el parpadeo en curso.
func _on_unequipped() -> void:
	_flicker_left = 0.0


## Si está empuñada, alterna la luz en todos los peers y emite [code]used[/code].
func use() -> void:
	if not is_equipped():
		return
	set_light_state.rpc(not is_on)
	used.emit()


## Enciende o apaga la luz y emite [code]toggled[/code]. Es un RPC a todos los peers porque
## la luz es estado del mundo. Ignora la orden de encender si no queda batería.
## Recibe: [param value] — [code]true[/code] para encender.
@rpc("any_peer", "call_local", "reliable")
func set_light_state(value: bool) -> void:
	if value and battery <= 0.0:
		return
	is_on = value
	if light:
		light.visible = is_on
	toggled.emit(is_on)


## Con la luz encendida, gasta batería según la competencia y emite
## [code]battery_changed[/code]. Al agotarse la apaga para todos por RPC (lo envían el
## servidor y cualquier peer donde esté empuñada); si queda batería, procesa el parpadeo.
## Recibe: [param delta] — segundos desde el frame anterior.
func _process(delta: float) -> void:
	if not is_on:
		return

	battery = maxf(battery - base_drain * _get_drain_multiplier() * delta, 0.0)
	battery_changed.emit(battery / max_battery)

	if battery <= 0.0:
		if multiplayer.is_server() or is_equipped():
			set_light_state.rpc(false)
		return

	_process_flicker(delta)


## Parpadeo cosmético y local, no vale la pena replicarlo: con una probabilidad por segundo
## que dicta la competencia, apaga el haz entre 0,05 y 0,15 s y después restaura su energía.
## Recibe: [param delta] — segundos desde el frame anterior.
func _process_flicker(delta: float) -> void:
	if not light:
		return
	if _flicker_left > 0.0:
		_flicker_left -= delta
		light.light_energy = 0.0 if _flicker_left > 0.0 else base_energy * _get_energy_multiplier()
		return
	var chance: float = _get_flicker_chance()
	if chance > 0.0 and randf() < chance * delta:
		_flicker_left = randf_range(0.05, 0.15)


## Aplica a la luz el alcance y la energía base escalados por la competencia del portador.
func _apply_light_settings() -> void:
	if not light:
		return
	light.spot_range = base_range * _get_range_multiplier()
	light.light_energy = base_energy * _get_energy_multiplier()


## Devuelve: la competencia cacheada como [LightProficiency], o [code]null[/code] si no hay
## portador o no es de luz.
func _get_light_proficiency() -> LightProficiency:
	return proficiency as LightProficiency


## Devuelve el multiplicador de alcance de la competencia, o 1.0 sin ella.
func _get_range_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.range_multiplier if light_proficiency else 1.0


## Devuelve el multiplicador de energía del haz de la competencia, o 1.0 sin ella.
func _get_energy_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.energy_multiplier if light_proficiency else 1.0


## Devuelve la probabilidad de parpadeo por segundo de la competencia, o 0.0 sin ella.
func _get_flicker_chance() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.flicker_chance if light_proficiency else 0.0


## Devuelve el multiplicador de consumo de batería de la competencia, o 1.0 sin ella.
func _get_drain_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.drain_multiplier if light_proficiency else 1.0
