extends RigidBody3D
class_name HoldableItem

## World prop the player can push and grab with LMB (free cursor).

@export var mesh_instance: MeshInstance3D
@export var outline_material: Material = preload("res://common/shaders/outline_simple.tres")

## Layer 1 = world/props, layer 2 = player. Mask both so boxes rest on the map and get pushed.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2

var is_held: bool = false
var _holder: Node = null

func _ready() -> void:
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	add_to_group("holdable_items")
	_apply_world_collision()
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4

func _apply_world_collision() -> void:
	collision_layer = LAYER_WORLD
	# Collide with world geometry + the player body.
	collision_mask = LAYER_WORLD | LAYER_PLAYER

func set_held(holder: Node, held: bool) -> void:
	is_held = held
	_holder = holder if held else null
	freeze = held
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if held:
		collision_layer = 0
		collision_mask = 0
	else:
		_apply_world_collision()
	if mesh_instance and outline_material:
		mesh_instance.material_overlay = outline_material if held else null

func apply_release_impulse(impulse: Vector3) -> void:
	freeze = false
	_apply_world_collision()
	apply_central_impulse(impulse)
