class_name EnemyBelief
extends RefCounted

## Algo que un enemigo cree: de qué trata, dónde, cuán seguro está y a qué ritmo lo olvida.

enum Source {
	SIGHT,
	TOUCH,
	HEARING,
	HINT,
}

var topic: StringName = &""
var source: Source = Source.SIGHT
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var certainty: float = 1.0
var lifetime: float = 10.0
var age: float = 0.0
var updated_usec: int = 0
var subject: Node3D = null
var passage: Passage = null
var passage_side: float = 0.0
var passage_age: float = 0.0


## Envejece la creencia [param delta] segundos y gasta su certeza.
func decay(delta: float) -> void:
	age += delta
	passage_age += delta
	if lifetime <= 0.0:
		certainty = 0.0
		return
	certainty = maxf(certainty - delta / lifetime, 0.0)


## Envejece la creencia [param delta] segundos sin gastar su certeza.
func grow_older(delta: float) -> void:
	age += delta
	passage_age += delta


## Devuelve [code]true[/code] si ya no queda certeza.
func is_exhausted() -> bool:
	return certainty <= 0.0


## Sube la certeza hasta [param to_certainty]; nunca la baja.
func reinforce(to_certainty: float) -> void:
	certainty = maxf(certainty, clampf(to_certainty, 0.0, 1.0))


## Baja la certeza en [param amount].
func contradict(amount: float) -> void:
	certainty = maxf(certainty - maxf(amount, 0.0), 0.0)


## Devuelve la rapidez estimada, en m/s y en planta.
func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Devuelve hacia dónde se movía, en planta y normalizado.
func get_direction() -> Vector3:
	var flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized()


## Devuelve [code]true[/code] si tiene apuntado un hueco por el que se fue.
func has_passage() -> bool:
	return is_instance_valid(passage)


## Olvida el hueco por el que se fue.
func clear_passage() -> void:
	passage = null
	passage_side = 0.0
	passage_age = 0.0


## Devuelve el nombre de la fuente [param value].
static func get_source_name(value: Source) -> String:
	return str(Source.keys()[value])


## Devuelve un resumen legible para depurar.
func _to_string() -> String:
	return "%s %.2f %s en %s (%.1f s)" % [topic, certainty, get_source_name(source),
		position, age]
