class_name BeliefCertaintyCondition
extends EnemyCondition

## La certeza más alta entre sus temas de creencia está por debajo de [code]below[/code].

## Temas de creencia que mira; vacío, todos.
@export var topics: Array[StringName] = []
## Umbral de certeza, de 0 a 1.
@export_range(0.0, 1.0, 0.01) var below: float = 0.05


## Devuelve [code]true[/code] si su certeza más alta está por debajo de [code]below[/code].
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory:
		return true
	return get_highest_certainty(brain.memory) < below


## Devuelve la certeza más alta entre [code]topics[/code].
func get_highest_certainty(memory: EnemyMemory) -> float:
	var highest: float = 0.0
	if topics.is_empty():
		for belief: EnemyBelief in memory.get_beliefs():
			highest = maxf(highest, belief.certainty)
		return highest
	for topic: StringName in topics:
		highest = maxf(highest, memory.get_certainty(topic))
	return highest
