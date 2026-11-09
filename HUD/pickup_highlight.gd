class_name PickupHighlightHUD
extends HBoxContainer

const WORLD_COLLISION_MASK: int = 1

@onready var icon: TextureRect = $Icon

var _player: Player


func _ready() -> void:
	hide()
	set_physics_process(false)


func setup(player: Player) -> void:
	_player = player
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var interaction: InteractionComponent = _player.interaction
	var target: Interactable = interaction.current_target
	if not is_instance_valid(target) or not (target is EquipmentPickup):
		hide()
		return

	var pickup: EquipmentPickup = target as EquipmentPickup
	var camera: Camera3D = _player.camera
	var anchor: Vector3 = pickup.global_position + Vector3.UP * 0.3
	if not pickup.can_interact(_player) or camera.is_position_behind(anchor):
		hide()
		return

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera.global_position, interaction.ray.get_collision_point(), WORLD_COLLISION_MASK
	)
	if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		hide()
		return

	icon.texture = pickup.get_pickup_icon()
	position = camera.unproject_position(anchor) - Vector2(size.x * 0.5, size.y)
	show()
