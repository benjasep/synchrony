class_name GrabRig
extends Node3D

## Anatomía del agarre de un modelo: vive en su envoltorio, junto al [AnimationTree], y no sabe
## nada de reglas ni de red. Arranca y desvía la sub-máquina del agarre, mueve dos nodos que
## siguen a los huesos de la presa y emite cada evento de [code]events[/code] al cruzar su
## tiempo. Las reglas (víctima, muerte, rescate) las pone [GrabAttack] en la entidad, que lo
## recibe cableado por [Enemy]; cada peer reproduce la animación en local.

## Se emite al cruzar cada evento de la tabla, en el orden de la animación.
signal event_reached(event: StringName)
## Se emite al entrar en [code]hold_state[/code], el bucle cuya salida decide el código.
signal hold_started
## Se emite al volver a [code]locomotion_state[/code] al final de una secuencia completa; no al
## cortarla con [code]stop()[/code].
signal finished

@export var tree: AnimationTree
## Ruta de los parámetros de la máquina de estados que tiene la locomoción y el agarre:
## [code]parameters[/code] si es la raíz del árbol; [code]parameters/<nodo>[/code] si es un nodo
## de un [AnimationNodeBlendTree] raíz.
@export var state_machine_path: StringName = &"parameters"
@export var skeleton: Skeleton3D
## Se apaga al empezar y se enciende al volver a la locomoción: si no, una pata sobre un peldaño
## movería las manos que sujetan a la víctima.
@export var foot_placement: FootPlacement
## Sigue al hueso del cuerpo de la presa: donde van los pies de la víctima.
@export var body_anchor: Node3D
## Sigue al hueso de la cabeza de la presa: donde van sus ojos.
@export var head_anchor: Node3D

@export_group("Huesos")
## Hueso que no deforma con la base de un [Player]: -Z mira al modelo, +Y arriba.
@export var body_bone: StringName = &"presa_cuerpo"
@export var head_bone: StringName = &"presa_cabeza"

@export_group("Estados")
@export var locomotion_state: StringName = &"locomotion"
## Sub-máquina del agarre dentro de la máquina de [code]state_machine_path[/code].
@export var grab_state: StringName = &"agarre"
## Estado en bucle de la sub-máquina del que se sale por código.
@export var hold_state: StringName = &"mordisco"
## Salida de [code]hold_state[/code] que remata.
@export var finish_state: StringName = &"apretar_arrancar"
## Salida de [code]hold_state[/code] que suelta a la víctima viva.
@export var interrupt_state: StringName = &"interrumpido"

@export_group("Eventos")
@export var events: Array[AnimationEventMarker] = []

var _body_index: int = -1
var _head_index: int = -1
var _running: bool = false
var _entered: bool = false
var _last_state: StringName = &""
var _last_position: float = 0.0


## Busca los huesos de la presa y se engancha al árbol: los eventos y los nodos de la presa se
## actualizan justo después de que el árbol aplique la pose del frame.
func _ready() -> void:
	if skeleton:
		_body_index = skeleton.find_bone(body_bone)
		_head_index = skeleton.find_bone(head_bone)
		if _body_index < 0 or _head_index < 0:
			push_error("GrabRig: el esqueleto no tiene %s o %s" % [body_bone, head_bone])
	if tree:
		tree.mixer_applied.connect(_on_mixer_applied)


## Devuelve [code]true[/code] si el modelo trae lo necesario para agarrar: árbol, esqueleto,
## los dos nodos de la presa y sus huesos.
func is_valid() -> bool:
	return tree != null and skeleton != null and body_anchor != null and head_anchor != null \
		and _body_index >= 0 and _head_index >= 0


## Devuelve [code]true[/code] desde [code]start()[/code] hasta volver a la locomoción o
## [code]stop()[/code].
func is_running() -> bool:
	return _running


## Devuelve el estado de la sub-máquina del agarre en curso o, fuera de él,
## [code]locomotion_state[/code].
func get_current_state() -> StringName:
	if not _running or not _entered:
		return locomotion_state
	return _get_grab_playback().get_current_node()


## Devuelve el transform global que tendría el hueso del cuerpo de la presa en reposo con el
## modelo donde está ahora: donde tiene que estar la víctima al empezar.
func get_rest_body_transform() -> Transform3D:
	if not is_valid():
		return global_transform
	return skeleton.global_transform * skeleton.get_bone_global_rest(_body_index)


## Arranca la secuencia: apaga el [FootPlacement] y viaja a [code]grab_state[/code], que
## empieza por su estado inicial. Quien llama ya ha alineado el modelo con la víctima.
func start() -> void:
	if not is_valid():
		return
	_running = true
	_entered = false
	_last_state = &""
	_last_position = 0.0
	if foot_placement:
		foot_placement.enabled = false
	_get_root_playback().travel(grab_state)
	update_anchors()


## Sale de [code]hold_state[/code] hacia el remate.
func finish() -> void:
	if _running:
		_get_grab_playback().travel(finish_state)


## Sale de [code]hold_state[/code] hacia la salida que suelta a la víctima viva.
func interrupt() -> void:
	if _running:
		_get_grab_playback().travel(interrupt_state)


## Corta la secuencia en seco: vuelve a la locomoción sin fundido ni más eventos y enciende el
## [FootPlacement]. No emite [code]finished[/code]. Pensado para cuando el enemigo se retira.
func stop() -> void:
	if not _running:
		return
	_running = false
	_entered = false
	_get_root_playback().start(locomotion_state)
	if foot_placement:
		foot_placement.enabled = true


## Copia a [code]body_anchor[/code] y [code]head_anchor[/code] la pose actual de sus huesos. Se
## llama sola cada vez que el árbol aplica una pose durante la secuencia.
func update_anchors() -> void:
	if not is_valid():
		return
	body_anchor.global_transform = skeleton.global_transform \
		* skeleton.get_bone_global_pose(_body_index)
	head_anchor.global_transform = skeleton.global_transform \
		* skeleton.get_bone_global_pose(_head_index)


## Con la secuencia en marcha, cada vez que el árbol aplica la pose: mueve los nodos de la presa,
## dispara los eventos cruzados desde el frame anterior y detecta la vuelta a la locomoción.
func _on_mixer_applied() -> void:
	if not _running:
		return
	update_anchors()
	var root_state: StringName = _get_root_playback().get_current_node()
	if not _entered:
		# travel() no se aplica hasta que el árbol procesa: hasta entonces la
		# raíz sigue en locomoción y eso no es el final de nada.
		_entered = root_state == grab_state
		# Y el frame en que entra, la sub-máquina aún informa del estado y la
		# posición en que se quedó si la secuencia anterior se cortó con stop():
		# leerla dispararía sus eventos (separacion mataría a la víctima nueva
		# antes de atraparla). Desde el frame siguiente informa del de verdad, y
		# como _last_state sigue vacío se emite todo desde el principio.
		return
	if root_state != grab_state:
		_running = false
		_entered = false
		if foot_placement:
			foot_placement.enabled = true
		finished.emit()
		return
	var playback: AnimationNodeStateMachinePlayback = _get_grab_playback()
	_advance(playback.get_current_node(), playback.get_current_play_position())


## Dispara los eventos entre la posición del frame anterior y [param position]. Si el estado
## cambió, antes cierra el anterior hasta donde llegó (sus eventos pendientes, si el clip acabó
## entre dos frames) y emite [code]hold_started[/code] al entrar en [code]hold_state[/code].
## Recibe: [param state] — estado actual de la sub-máquina; [param position] — segundos dentro
## de ese estado.
func _advance(state: StringName, position: float) -> void:
	if state != _last_state:
		if _last_state != &"":
			# Lo que avanzó el árbol este frame, menos lo que ya lleva el estado
			# nuevo, es lo que le faltó al anterior: llega al final si acabó por
			# sí solo y se queda donde estaba si se le sacó con travel().
			var elapsed: float = get_process_delta_time()
			_emit_between(_last_state, _last_position, _last_position + maxf(elapsed - position, 0.0))
		_last_state = state
		_last_position = -1.0
		if state == hold_state:
			hold_started.emit()
	if position < _last_position:
		# Un bucle que dio la vuelta.
		_emit_between(state, _last_position, INF)
		_last_position = -1.0
	_emit_between(state, _last_position, position)
	_last_position = position


## Emite, en orden de tiempo, los eventos de [param state] con tiempo en
## ([param from], [param to]].
func _emit_between(state: StringName, from: float, to: float) -> void:
	for event: StringName in AnimationEventMarker.get_events_between(events, state, from, to):
		event_reached.emit(event)


## Devuelve la reproducción de la máquina de estados que tiene la locomoción y el agarre.
func _get_root_playback() -> AnimationNodeStateMachinePlayback:
	return tree.get(StringName("%s/playback" % state_machine_path)) as AnimationNodeStateMachinePlayback


## Devuelve la reproducción de la sub-máquina del agarre.
func _get_grab_playback() -> AnimationNodeStateMachinePlayback:
	return tree.get(StringName("%s/%s/playback" % [state_machine_path, grab_state])) \
		as AnimationNodeStateMachinePlayback
