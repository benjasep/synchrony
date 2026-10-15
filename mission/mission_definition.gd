class_name MissionDefinition
extends Resource

## Qué pide una misión, como datos: los objetos a encontrar. El mapa solo pone marcadores
## ([ObjectiveZone], [ExtractionZone]) y [MissionDirector] sortea en el servidor dónde cae
## cada objeto.

@export var objectives: Array[MissionObjective] = []
## Cuántos objetos puede recibir como mucho cada zona antes de tener que relajar el reparto;
## 0 o menos = sin límite.
@export var max_per_zone: int = 1
