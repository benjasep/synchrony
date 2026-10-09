class_name RoleProfile
extends Resource

## Todo lo que distingue a un rol, como datos. [Player] no tiene subclases: añadir un rol es
## crear un .tres y registrarlo en [RoleDatabase]. [code]proficiencies[/code] lista solo
## excepciones; lo no declarado cae a [ProficiencyDatabase].

@export var role: Statics.Role = Statics.Role.NONE
@export var display_name: String = ""
@export var icon: Texture2D

@export_group("Movimiento")
@export var move_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 4.5

@export_group("Cuerpo")
@export var body_scene: PackedScene
@export var eye_height: float = 1.6
@export var body_height: float = 1.8
@export var body_radius: float = 0.4

@export_group("Salud")
@export var max_health: float = 100.0

@export_group("Percepción")
@export var vision_mode: VisionMode

@export_group("Equipamiento")
@export var starting_equipment: Array[PackedScene] = []
@export var proficiencies: Array[ProficiencyProfile] = []

@export_group("Escenas")
@export var ability_scene: PackedScene
@export var hud_scene: PackedScene


## Busca la competencia de este rol con una familia de items: primero entre sus excepciones
## y, si no declara ninguna, el default de [ProficiencyDatabase].
## Recibe: [param tag] — familia del item.
## Devuelve: el perfil; [code]null[/code] solo si la base de datos está mal configurada.
func get_proficiency(tag: Statics.EquipmentTag) -> ProficiencyProfile:
	for profile: ProficiencyProfile in proficiencies:
		if profile and profile.tag == tag:
			return profile
	return ProficiencyDatabase.get_default(tag)
