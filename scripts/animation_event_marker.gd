class_name AnimationEventMarker
extends Resource

## Un evento con nombre en un instante de una animación. Los marcadores de Blender no viajan en
## el glTF, así que la tabla se escribe en el envoltorio del modelo con uno de estos por evento
## y la leen los rigs ([GrabRig], [MeleeRig]) cada frame, con las dos funciones estáticas de
## abajo.

## Estado de la máquina de estados en el que ocurre; en los envoltorios del proyecto, el mismo
## nombre que el clip.
@export var animation: StringName
@export var event: StringName
## Segundos desde el inicio de la animación.
@export var time: float = 0.0


## Devuelve los nombres de los eventos de [param markers] sobre [param state] con tiempo en
## ([param from], [param to]], en orden de tiempo. Ignora las entradas vacías de la tabla.
static func get_events_between(markers: Array[AnimationEventMarker], state: StringName,
		from: float, to: float) -> Array[StringName]:
	var due: Array[AnimationEventMarker] = []
	for marker: AnimationEventMarker in markers:
		if marker and marker.animation == state and marker.time > from and marker.time <= to:
			due.append(marker)
	due.sort_custom(func(a: AnimationEventMarker, b: AnimationEventMarker) -> bool:
		return a.time < b.time)
	var names: Array[StringName] = []
	for marker: AnimationEventMarker in due:
		names.append(marker.event)
	return names


## Devuelve el tiempo de [param event] sobre [param state] en [param markers], o [code]-1[/code]
## si no está.
static func find_time(markers: Array[AnimationEventMarker], state: StringName,
		event: StringName) -> float:
	for marker: AnimationEventMarker in markers:
		if marker and marker.animation == state and marker.event == event:
			return marker.time
	return -1.0
