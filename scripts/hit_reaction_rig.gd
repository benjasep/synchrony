class_name HitReactionRig
extends Node

## Anatomía de las reacciones al daño de un modelo: vive en su envoltorio y no sabe nada de
## reglas ni de red. Suma un respingo corto y aditivo, elegido por nombre, encima de lo que esté
## sonando (locomoción, golpe). Cuándo y cuál lo decide [HitReaction] en la entidad, que lo
## recibe cableado por [Enemy]; cada peer reproduce la animación en local.
##
## En el árbol, cada reacción es una entrada con su nombre en cada una de las
## [AnimationNodeTransition] de [code]transitions[/code], que son el [i]shot[/i] de los
## [AnimationNodeOneShot] de [code]one_shots[/code]: en modo ADD y encadenados, todos nodos del
## [AnimationNodeBlendTree] raíz. Las reacciones se alternan entre ellos. Con uno solo, un segundo
## FIRE con el OneShot activo reinicia el clip en el acto y a peso completo (Godot 4.7 no repite
## el fundido de entrada si ya estaba activo), y como el clip empieza en la pose de reposo, el
## respingo en curso cae a cero de un frame a otro. Alternando, el nuevo entra con su fundido
## mientras el anterior se desvanece desde donde estaba. Los OneShot llevan
## [code]break_loop_at_end[/code] para acabar aunque el clip venga marcado como bucle.
##
## Añadir una reacción es solo de datos: el clip aditivo en el modelo y, en el árbol, una entrada
## con su nombre en CADA transición, cada una con su [AnimationNodeAnimation] (no se pueden
## compartir: cada uno lleva su propio tiempo). Después, su nombre aquí (por zona) o en la
## [code]reaction[/code] de una [Hitbox].

@export var tree: AnimationTree

@export_group("Árbol")
## [AnimationNodeOneShot] en modo ADD por los que se alternan las reacciones: nombres de nodos
## del [AnimationNodeBlendTree] raíz.
@export var one_shots: Array[StringName] = [&"reaccion_a", &"reaccion_b"]
## [AnimationNodeTransition] que elige el clip de cada OneShot, en el mismo orden. Todas tienen
## que tener las mismas entradas.
@export var transitions: Array[StringName] = [&"reacciones_a", &"reacciones_b"]

@export_group("Reacciones por zona")
## Reacción a un impacto en [code]CUERPO[/code]; también la de cualquier zona sin la suya.
@export var body_reaction: StringName = &"dano_cuerpo"
## Reacción a un impacto en [code]CABEZA[/code]; vacía = la del cuerpo.
@export var head_reaction: StringName = &""
## Reacción a un impacto en [code]PUNTO_DEBIL[/code]; vacía = la del cuerpo.
@export var weak_spot_reaction: StringName = &""

## OneShot que toca disparar la próxima vez.
var _next_slot: int = 0
## OneShot que se disparó el último, o [code]-1[/code].
var _last_slot: int = -1


## Avisa si el árbol no tiene los nodos que espera o si las transiciones no tienen las mismas
## entradas: una reacción que falte en una sola sonaría una vez sí y otra no.
func _ready() -> void:
	if not tree:
		return
	if not is_valid():
		push_warning("HitReactionRig: el árbol no tiene los OneShot %s y las transiciones %s"
			% [one_shots, transitions])
		return
	var inputs: PackedStringArray = _get_input_names(0)
	for i: int in range(1, transitions.size()):
		if _get_input_names(i) != inputs:
			push_warning("HitReactionRig: %s no tiene las mismas entradas que %s"
				% [transitions[i], transitions[0]])


## Devuelve [code]true[/code] si el árbol tiene, en su [AnimationNodeBlendTree] raíz, un
## [AnimationNodeOneShot] y una [AnimationNodeTransition] por cada entrada de
## [code]one_shots[/code] y [code]transitions[/code].
func is_valid() -> bool:
	if not tree or one_shots.is_empty() or one_shots.size() != transitions.size():
		return false
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if not root:
		return false
	for i: int in one_shots.size():
		if not root.has_node(one_shots[i]) or not root.has_node(transitions[i]):
			return false
		if not (root.get_node(one_shots[i]) is AnimationNodeOneShot) \
				or not (root.get_node(transitions[i]) is AnimationNodeTransition):
			return false
	return true


## Devuelve [code]true[/code] si [param reaction] no está vacía y es una entrada de todas las
## transiciones.
func has_reaction(reaction: StringName) -> bool:
	if reaction == &"" or not is_valid():
		return false
	for i: int in transitions.size():
		if _get_transition(i).find_input(reaction) < 0:
			return false
	return true


## Devuelve la reacción de una zona: la suya si existe en el árbol; si no, la del cuerpo; vacía
## si tampoco existe.
func get_zone_reaction(zone: Statics.HitZone) -> StringName:
	var own: StringName = &""
	match zone:
		Statics.HitZone.CABEZA:
			own = head_reaction
		Statics.HitZone.PUNTO_DEBIL:
			own = weak_spot_reaction
		_:
			own = body_reaction
	if has_reaction(own):
		return own
	return body_reaction if has_reaction(body_reaction) else &""


## Devuelve la reacción a un impacto en [param hitbox]: la de la hitbox si existe en el árbol;
## si no, la de su zona; si no, la del cuerpo. Así una hitbox puede nombrar ya una reacción que
## aún no tiene clip. Vacía si no hay ninguna.
func get_reaction_for(hitbox: Hitbox) -> StringName:
	if not hitbox:
		return get_zone_reaction(Statics.HitZone.CUERPO)
	if has_reaction(hitbox.reaction):
		return hitbox.reaction
	return get_zone_reaction(hitbox.zone)


## Lanza [param reaction] desde el principio en el siguiente OneShot y desvanece los demás: si
## ya sonaba otra (o la misma), se funden sin salto.
## Devuelve: [code]false[/code], sin hacer nada, si [param reaction] no es una entrada de las
## transiciones.
func play(reaction: StringName) -> bool:
	if not has_reaction(reaction):
		return false
	var slot: int = _next_slot
	_next_slot = (slot + 1) % one_shots.size()
	_last_slot = slot
	for i: int in one_shots.size():
		if i != slot:
			tree.set(_one_shot_parameter(i, &"request"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	# Antes que el FIRE: la transición elige el clip cuando el OneShot procesa su shot.
	tree.set(_transition_parameter(slot, &"transition_request"), String(reaction))
	tree.set(_one_shot_parameter(slot, &"request"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


## Desvanece la reacción que suene, con el fundido de salida de cada OneShot.
func stop() -> void:
	if not is_valid():
		return
	for i: int in one_shots.size():
		tree.set(_one_shot_parameter(i, &"request"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Devuelve [code]true[/code] mientras suene alguna reacción, desvaneciéndose incluida. Lo
## actualiza el árbol al procesar: justo después de [code]play()[/code] aún no.
func is_playing() -> bool:
	if not is_valid():
		return false
	for i: int in one_shots.size():
		if bool(tree.get(_one_shot_parameter(i, &"active"))):
			return true
	return false


## Devuelve la reacción del último [code]play()[/code] si aún suena sin desvanecerse, o vacía.
func get_current_reaction() -> StringName:
	if _last_slot < 0 or not is_valid():
		return &""
	if not bool(tree.get(_one_shot_parameter(_last_slot, &"internal_active"))):
		return &""
	return StringName(str(tree.get(_transition_parameter(_last_slot, &"current_state"))))


## Devuelve la transición de [param slot] en el árbol.
func _get_transition(slot: int) -> AnimationNodeTransition:
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	return root.get_node(transitions[slot]) as AnimationNodeTransition


## Devuelve los nombres de las entradas de la transición de [param slot], en orden.
func _get_input_names(slot: int) -> PackedStringArray:
	var transition: AnimationNodeTransition = _get_transition(slot)
	var names: PackedStringArray = PackedStringArray()
	for i: int in transition.get_input_count():
		names.append(transition.get_input_name(i))
	return names


## Devuelve la ruta del parámetro [param parameter] del OneShot de [param slot].
func _one_shot_parameter(slot: int, parameter: StringName) -> StringName:
	return StringName("parameters/%s/%s" % [one_shots[slot], parameter])


## Devuelve la ruta del parámetro [param parameter] de la transición de [param slot].
func _transition_parameter(slot: int, parameter: StringName) -> StringName:
	return StringName("parameters/%s/%s" % [transitions[slot], parameter])
