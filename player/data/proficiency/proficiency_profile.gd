class_name ProficiencyProfile
extends Resource

## Qué tan bien maneja un rol una familia de equipamiento ([code]tag[/code]). Los debuffs por
## usar el item de otro rol se expresan aquí como datos, nunca como condicionales en el item:
## se subclasea por familia (ver [FirearmProficiency]) y un debuff nuevo es un @export más.

@export var tag: Statics.EquipmentTag = Statics.EquipmentTag.NONE

@export var display_name: String = ""

@export var usable: bool = true

@export var equip_time_multiplier: float = 1.0
