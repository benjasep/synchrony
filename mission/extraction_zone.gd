class_name ExtractionZone
extends Area3D

## Zona final candidata, colocada por el mapa. [MissionDirector] elige una al azar al empezar
## la partida y la activa en todos los peers; las demás se quedan inertes. Solo detecta: los
## jugadores entran por su capa de colisión, y la zona no ocupa ninguna capa propia.

const GROUP: StringName = &"extraction_zone"

## Es una máscara: 2 = capa 2, la capa de colisión de los [Player].
const PLAYER_COLLISION_LAYER: int = 2

## Señal visual opcional; solo se ve en la zona elegida.
@export var indicator: Node3D

var is_active: bool = false


## Se registra en el grupo [code]extraction_zone[/code], que es donde la busca el director.
func _enter_tree() -> void:
	add_to_group(GROUP)


## Fuerza la detección de jugadores sin fiarse de la escena y pasa el indicador a la capa de
## cuerpos. No apaga una activación que haya llegado antes que este [code]_ready()[/code].
func _ready() -> void:
	# Capa 0: con capa propia, un rayo que acepte áreas (el del disparo, por ejemplo)
	# chocaría con la zona como si fuera una pared invisible.
	collision_layer = 0
	collision_mask = PLAYER_COLLISION_LAYER
	monitoring = true
	monitorable = false
	# En la capa 1 el vidente solo vería el contorno del indicador, como el de una pared.
	Statics.force_visual_layer(indicator, Statics.BODY_VISUAL_LAYER)
	_update_indicator()


## Activa o desactiva la zona; solo cambia si se ve el indicador. La llama el director en
## todos los peers.
## Recibe: [param active] — [code]true[/code] si es la zona final de esta partida.
func set_active(active: bool) -> void:
	is_active = active
	_update_indicator()


## Comprueba si [param body] está dentro de la zona, según el último paso de física.
## Devuelve: [code]false[/code] también si no está en el árbol o no vigila.
func contains(body: Node3D) -> bool:
	if not body or not is_inside_tree() or not monitoring:
		return false
	return overlaps_body(body)


## Muestra el indicador solo si la zona está activa.
func _update_indicator() -> void:
	if indicator:
		indicator.visible = is_active
