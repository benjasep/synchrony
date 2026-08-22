class_name RoleProfile
extends Resource

## Todo lo que distingue a un rol de otro, como datos.
##
## Es el único punto de variación entre roles: Player es una clase concreta sin
## subclases. Añadir un rol es crear un .tres y registrarlo en RoleDatabase; no
## debería requerir tocar código.

@export var role: Statics.Role = Statics.Role.NONE
@export var display_name: String = ""
@export var icon: Texture2D

@export_group("Movimiento")
@export var move_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 4.5

@export_group("Salud")
@export var max_health: float = 100.0

@export_group("Percepción")
@export var vision_mode: VisionMode

@export_group("Equipamiento")
## Items con los que aparece. Son objetos normales: se pueden soltar y recoger.
@export var starting_equipment: Array[PackedScene] = []
## Excepciones de competencia. Lo no declarado cae a ProficiencyDatabase.
@export var proficiencies: Array[ProficiencyProfile] = []

@export_group("Escenas")
## Habilidad innata. A diferencia del equipamiento, NO es transferible.
@export var ability_scene: PackedScene
@export var hud_scene: PackedScene


## Competencia de este rol con una familia de items. Nunca devuelve null salvo
## que la base de datos esté mal configurada.
func get_proficiency(tag: Statics.EquipmentTag) -> ProficiencyProfile:
	for profile: ProficiencyProfile in proficiencies:
		if profile and profile.tag == tag:
			return profile
	return ProficiencyDatabase.get_default(tag)
