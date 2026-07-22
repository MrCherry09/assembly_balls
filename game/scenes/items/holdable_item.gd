extends RigidBody3D
class_name HoldableItem

## World prop the player can push and grab with LMB (free cursor).
## Layer 3 (bit value 4): collides with world + other holdables, never with players.
## Camera stays on mask 1 so props never block the third-person camera.

@export var mesh_instance: MeshInstance3D
@export var outline_material: Material = preload("res://common/shaders/outline_simple.tres")
@export var mass_kg: float = 18.0
## Heavier fall than default project gravity so thrown props drop quickly.
@export var free_gravity_scale: float = 2.4

@export_group("Inventory")
@export var inventory_icon: Texture2D

const LAYER_WORLD := 1
const LAYER_HOLDABLE := 4

var is_held: bool = false
var _holder: Node = null
var _default_gravity_scale: float = 2.4

func _ready() -> void:
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	add_to_group("holdable_items")
	_default_gravity_scale = free_gravity_scale
	gravity_scale = free_gravity_scale
	mass = mass_kg
	_apply_world_collision()
	_apply_heavy_feel()
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8

func _apply_world_collision() -> void:
	collision_layer = LAYER_HOLDABLE
	collision_mask = LAYER_WORLD | LAYER_HOLDABLE

func _apply_heavy_feel() -> void:
	linear_damp = 1.6
	angular_damp = 2.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.rough = true
	mat.bounce = 0.0
	physics_material_override = mat

func set_held(holder: Node, held: bool, release_velocity: Vector3 = Vector3.ZERO) -> void:
	is_held = held
	_holder = holder if held else null
	freeze = false
	_apply_world_collision()
	if held:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		gravity_scale = 0.0
	else:
		# Keep throw momentum from the grab drag — do not zero velocity.
		linear_velocity = release_velocity
		angular_velocity = Vector3.ZERO
		gravity_scale = _default_gravity_scale
	if mesh_instance and outline_material:
		mesh_instance.material_overlay = outline_material if held else null

func drive_toward(target: Vector3, follow_speed: float, _delta: float) -> void:
	if not is_held:
		return
	var to_target := target - global_position
	linear_velocity = to_target * follow_speed
	angular_velocity = Vector3.ZERO
	var max_speed := follow_speed * 1.4
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
