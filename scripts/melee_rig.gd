class_name MeleeRig
extends Node3D

## Anatomía del golpe de un modelo: vive en su envoltorio, junto al [AnimationTree], y no sabe
## nada de reglas ni de red. Lanza el estado del golpe en la máquina de estados, emite cada
## evento de [code]events[/code] al cruzar su tiempo y dice hacia dónde golpea el modelo. Las
## reglas (objetivo, daño, encararse) las pone [MeleeAttack] en la entidad, que lo recibe
## cableado por [Enemy]; cada peer reproduce la animación en local.
##
## La línea del golpe pasa por el origen de este nodo en la dirección [code]forward[/code]:
## colócalo sobre la línea central del modelo, que no tiene por qué pasar por el origen de la
## entidad. [MeleeAttack] gira al enemigo hasta dejar al objetivo sobre esa línea.
##
## No toca el [FootPlacement], a diferencia de [GrabRig]: en suelo plano no cambia nada aunque
## una mano esté en el aire, porque mide el suelo bajo la proyección de cada contacto sobre el
## plano del esqueleto y no bajo el contacto animado, y con desnivel cero no mueve ningún hueso
## (lo comprueba [code]tests/verify_attacks.gd[/code]). En un desnivel sí subiría o bajaría la
## mano que golpea lo que suba o baje el suelo bajo ella; se acepta: es cosmético, nadie sujeta
## nada con ella y deja las otras patas apoyadas.

## Se emite al cruzar cada evento de la tabla, en el orden de la animación.
signal event_reached(event: StringName)
## Se emite al salir del estado del golpe por sí solo: al acabar el clip o si otra transición
## de la máquina lo desplaza (un agarre). No al cortarlo con [code]stop()[/code].
signal finished

@export var tree: AnimationTree
## Ruta de los parámetros de la máquina de estados que tiene la locomoción y el golpe:
## [code]parameters[/code] si es la raíz del árbol; [code]parameters/<nodo>[/code] si es un nodo
## de un [AnimationNodeBlendTree] raíz.
@export var state_machine_path: StringName = &"parameters"
## Dirección hacia la que golpea el modelo, en el espacio de este nodo. La pesadilla se modeló
## mirando a -X.
@export var forward: Vector3 = Vector3.LEFT

@export_group("Estados")
@export var locomotion_state: StringName = &"locomotion"
## Estado del golpe en la máquina: un clip que empieza y acaba en la pose de reposo.
@export var attack_state: StringName = &"ataque"

@export_group("Eventos")
## Eventos del golpe; su [code]animation[/code] es [code]attack_state[/code].
@export var events: Array[AnimationEventMarker] = []

var _running: bool = false
var _entered: bool = false
var _last_position: float = -1.0


## Se engancha al árbol: los eventos se leen justo después de que aplique la pose del frame.
func _ready() -> void:
	if tree:
		tree.mixer_applied.connect(_on_mixer_applied)


## Devuelve [code]true[/code] si el árbol trae la máquina de estados de
## [code]state_machine_path[/code].
func is_valid() -> bool:
	return tree != null and _get_playback() != null


## Devuelve [code]true[/code] desde [code]play()[/code] hasta salir del golpe o
## [code]stop()[/code].
func is_running() -> bool:
	return _running


## Devuelve [code]attack_state[/code] mientras suena el golpe o, fuera de él,
## [code]locomotion_state[/code]. Justo después de [code]play()[/code], hasta que el árbol
## procesa, sigue devolviendo [code]locomotion_state[/code].
func get_current_state() -> StringName:
	if not _running or not _entered:
		return locomotion_state
	return attack_state


## Devuelve los segundos que lleva sonando el golpe, o [code]0[/code] fuera de él.
func get_play_position() -> float:
	if not _running or not _entered:
		return 0.0
	return _get_playback().get_current_play_position()


## Devuelve el tiempo de [param event] en la tabla, o [code]-1[/code] si no está.
func get_event_time(event: StringName) -> float:
	return AnimationEventMarker.find_time(events, attack_state, event)


## Devuelve la dirección global hacia la que golpea el modelo ([code]forward[/code] girado con
## este nodo), normalizada.
func get_forward() -> Vector3:
	return (global_basis * forward).normalized()


## Lanza el golpe desde el principio, aunque ya estuviera sonando. Desde otro estado viaja con
## el fundido de la transición; si ya suena, lo reinicia en seco ([code]travel()[/code] a sí
## mismo no haría nada). Quien llama ya ha encarado el modelo.
func play() -> void:
	if not is_valid():
		return
	_running = true
	_entered = false
	_last_position = -1.0
	var playback: AnimationNodeStateMachinePlayback = _get_playback()
	if playback.get_current_node() == attack_state:
		playback.start(attack_state)
	else:
		playback.travel(attack_state)


## Corta el golpe en seco: vuelve a la locomoción sin fundido ni más eventos. No emite
## [code]finished[/code]. Pensado para cuando el enemigo se retira.
func stop() -> void:
	if not _running:
		return
	_running = false
	_entered = false
	_get_playback().start(locomotion_state)


## Con el golpe en marcha, cada vez que el árbol aplica la pose: dispara los eventos cruzados
## desde el frame anterior y detecta la salida del estado.
func _on_mixer_applied() -> void:
	if not _running:
		return
	var playback: AnimationNodeStateMachinePlayback = _get_playback()
	var state: StringName = playback.get_current_node()
	if not _entered:
		# travel() no se aplica hasta que el árbol procesa: hasta entonces la
		# máquina sigue en la locomoción y eso no es el final de nada.
		_entered = state == attack_state
		if not _entered:
			return
	if state != attack_state:
		_running = false
		_entered = false
		if state == locomotion_state:
			# Volvió solo, así que el clip acabó: lo que le faltara entre el último
			# frame y el final ya pasó.
			_emit_between(_last_position, INF)
		finished.emit()
		return
	var position: float = playback.get_current_play_position()
	_emit_between(_last_position, position)
	_last_position = position


## Emite, en orden de tiempo, los eventos del golpe con tiempo en ([param from], [param to]].
func _emit_between(from: float, to: float) -> void:
	for event: StringName in AnimationEventMarker.get_events_between(events, attack_state, from, to):
		event_reached.emit(event)


## Devuelve la reproducción de la máquina de estados del golpe, o [code]null[/code].
func _get_playback() -> AnimationNodeStateMachinePlayback:
	return tree.get(StringName("%s/playback" % state_machine_path)) as AnimationNodeStateMachinePlayback
