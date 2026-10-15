class_name Hitbox
extends Area3D

## Volumen que recibe disparos en nombre de un [HealthComponent], marcado con la zona del
## cuerpo que representa. Es anatomía del modelo, no de la entidad: vive en el envoltorio del
## modelo (colgado de un [BoneAttachment3D] para seguir la animación) y [Enemy] le asigna su
## salud y los tipos de daño que acepta al instanciarlo. Solo es detectable: no detecta nada.

## Solo se emite en el servidor, cuando [code]receive_hit()[/code] hace daño de verdad, ya
## aplicado: con la hitbox (lo que distingue una rodilla de la otra, que comparten zona), el daño
## final y el causante. [code]HealthComponent.damaged[/code] solo lleva la zona.
signal hit_received(hitbox: Hitbox, amount: float, source: Node)

## Es una máscara: 16 = capa 5, la de hitboxes, que mira el rayo del disparo. No puede ser la 4
## de [Enemy]: esa caja de movimiento envuelve las hitboxes y se tragaría el tiro.
const HITBOX_LAYER: int = 16
## Grupo de todas las hitboxes; el modo debug de combate lo usa para pintarlas.
const GROUP: StringName = &"hitbox"

@export var zone: Statics.HitZone = Statics.HitZone.CUERPO
@export var damage_multiplier: float = 1.0
## Reacción del [HitReactionRig] del modelo a un impacto aquí; vacía, o sin clip en el árbol, =
## la de su zona.
@export var reaction: StringName = &""

## Salud que recibe el daño; la asigna [Enemy] al cablear su modelo.
var health: HealthComponent = null
## Flags de [enum Statics.DamageType] que le hacen daño; las asigna [Enemy] según
## [code]is_ethereal[/code]. Con [code]0[/code] no la daña nada.
var accepted_damage_types: int = 0


## Se registra en el grupo [constant GROUP].
func _enter_tree() -> void:
	add_to_group(GROUP)


## Fuerza la capa de hitboxes y anula la máscara de colisión, sin fiarse de la escena.
func _ready() -> void:
	collision_layer = HITBOX_LAYER
	collision_mask = 0


## Enciende o apaga la hitbox para el rayo del disparo sin sacarla del árbol. [Enemy] la apaga
## al retirarse y la enciende al volver.
## Recibe: [param active] — [code]true[/code] para que vuelva a recibir disparos.
func set_active(active: bool) -> void:
	collision_layer = HITBOX_LAYER if active else 0


## Devuelve [code]true[/code] si el rayo del disparo puede tocarla ahora.
func is_active() -> bool:
	return collision_layer == HITBOX_LAYER


## Aplica un impacto a su salud, con su zona y multiplicado por
## [code]damage_multiplier[/code], y después emite [code]hit_received[/code]. Solo actúa en el
## servidor; lo llama el disparo al resolver el rayo.
## Recibe: [param amount] — daño base del arma; [param damage_types] — flags de
## [enum Statics.DamageType] del arma; [param source] — causante del daño.
## Devuelve: [code]true[/code] si el impacto hizo daño; [code]false[/code] fuera del servidor,
## sin salud asignada o ya muerta, si el arma no daña a este tipo de enemigo o si el daño
## resultante no es positivo.
func receive_hit(amount: float, damage_types: int, source: Node = null) -> bool:
	if not multiplayer.is_server() or not health or health.is_dead:
		return false
	if (damage_types & accepted_damage_types) == 0:
		return false
	var final_amount: float = amount * damage_multiplier
	if final_amount <= 0.0:
		return false
	health.apply_damage(final_amount, source, zone)
	# Después del daño: quien escuche ve ya su efecto (la muerte y la retirada, si la hubo).
	hit_received.emit(self, final_amount, source)
	return true
