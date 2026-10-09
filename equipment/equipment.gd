class_name Equipment
extends Node3D

## Objeto que un jugador empuña, suelta y recoge (linterna, arma). No es una feature de rol:
## si muere su dueño otro lo recoge y el nivel no se bloquea. Nunca consulta
## [code]Statics.Role[/code]; declara su [code]tag[/code] y lee todo parámetro de manejo de su
## [ProficiencyProfile], no de constantes.

signal equipped(player: Player)
signal unequipped(player: Player)
signal used

@export var tag: Statics.EquipmentTag = Statics.EquipmentTag.NONE
@export var display_name: String = ""
@export var icon: Texture2D
@export var model: Node3D

var wielder: Player = null
var proficiency: ProficiencyProfile = null


## Comprueba si el rol de [param player] puede empuñar este item según su competencia.
## Devuelve: [code]false[/code] si no hay jugador, perfil o competencia, o si esta no es
## [code]usable[/code].
func can_be_equipped_by(player: Player) -> bool:
	if not player or not player.profile:
		return false
	var candidate: ProficiencyProfile = player.profile.get_proficiency(tag)
	return candidate != null and candidate.usable


## Empuña el item: cachea la competencia del portador (único cruce item × rol, así no hay
## lookups por frame), muestra el modelo, lo pasa a la capa de viewmodel, llama a
## [code]_on_equipped()[/code] y emite [code]equipped[/code].
## Recibe: [param player] — quien lo empuña.
## Devuelve: [code]false[/code], sin efectos, si [param player] no puede equiparlo.
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


## Deja de empuñar el item: llama a [code]_on_unequipped()[/code], oculta el modelo, olvida
## portador y competencia y emite [code]unequipped[/code] con el portador anterior. No hace
## nada si no estaba empuñado.
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


## Oculta el modelo sin desequipar el item; el inventario lo llama al añadirlo.
func stow() -> void:
	if model:
		model.hide()


## Devuelve [code]true[/code] si alguien empuña el item.
func is_equipped() -> bool:
	return wielder != null


## Indica si el rol del portador declara una competencia propia para este [code]tag[/code]
## en vez de caer al default "sin entrenamiento". Pensado para HUD y feedback.
## Devuelve: [code]false[/code] también si no hay portador.
func is_wielder_proficient() -> bool:
	if not wielder or not wielder.profile:
		return false
	for profile: ProficiencyProfile in wielder.profile.proficiencies:
		if profile and profile.tag == tag:
			return true
	return false


## Estado que debe sobrevivir a soltar y recoger el item (munición, batería). Las subclases
## con estado lo sobrescriben junto con [code]set_state()[/code].
## Devuelve: un diccionario serializable; vacío en la base.
func get_state() -> Dictionary:
	return {}


## Restaura el estado guardado con [code]get_state()[/code]; en la base no hace nada. Se llama
## después de entrar al árbol, porque el [code]_ready()[/code] del item lo reinicializa.
## Recibe: [param _state] — el diccionario que devolvió [code]get_state()[/code].
func set_state(_state: Dictionary) -> void:
	pass


## Acción principal (clic izquierdo). La base solo emite [code]used[/code]; las subclases la
## sobrescriben.
func use() -> void:
	used.emit()


## Acción secundaria (clic derecho). No hace nada en la base.
func alt_use() -> void:
	pass


## Gancho para subclases, llamado por [code]equip()[/code] con portador y competencia ya
## asignados y antes de emitir [code]equipped[/code].
func _on_equipped() -> void:
	pass


## Gancho para subclases, llamado por [code]unequip()[/code] cuando el portador aún está
## asignado, para poder quitarle los modificadores que le aplicó el item.
func _on_unequipped() -> void:
	pass
