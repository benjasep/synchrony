class_name Flashlight
extends Equipment

## Linterna del técnico.
##
## Caso especial y el único item que cruza la frontera cliente/mundo: la luz
## ILUMINA PARA TODOS, así que su estado es estado del mundo y debe replicarse.
## Compáralo con la percepción del vidente, que es puramente local.
##
## En manos ajenas parpadea y rinde menos, según su LightProficiency.

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


func _ready() -> void:
	battery = max_battery
	_apply_light_settings()
	if light:
		light.visible = false


func get_state() -> Dictionary:
	return {"battery": battery, "is_on": is_on}


func set_state(state: Dictionary) -> void:
	battery = state.get("battery", max_battery)
	is_on = state.get("is_on", false)
	if light:
		light.visible = is_on
	battery_changed.emit(battery / max_battery)


func _on_equipped() -> void:
	_apply_light_settings()


func _on_unequipped() -> void:
	_flicker_left = 0.0


func use() -> void:
	if not is_equipped():
		return
	set_light_state.rpc(not is_on)
	used.emit()


## Replicado: la luz es visible para todos los peers.
@rpc("any_peer", "call_local", "reliable")
func set_light_state(value: bool) -> void:
	if value and battery <= 0.0:
		return
	is_on = value
	if light:
		light.visible = is_on
	toggled.emit(is_on)


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


## El parpadeo es cosmético y local: no vale la pena replicarlo por red.
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


func _apply_light_settings() -> void:
	if not light:
		return
	light.spot_range = base_range * _get_range_multiplier()
	light.light_energy = base_energy * _get_energy_multiplier()


func _get_light_proficiency() -> LightProficiency:
	return proficiency as LightProficiency


func _get_range_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.range_multiplier if light_proficiency else 1.0


func _get_energy_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.energy_multiplier if light_proficiency else 1.0


func _get_flicker_chance() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.flicker_chance if light_proficiency else 0.0


func _get_drain_multiplier() -> float:
	var light_proficiency: LightProficiency = _get_light_proficiency()
	return light_proficiency.drain_multiplier if light_proficiency else 1.0
