class_name ProficiencyProfile
extends Resource

## Qué tan bien un rol maneja una familia de equipamiento.
##
## Un item NUNCA consulta Statics.Role: declara su EquipmentTag y pide su perfil
## de competencia al equiparse. Los debuffs por usar el item de otro rol se
## expresan como datos aquí, no como condicionales en el código del item.
##
## Subclasea esta clase por familia de item (ver FirearmProficiency) para añadir
## los parámetros que esa familia necesite. Añadir un debuff nuevo debe costar
## un @export en la subclase + un uso en el item + tunear los .tres.

## Familia de equipamiento a la que aplica este perfil.
@export var tag: Statics.EquipmentTag = Statics.EquipmentTag.NONE

## Etiqueta legible para HUD/tooltips ("Experto", "Sin entrenamiento").
@export var display_name: String = ""

## Si es false, el jugador no puede siquiera empuñar el item.
@export var usable: bool = true

## Multiplicador del tiempo de equipado/guardado.
@export var equip_time_multiplier: float = 1.0
