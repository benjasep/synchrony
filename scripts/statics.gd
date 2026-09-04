class_name Statics
extends Node


const MAX_CLIENTS: int = 3
const PORT: int = 5409 # Number between 1024 and 65535.
## Peer id del servidor. Autoridad de todo lo que es estado del mundo.
const SERVER_ID: int = 1

## Presupuesto de capas visuales. Son MÁSCARAS, no índices: la capa N de Godot
## vale 1 << (N - 1).
##
## Existe porque el vidente no ve el mundo como los demás: su cámara dibuja solo
## la capa 1 para llenar el depth buffer del que sale el eco, y una segunda
## pasada compone las capas 2, 3 y 4 por encima. Todo lo que tenga que verse
## "bien" para él tiene que caer fuera de la capa 1.
##
## Un .glb recién importado llega siempre en la capa 1, así que los modelos se
## reubican en código con force_visual_layer().
const WORLD_VISUAL_LAYER: int = 1      ## Capa 1: geometría del nivel.
const ETHEREAL_VISUAL_LAYER: int = 2   ## Capa 2: enemigos etéreos.
const VIEWMODEL_VISUAL_LAYER: int = 4  ## Capa 3: item empuñado.
const BODY_VISUAL_LAYER: int = 8       ## Capa 4: cuerpos de otros jugadores.


## Mueve un nodo y toda su descendencia a una capa visual.
##
## Se hace en código y no marcando "Editable Children" en el editor porque
## reexportar el modelo desde Blender reimporta la escena y deshace cualquier
## cambio hecho sobre sus nodos.
##
## Toca GeometryInstance3D y no VisualInstance3D a propósito: la capa de una
## Light3D decide a QUÉ ilumina, así que mover la de la linterna la dejaría
## alumbrando solo al viewmodel.
static func force_visual_layer(node: Node, layer: int) -> void:
	if not node:
		return
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry:
		geometry.layers = layer
	for child: Node in node.get_children():
		force_visual_layer(child, layer)


## Statics no depende de nada a propósito: RoleProfile y RoleDatabase la
## referencian, así que si ella los referenciara de vuelta habría dependencia
## cíclica. Por eso get_role_name() vive ahora en RoleDatabase.
enum Role {
	NONE,
	SEER,        ## Vidente: ciego al mundo físico, ve entidades etéreas.
	TECHNICIAN,  ## Técnico: linterna, y a futuro mapa y ganzúas.
	SOLDIER,     ## Militar: armas contra enemigos físicos y etéreos.
}


## Familia de equipamiento. Un item declara su tag; un rol declara su
## competencia por tag. Ninguno de los dos conoce al otro.
enum EquipmentTag {
	NONE,
	FIREARM,
	LIGHT_SOURCE,
	LOCKPICK,     ## Fuera de scope por ahora; el tag no cuesta nada.
	MAP,          ## Idem.
	RITUAL_TOOL,
}


## Flags, no enum secuencial: un arma puede dañar a ambos tipos a la vez.
enum DamageType {
	PHYSICAL = 1,
	ETHEREAL = 2,
}


class PlayerData:
	var id: int
	var name: String
	# Position relative to other players
	var index: int = -1
	var role: Role
	var vote: bool = false
	
	func _init(new_id: int, new_name: String, new_index: int = -1, new_role: Role = Role.NONE) -> void:
		id = new_id
		name = new_name
		index = new_index
		role = new_role
	
	func _to_string() -> String:
		return "Player: {id: %d, name: %s, index: %d, role: %d}" % [id, name, index, role]
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"index": index,
			"role": role,
			"vote": vote
		}
	
	static func from_dict(data: Dictionary) -> PlayerData:
		var player: PlayerData = PlayerData.new(data.id, data.name, data.index, data.role)
		player.vote = data.vote
		return player
	
	func update(player_data: PlayerData) -> void:
		if id != player_data.id:
			return
		name = player_data.name
		index = player_data.index
		role = player_data.role
		vote = player_data.vote
