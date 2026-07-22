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

@export_group("Network")
## Assigned by WorldNet (stable across peers when scene-ordered).
@export var item_id: int = 0
## Cached packed-scene path for inventory pickup/drop (scene_file_path can be empty on some instances).
@export var spawn_scene_path: String = ""
## Client visual follow speed toward host pose (higher = snappier, more jitter risk).
@export var net_visual_follow: float = 18.0
## Hard-snap if the puppet is this far from the extrapolated host pose.
@export var net_snap_distance: float = 2.5
## Max seconds of velocity extrapolation between pose packets.
@export var net_extrapolate_max_sec: float = 0.12

const LAYER_WORLD := 1
const LAYER_HOLDABLE := 4

var is_held: bool = false
var holder_peer_id: int = 0
var _holder: Node = null
var _default_gravity_scale: float = 2.4
var _network_ready: bool = false

# Client-only: ease toward host-authoritative poses (same view for holder and observers).
var _net_pos: Vector3 = Vector3.ZERO
var _net_rot: Vector3 = Vector3.ZERO
var _net_vel: Vector3 = Vector3.ZERO
var _net_age_sec: float = 0.0
var _has_net_pose: bool = false

func _ready() -> void:
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	add_to_group("holdable_items")
	_default_gravity_scale = free_gravity_scale
	gravity_scale = free_gravity_scale
	mass = mass_kg
	if spawn_scene_path == "" and scene_file_path != "":
		spawn_scene_path = scene_file_path
	_apply_world_collision()
	_apply_heavy_feel()
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8

func get_spawn_scene_path() -> String:
	if spawn_scene_path != "":
		return spawn_scene_path
	return scene_file_path

func set_spawn_scene_path(path: String) -> void:
	if path != "":
		spawn_scene_path = path

func setup_network() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	set_multiplayer_authority(1)
	# Clients are visual puppets driven by WorldNet pose RPCs (not MultiplayerSynchronizer —
	# runtime-created synchronizers are unreliable in Godot 4).
	if not multiplayer.is_server():
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_net_pos = global_position
		_net_rot = rotation
		_net_vel = Vector3.ZERO
		_net_age_sec = 0.0
		_has_net_pose = true
	_network_ready = true

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if not _network_ready and not _has_net_pose:
		return
	if not _has_net_pose:
		return
	_net_age_sec += delta
	_update_network_visual(delta)

func apply_network_pose(pos: Vector3, rot: Vector3, held: bool, peer_id: int, vel: Vector3 = Vector3.ZERO) -> void:
	## Host is truth for everyone (including the local holder). Clients ease toward poses.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	freeze = true
	var was_held := is_held
	is_held = held
	holder_peer_id = peer_id if held else 0
	gravity_scale = 0.0 if held else _default_gravity_scale
	if mesh_instance and outline_material and was_held != held:
		mesh_instance.material_overlay = outline_material if held else null

	_net_pos = pos
	_net_rot = rot
	# Held bodies often report velocity into walls/props while physically blocked —
	# never extrapolate that or the puppet tunnels in/out of geometry.
	_net_vel = Vector3.ZERO if held else vel
	_net_age_sec = 0.0
	if not _has_net_pose or global_position.distance_to(pos) > net_snap_distance:
		_teleport_visual(pos, rot)
	_has_net_pose = true

func _update_network_visual(delta: float) -> void:
	var target_pos := _net_pos
	var target_rot := _net_rot

	# Only extrapolate free (unheld) motion. Held items stay glued to the last host pose.
	if not is_held and _net_vel.length() >= 0.15:
		var age := minf(_net_age_sec, net_extrapolate_max_sec)
		target_pos = _net_pos + _net_vel * age

	if global_position.distance_to(target_pos) > net_snap_distance:
		_teleport_visual(target_pos, target_rot)
		return

	# Slightly snappier while held so wall contact doesn't "swim" between packets.
	var follow := net_visual_follow * 1.35 if is_held else net_visual_follow
	var t := 1.0 - exp(-follow * delta)
	_teleport_visual(
		global_position.lerp(target_pos, t),
		_lerp_euler(rotation, target_rot, t)
	)

func _lerp_euler(from: Vector3, to: Vector3, weight: float) -> Vector3:
	return Vector3(
		lerp_angle(from.x, to.x, weight),
		lerp_angle(from.y, to.y, weight),
		lerp_angle(from.z, to.z, weight)
	)

func _teleport_visual(pos: Vector3, rot: Vector3) -> void:
	var xf := Transform3D(Basis.from_euler(rot), pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

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

## Local-only hold (singleplayer / offline). Prefer set_held_network in multiplayer.
func set_held(holder: Node, held: bool, release_velocity: Vector3 = Vector3.ZERO) -> void:
	is_held = held
	_holder = holder if held else null
	holder_peer_id = 0
	_apply_held_physics(held, release_velocity)

func set_held_network(peer_id: int, held: bool, release_velocity: Vector3 = Vector3.ZERO) -> void:
	is_held = held
	holder_peer_id = peer_id if held else 0
	_holder = null
	_apply_held_physics(held, release_velocity)

func _apply_held_physics(held: bool, release_velocity: Vector3) -> void:
	_apply_world_collision()
	var on_host := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if held:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		gravity_scale = 0.0
		if on_host:
			freeze = false
		else:
			freeze = true
	else:
		gravity_scale = _default_gravity_scale
		if on_host:
			freeze = false
			linear_velocity = release_velocity
			angular_velocity = Vector3.ZERO
		else:
			freeze = true
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_net_pos = global_position
			_net_rot = rotation
			_net_vel = Vector3.ZERO
			_net_age_sec = 0.0
			_has_net_pose = true
	if mesh_instance and outline_material:
		mesh_instance.material_overlay = outline_material if held else null

func drive_toward(target: Vector3, follow_speed: float, _delta: float) -> void:
	if not is_held:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	freeze = false
	var to_target := target - global_position
	linear_velocity = to_target * follow_speed
	angular_velocity = Vector3.ZERO
	var max_speed := follow_speed * 1.4
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
