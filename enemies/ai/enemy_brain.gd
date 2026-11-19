class_name EnemyBrain
extends Node

## Cerebro de un enemigo: corre el estado actual y toma la primera [EnemyTransition] que se cumple.

signal state_changed(previous: StringName, current: StringName)

## Si el cerebro está encendido.
@export var active: bool = true:
	set = set_active
## Nombre del estado en el que empieza.
@export var initial_state: StringName = &""
## Transiciones de la gráfica de estados.
@export var transitions: Array[EnemyTransition] = []
## Estrategia para elegir presa.
@export var target_selector: TargetSelector
## Si imprime cada cambio de estado.
@export var debug_log: bool = false

@export_group("Nodos")
@export var enemy: Enemy
@export var senses: EnemySenses
@export var memory: EnemyMemory
@export var locomotion: EnemyLocomotion
@export var combat: EnemyCombat

var current_state: EnemyState = null

var _states: Dictionary[StringName, EnemyState] = {}
var _transitions: Array[EnemyTransition] = []


## Registra sus estados hijos y copia la gráfica.
func _ready() -> void:
	for child: Node in get_children():
		var state: EnemyState = child as EnemyState
		if state:
			state.brain = self
			_states[state.name] = state
	if initial_state != &"" and not _states.has(initial_state):
		push_warning("EnemyBrain de %s: no hay estado inicial %s" % [_owner_name(), initial_state])
	add_transitions(transitions)


## Toma la primera transición aplicable y avanza el estado actual, en el servidor.
func _physics_process(delta: float) -> void:
	if not active or not _is_server() or _states.is_empty():
		return
	if not current_state:
		change_state(initial_state)
		if not current_state:
			return
	var transition: EnemyTransition = pick_transition()
	if transition:
		if memory and transition.memory_event != &"":
			memory.bump(transition.memory_event)
		change_state(transition.to)
	current_state.time_in_state += delta
	current_state.tick(delta)


## Enciende o apaga el cerebro.
func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active and is_node_ready():
		change_state(&"")
		if locomotion:
			locomotion.stop()


## Añade transiciones a la gráfica en caliente, ordenadas por prioridad.
func add_transitions(extra: Array[EnemyTransition]) -> void:
	for transition: EnemyTransition in extra:
		if not transition or _transitions.has(transition):
			continue
		if is_node_ready() and not _states.has(transition.to):
			push_warning("EnemyBrain de %s: la transición %s va a un estado que no existe"
				% [_owner_name(), transition.describe()])
		_insert_sorted(transition)


## Devuelve una copia de la gráfica en uso, en orden de evaluación.
func get_transitions() -> Array[EnemyTransition]:
	return _transitions.duplicate()


## Devuelve la primera transición de [param from] a [param to], o [code]null[/code].
func find_transition(from: StringName, to: StringName) -> EnemyTransition:
	for transition: EnemyTransition in _transitions:
		if transition.from == from and transition.to == to:
			return transition
	return null


## Devuelve la transición que tomaría ahora desde el estado actual, o [code]null[/code].
func pick_transition() -> EnemyTransition:
	if not current_state:
		return null
	var current: StringName = current_state.name
	for transition: EnemyTransition in _transitions:
		if transition.to == current or not transition.applies_from(current):
			continue
		if not _states.has(transition.to):
			continue
		if not transition.condition or transition.condition.is_met(self):
			return transition
	return null


## Sale del estado actual, entra en [param state_name] y emite [code]state_changed[/code].
func change_state(state_name: StringName) -> void:
	var previous: StringName = get_state_name()
	if current_state:
		current_state.exit()
	if locomotion:
		locomotion.release()
	current_state = _states.get(state_name, null)
	if current_state:
		current_state.reset_for_entry()
		current_state.enter()
	var current: StringName = get_state_name()
	if debug_log:
		print("[%s] %s -> %s" % [_owner_name(), previous, current])
	if previous != current or current_state:
		state_changed.emit(previous, current)


## Devuelve el nombre del estado actual.
func get_state_name() -> StringName:
	return current_state.name if current_state else &""


## Devuelve el estado hijo llamado [param state_name], o [code]null[/code].
func get_state(state_name: StringName) -> EnemyState:
	return _states.get(state_name, null)


## Devuelve los nombres de todos sus estados.
func get_state_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for state_name: StringName in _states.keys():
		names.append(state_name)
	return names


## Devuelve [code]true[/code] si es el estado inicial o alguna transición lleva a él.
func is_state_reachable(state_name: StringName) -> bool:
	if state_name == initial_state:
		return true
	for transition: EnemyTransition in _transitions:
		if transition.to == state_name:
			return true
	return false


## Devuelve los estados a los que no se puede llegar.
func get_locked_states() -> Array[StringName]:
	var locked: Array[StringName] = []
	for state_name: StringName in _states.keys():
		if not is_state_reachable(state_name):
			locked.append(state_name)
	return locked


## Elige presa entre [param candidates].
func choose_target(candidates: Array[Player]) -> Player:
	if target_selector:
		return target_selector.choose(self, candidates)
	for candidate: Player in candidates:
		if TargetSelector.is_valid_prey(candidate):
			return candidate
	return null


## Inserta [param transition] detrás de todas las de prioridad mayor o igual.
func _insert_sorted(transition: EnemyTransition) -> void:
	var index: int = _transitions.size()
	for i: int in _transitions.size():
		if _transitions[i].priority < transition.priority:
			index = i
			break
	_transitions.insert(index, transition)


## Devuelve el nombre del enemigo para los avisos.
func _owner_name() -> String:
	return str(enemy.name) if enemy else str(name)


## Devuelve [code]true[/code] en el servidor o sin peer.
func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
