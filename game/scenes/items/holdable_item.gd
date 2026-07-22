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

const LAYER_WORLD := 1
const LAYER_HOLDABLE := 4
## How long we spread motion between two remote snapshots (smooths packet jitter).
const NET_INTERP_WINDOW_SEC := 0.05
## Beyond this, snap instead of interpolating (teleports / corrections).
const NET_SNAP_DIST := 3.0

var is_held: bool = false
var holder_peer_id: int = 0
var _holder: Node = null
var _default_gravity_scale: float = 2.4
var _network_ready: bool = false

# Remote puppet: interpolate between authoritative snapshots from the simulating peer.
var _net_has_pose: bool = false
var _net_from_pos: Vector3 = Vector3.ZERO
var _net_from_rot: Vector3 = Vector3.ZERO
var _net_to_pos: Vector3 = Vector3.ZERO
var _net_to_rot: Vector3 = Vector3.ZERO
var _net_to_vel: Vector3 = Vector3.ZERO
var _net_interp_t: float = 0.0
var _net_interp_dur: float = NET_INTERP_WINDOW_SEC
var _net_last_pose_msec: int = 0

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
	set_physics_process(true)

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
	if is_local_sim_authority():
		freeze = false
	else:
		_set_as_puppet(Vector3.ZERO)
	_network_ready = true

func is_local_sim_authority() -> bool:
	## Free items: host. Held items: the holding peer. Offline: always local.
	if not multiplayer.has_multiplayer_peer():
		return true
	if is_held:
		return holder_peer_id == multiplayer.get_unique_id()
	return multiplayer.is_server()

func _physics_process(delta: float) -> void:
	if is_local_sim_authority():
		return
	if not _net_has_pose:
		return
	_net_interp_t += delta
	var alpha := 1.0
	if _net_interp_dur > 0.0001:
		alpha = clampf(_net_interp_t / _net_interp_dur, 0.0, 1.0)
	var pos := _net_from_pos.lerp(_net_to_pos, alpha)
	var rot := Vector3(
		lerp_angle(_net_from_rot.x, _net_to_rot.x, alpha),
		lerp_angle(_net_from_rot.y, _net_to_rot.y, alpha),
		lerp_angle(_net_from_rot.z, _net_to_rot.z, alpha)
	)
	var vel := _net_to_vel
	if alpha >= 1.0:
		var over := _net_interp_t - _net_interp_dur
		pos = _net_to_pos + _net_to_vel * over
	else:
		# Approximate segment velocity so kinematic contacts still resolve.
		vel = (_net_to_pos - _net_from_pos) / maxf(_net_interp_dur, 0.001)
	_set_as_puppet(vel)
	_teleport_visual(pos, rot, vel)

func apply_network_pose(pos: Vector3, rot: Vector3, held: bool, peer_id: int, vel: Vector3 = Vector3.ZERO) -> void:
	## Puppet update from the peer that is currently simulating this item.
	if is_local_sim_authority():
		return
	var was_held := is_held
	is_held = held
	holder_peer_id = peer_id if held else 0
	gravity_scale = 0.0 if held else _default_gravity_scale
	if mesh_instance and outline_material and was_held != held:
		mesh_instance.material_overlay = outline_material if held else null

	# Host snaps to remote holder as a kinematic body so free items get pushed.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var push_vel := vel
		if push_vel.length_squared() < 0.0001:
			var dt := maxf(get_physics_process_delta_time(), 0.001)
			push_vel = (pos - global_position) / dt
		_set_as_puppet(push_vel)
		_teleport_visual(pos, rot, push_vel)
		_net_has_pose = false
		return

	var dist := global_position.distance_to(pos)
	if not _net_has_pose or dist > NET_SNAP_DIST or (not was_held and held) or (was_held and not held):
		_set_as_puppet(vel)
		_teleport_visual(pos, rot, vel)
		_net_from_pos = pos
		_net_from_rot = rot
		_net_to_pos = pos
		_net_to_rot = rot
		_net_to_vel = vel
		_net_interp_t = _net_interp_dur
		_net_last_pose_msec = Time.get_ticks_msec()
		_net_has_pose = true
		return

	var now := Time.get_ticks_msec()
	var dt_sec := NET_INTERP_WINDOW_SEC
	if _net_last_pose_msec > 0:
		dt_sec = clampf(float(now - _net_last_pose_msec) / 1000.0, 1.0 / 60.0, 0.12)
	_net_last_pose_msec = now
	_net_from_pos = global_position
	_net_from_rot = rotation
	_net_to_pos = pos
	_net_to_rot = rot
	_net_to_vel = vel
	_net_interp_t = 0.0
	_net_interp_dur = dt_sec
	_net_has_pose = true

func _set_as_puppet(vel: Vector3) -> void:
	## Kinematic freeze still pushes dynamic rigid bodies when moved via code.
	freeze = true
	freeze_mode = FREEZE_MODE_KINEMATIC
	linear_velocity = vel
	angular_velocity = Vector3.ZERO

func _teleport_visual(pos: Vector3, rot: Vector3, vel: Vector3 = Vector3.ZERO) -> void:
	_set_as_puppet(vel)
	var xf := Transform3D(Basis.from_euler(rot), pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	global_transform = xf

func _apply_world_collision() -> void:
	collision_layer = LAYER_HOLDABLE
	collision_mask = LAYER_WORLD | LAYER_HOLDABLE

func _apply_holder_collision_mask(held: bool, simulate: bool) -> void:
	## Client holders skip local holdable-holdable contacts — free items are frozen
	## puppets there. The host kinematic copy of the held item pushes them instead.
	if held and simulate and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		collision_mask = LAYER_WORLD
	else:
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
	_net_has_pose = false
	_apply_held_physics(held, release_velocity)

func _apply_held_physics(held: bool, release_velocity: Vector3) -> void:
	_apply_world_collision()
	if held:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		gravity_scale = 0.0
	else:
		gravity_scale = _default_gravity_scale
	var simulate := is_local_sim_authority()
	_apply_holder_collision_mask(held, simulate)
	if simulate:
		freeze = false
		if not held:
			linear_velocity = release_velocity
			angular_velocity = Vector3.ZERO
	else:
		_set_as_puppet(Vector3.ZERO)
	if mesh_instance and outline_material:
		mesh_instance.material_overlay = outline_material if held else null

func drive_toward(target: Vector3, follow_speed: float, _delta: float) -> void:
	if not is_held:
		return
	if multiplayer.has_multiplayer_peer() and holder_peer_id != multiplayer.get_unique_id():
		return
	freeze = false
	var to_target := target - global_position
	linear_velocity = to_target * follow_speed
	angular_velocity = Vector3.ZERO
	var max_speed := follow_speed * 1.4
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
