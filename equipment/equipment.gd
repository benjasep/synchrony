class_name Equipment
extends Node3D

## Objeto que un jugador puede empuñar. La linterna y el arma son Equipment, NO
## features de rol: eso permite que se caigan al morir, se presten y se recojan,
## y evita que la muerte del técnico bloquee el nivel.
##
## Un Equipment NUNCA menciona Statics.Role. Declara su familia (tag) y, al
## equiparse, resuelve UNA sola vez su ProficiencyProfile contra el portador.
## Los debuffs por usar el item de otro rol salen de ahí, como datos.
##
## Todos los parámetros de manejo deben leerse del proficiency, no ser
## constantes: así añadir un debuff nuevo es un @export, no un refactor.

signal equipped(player: Player)
signal unequipped(player: Player)
signal used

@export var tag: Statics.EquipmentTag = Statics.EquipmentTag.NONE
@export var display_name: String = ""
@export var icon: Texture2D
## Nodo visual que se oculta cuando el item está guardado.
@export var model: Node3D

var wielder: Player = null
var proficiency: ProficiencyProfile = null


func can_be_equipped_by(player: Player) -> bool:
	if not player or not player.profile:
		return false
	var candidate: ProficiencyProfile = player.profile.get_proficiency(tag)
	return candidate != null and candidate.usable


## Único punto donde se cruza item × rol. Se cachea: no hay lookups por frame.
func equip(player: Player) -> bool:
	if not can_be_equipped_by(player):
		return false
	wielder = player
	proficiency = player.profile.get_proficiency(tag)
	if model:
		model.show()
	# En la mano de alguien el item deja de ser geometría del mundo y pasa a ser
	# viewmodel (capa 3). El vidente compone esa capa por encima de su eco; en la
	# capa 1 se lo tragaría el post-proceso y empuñaría un item invisible.
	Statics.force_visual_layer(self, Statics.VIEWMODEL_VISUAL_LAYER)
	_on_equipped()
	equipped.emit(player)
	return true


func unequip() -> void:
	if not wielder:
		return
	var previous: Player = wielder
	_on_unequipped()
	if model:
		model.hide()
	wielder = null
	proficiency = null
	unequipped.emit(previous)


## Guarda el item sin desequiparlo lógicamente (recién añadido al inventario).
func stow() -> void:
	if model:
		model.hide()


func is_equipped() -> bool:
	return wielder != null


## True si el portador maneja este item con soltura. Para HUD y feedback.
func is_wielder_proficient() -> bool:
	if not wielder or not wielder.profile:
		return false
	for profile: ProficiencyProfile in wielder.profile.proficiencies:
		if profile and profile.tag == tag:
			return true
	return false


## Estado que debe sobrevivir a soltar y recoger el item (munición, batería).
## Al morir el militar, su arma cae con las balas que le quedaban.
func get_state() -> Dictionary:
	return {}


func set_state(_state: Dictionary) -> void:
	pass


## Puntos de extensión.
func use() -> void:
	used.emit()


func alt_use() -> void:
	pass


func _on_equipped() -> void:
	pass


func _on_unequipped() -> void:
	pass
