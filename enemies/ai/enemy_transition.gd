class_name EnemyTransition
extends Resource

## Una flecha de la gráfica del [EnemyBrain]: de qué estado sale, a cuál va y cuándo.

## Estado de origen; vacío, cualquiera.
@export var from: StringName = &""
## Estado de destino.
@export var to: StringName = &""
## Condición para tomarla; sin ella se toma siempre.
@export var condition: EnemyCondition
## Prioridad: se evalúan de mayor a menor.
@export var priority: int = 0
## Contador de [EnemyMemory] que suma uno al tomarla; vacío, ninguno.
@export var memory_event: StringName = &""


## Devuelve [code]true[/code] si puede salir de [param state_name].
func applies_from(state_name: StringName) -> bool:
	return from == &"" or from == state_name


## Devuelve una descripción corta para depurar.
func describe() -> String:
	return "%s -> %s (%d)" % [from if from != &"" else &"*", to, priority]
