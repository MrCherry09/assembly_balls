extends RigidBody3D
class_name HoldableItem

## World prop the player can push and grab with LMB (free cursor).
## Uses layer 3 so the third-person camera (mask 1) is never blocked by props.

@export var mesh_instance: MeshInstance3D
@export var outline_material: Material = preload("res://common/shaders/outline_simple.tres")
@export var mass_kg: float = 18.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_HOLDABLE := 4
## Player ItemColliderStaticBody / ItemColliderWall (physics layer 8).
const LAYER_ITEM_COLLIDER := 128

var is_held: bool = false
var _holder: Node = null
var _default_gravity_scale: float = 1.0

func _ready() -> void:
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	add_to_group("holdable_items")
	_default_gravity_scale = gravity_scale
	mass = mass_kg
	collision_priority = 0.01
	_apply_world_collision()
	_apply_heavy_feel()
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8

func _apply_world_collision() -> void:
	collision_layer = LAYER_HOLDABLE | LAYER_ITEM_COLLIDER
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_HOLDABLE | LAYER_ITEM_COLLIDER

func _apply_heavy_feel() -> void:
	linear_damp = 1.2
	angular_damp = 2.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.rough = true
	mat.bounce = 0.0
	physics_material_override = mat

func set_held(holder: Node, held: bool) -> void:
	is_held = held
	_holder = holder if held else null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	_apply_world_collision()
	gravity_scale = 0.0 if held else _default_gravity_scale
	if mesh_instance and outline_material:
		mesh_instance.material_overlay = outline_material if held else null

func drive_toward(target: Vector3, follow_speed: float, _delta: float) -> void:
	if not is_held:
		return
	var to_target := target - global_position
	linear_velocity = to_target * follow_speed
	angular_velocity = Vector3.ZERO
	var max_speed := follow_speed * 2.0
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
