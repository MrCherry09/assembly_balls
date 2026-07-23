extends Node3D
class_name CameraObject

#camera variables
@export_group("Camera variables")
@export_range(0.0, 0.5, 0.001) var look_sensitivity: float = 0.05
@export_range(5.0, 175.0, 0.01) var cam_fov: float = 90.0: get = get_cam_fov
@export var max_view_angles: Vector2 = Vector2(-89.0, 89.0) #in degrees; keep inside ±90 to avoid euler flips
const PITCH_LIMIT_DEG := 89.0

@export_group("Third person")
@export_range(1.0, 12.0, 0.1) var camera_distance: float = 3.5
@export_range(-1.0, 2.0, 0.05) var camera_height: float = 0.35
@export_range(-2.0, 2.0, 0.05) var shoulder_offset: float = 1.0
@export_range(0.05, 1.0, 0.01) var collision_margin: float = 0.2
## How quickly the camera eases in/out when a wall shortens the arm.
@export_range(1.0, 40.0, 0.1) var collision_smooth_speed: float = 16.0
@export var collision_mask: int = 1
## Optional cosmetic pivot only — orbit/collision use the CameraHolder (stable).
@export var link_to: Node3D

@export_group("Aim")
## Local Z / orbit distance while aiming.
@export var aim_camera_distance: float = 2.15
## Slightly higher pivot while aiming (reads as leaning into the shot).
@export var aim_camera_height: float = 0.42
@export_range(1.0, 30.0, 0.1) var aim_blend_speed: float = 14.0
## Multiplier on look sensitivity while aiming.
@export_range(0.2, 1.0, 0.01) var aim_look_sensitivity_scale: float = 0.72
@export var aim_action: StringName = &"play_char_aim_action"
var is_aiming: bool = false
var _default_shoulder_offset: float = 0.0
var _default_camera_distance: float = 0.0
var _default_camera_height: float = 0.0
var _current_shoulder_offset: float = 0.0
var _current_camera_distance: float = 0.0
var _current_camera_height: float = 0.0
var _stored_shoulder_offset: float = 0.0
var _stored_camera_distance: float = 0.0
var _was_aiming: bool = false
var _fov_tween: Tween
## Smoothed orbit arm length (avoids hard snaps when colliding with walls).
var _arm_length: float = 0.0
## Local Y of CameraHolder on the player (baked out when top_level).
var _holder_height: float = 0.0

@export_group("fov variables")
@export var state_fovs_map: Dictionary[String, Vector2] = {
	#fov value, duration
	"Default": Vector2(90.0, 0.2),
	"Idle": Vector2(90.0, 0.2),
	"Crouch": Vector2(90.0, 0.2),
	"Walk": Vector2(90.0, 0.2),
	"Run": Vector2(100.0, 0.2),
	"Slide": Vector2(100.0, 0.2),
	"Dash": Vector2(120.0, 0.05),
	"Fly": Vector2(100.0, 0.2),
}

@export var clamp_fov: bool = false
@export var clamp_fov_values: Vector2 = Vector2(10.0, 170)

func get_state_fovs(state_name: String) -> Vector2:
	var fallback_value := Vector2(90, 0.2)
	return state_fovs_map.get(state_name, fallback_value)

@export_group("Zoom variables")
var zoom_on: bool = false
var zoom_has_occured: bool = false
@export_range(-180.0, 180.0, 1.0) var zoom_val: float = 40.0
@export_range(0.0, 3.0, 0.01) var zoom_duration: float = 0.2

@export_group("Mouse variables")
var _orbiting: bool = false
## Absolute look angles — never use rotate_x for pitch or eulers can flip past vertical.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Viewport-space cursor (must pair with Viewport.warp_mouse — not Input/DisplayServer).
var _stored_cursor_vp: Vector2 = Vector2.ZERO
var _has_stored_cursor: bool = false
var _mouse_captured: bool = false

@export_group("Keybind variables")
@export var zoom_action: StringName = "play_char_zoom_action"
@onready var input_actions_list: Array[StringName] = [zoom_action, aim_action]
@export var check_on_ready_if_inputs_registered: bool = true
var default_input_actions: Dictionary

var state: String

@onready var camera: Camera3D = $Camera
@onready var play_char: PlayerCharacter = $".."
@onready var hud: CanvasLayer = $"../HUD"
@onready var camera_based_raycasts: Node3D = $Camera/CameraBasedRaycasts

func _ready() -> void:
	camera.fov = cam_fov
	_look_yaw = rotation.y
	_look_pitch = camera.rotation.x
	_default_shoulder_offset = shoulder_offset
	_default_camera_distance = camera_distance
	_default_camera_height = camera_height
	_current_shoulder_offset = shoulder_offset
	_current_camera_distance = camera_distance
	_current_camera_height = camera_height
	_stored_shoulder_offset = shoulder_offset
	_stored_camera_distance = camera_distance
	_arm_length = camera_distance
	_holder_height = position.y
	_keep_wall_raycasts_on_pivot()
	build_default_keybinding()
	input_actions_check()
	# Detach from the CharacterBody so we can follow its *interpolated* pose
	# without fighting physics_interpolation (the usual third-person jitter).
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var activate_camera: bool = not multiplayer or is_multiplayer_authority()
	_update_camera_current.call_deferred(activate_camera)
	_set_orbiting(false)
	_apply_look_rotation()
	_snap_to_player_interpolated()

## Wallrun raycasts must stay at the player pivot; otherwise camera offset breaks them.
func _keep_wall_raycasts_on_pivot() -> void:
	if not camera_based_raycasts: return
	if camera_based_raycasts.get_parent() == self: return
	var global_xf := camera_based_raycasts.global_transform
	camera_based_raycasts.reparent(self)
	camera_based_raycasts.global_transform = global_xf

func _update_camera_current(should_be_current: bool) -> void:
	if should_be_current: camera.make_current()
	elif camera.current: camera.clear_current()

func build_default_keybinding() -> void:
	default_input_actions = {
		zoom_action: [Key.KEY_Z],
		aim_action: [Key.KEY_V],
	}

func input_actions_check() -> void:
	if check_on_ready_if_inputs_registered:
		var registered_input_actions: Array[StringName] = []
		for input_action in InputMap.get_actions():
			if input_action.begins_with(&"play_char_"):
				registered_input_actions.append(input_action)

		for input_action in input_actions_list:
			if input_action == &"":
				assert(false, "There's an undefined input action")

			if not registered_input_actions.has(input_action):
				InputMap.add_action(input_action)
				for keycode in default_input_actions[input_action]:
					var input_event_key = InputEventKey.new()
					input_event_key.physical_keycode = keycode
					InputMap.action_add_event(input_action, input_event_key)

func _get_pitch_limits_rad() -> Vector2:
	var lo_deg := maxf(max_view_angles.x, -PITCH_LIMIT_DEG)
	var hi_deg := minf(max_view_angles.y, PITCH_LIMIT_DEG)
	return Vector2(deg_to_rad(lo_deg), deg_to_rad(hi_deg))

func _clamp_look_pitch() -> void:
	var limits := _get_pitch_limits_rad()
	_look_pitch = clampf(_look_pitch, limits.x, limits.y)

func _pivot_origin_from_player(player_xf: Transform3D) -> Vector3:
	return player_xf.origin + Vector3(0.0, _holder_height, 0.0)

func _snap_to_player_interpolated() -> void:
	var player_xf := play_char.get_global_transform_interpolated()
	global_position = _pivot_origin_from_player(player_xf)
	_apply_look_rotation()
	camera.position = _orbit_local(_arm_length, _look_pitch)

func _apply_look_rotation() -> void:
	_clamp_look_pitch()
	rotation = Vector3(0.0, _look_yaw, 0.0)
	camera.rotation = Vector3(_look_pitch, 0.0, 0.0)

func get_look_yaw() -> float:
	return _look_yaw

func is_look_busy() -> bool:
	return _orbiting or is_aiming

## Screen position used for item drag while the cursor is captured (RMB / aim).
func get_drag_cursor_vp() -> Vector2:
	if _has_stored_cursor:
		return _stored_cursor_vp
	return get_viewport().get_mouse_position()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Free-look while RMB orbiting or while aiming.
	if not _orbiting and not is_aiming: return
	var sensitivity := look_sensitivity / 10.0
	if is_aiming:
		sensitivity *= aim_look_sensitivity_scale
	_look_yaw -= event.relative.x * sensitivity
	_look_pitch -= event.relative.y * sensitivity
	_apply_look_rotation()
	get_viewport().set_input_as_handled()

func _set_orbiting(orbiting: bool) -> void:
	_orbiting = orbiting
	_sync_mouse_mode()

func _unhandled_input(event) -> void:
	if multiplayer and not is_multiplayer_authority(): return
	if play_char is PlayerCharacter and (play_char as PlayerCharacter).is_gameplay_blocked():
		_set_orbiting(false)
		is_aiming = false
		_was_aiming = false
		_sync_mouse_mode()
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and not _mouse_captured:
			# event.position is already viewport-space (stretch-safe with Viewport.warp_mouse).
			_stored_cursor_vp = event.position
			_has_stored_cursor = true
		_set_orbiting(event.pressed)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_set_orbiting(false)

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if play_char is PlayerCharacter and (play_char as PlayerCharacter).is_gameplay_blocked():
		_set_orbiting(false)
		is_aiming = false
		_was_aiming = false
		_sync_mouse_mode()
		# Still follow the player so the view doesn't detach behind the menu.
		global_position = _pivot_origin_from_player(play_char.get_global_transform_interpolated())
		_apply_look_rotation()
		_update_camera_position(delta)
		return
	state = play_char.state_machine.curr_state_name
	if camera.v_offset != 0.0:
		camera.v_offset = 0.0
	if absf(rotation_degrees.z) > 0.01:
		rotation_degrees.z = 0.0

	_update_aim(delta)
	# Follow the same interpolated player pose the renderer uses.
	global_position = _pivot_origin_from_player(play_char.get_global_transform_interpolated())
	_apply_look_rotation()
	zoom()
	_update_camera_position(delta)

func _store_hip_fire_camera_state() -> void:
	## Hip-fire targets stay on configured defaults so spam-aim cannot drift the rest pose.
	_stored_shoulder_offset = _default_shoulder_offset
	_stored_camera_distance = _default_camera_distance

func _update_aim(delta: float) -> void:
	if multiplayer and not is_multiplayer_authority():
		return
	var want_aim := Input.is_action_pressed(aim_action)
	if want_aim and not _was_aiming:
		_store_hip_fire_camera_state()
		if not _mouse_captured:
			_stored_cursor_vp = get_viewport().get_mouse_position()
			_has_stored_cursor = true
	_was_aiming = want_aim
	is_aiming = want_aim
	_sync_mouse_mode()

	var t := clampf(aim_blend_speed * delta, 0.0, 1.0)
	# Never change shoulder while aiming — moving X slides the whole view sideways.
	_current_shoulder_offset = _default_shoulder_offset
	var target_distance := aim_camera_distance if is_aiming else _default_camera_distance
	var target_height := aim_camera_height if is_aiming else _default_camera_height
	_current_camera_distance = lerpf(_current_camera_distance, target_distance, t)
	_current_camera_height = lerpf(_current_camera_height, target_height, t)
	_stored_shoulder_offset = _default_shoulder_offset
	_stored_camera_distance = _default_camera_distance

func _orbit_local(arm: float, pitch: float) -> Vector3:
	return Vector3(
		_current_shoulder_offset,
		-sin(pitch) * arm + _current_camera_height,
		cos(pitch) * arm
	)

func _update_camera_position(delta: float) -> void:
	var pitch := _look_pitch
	var target_arm := _current_camera_distance
	var desired_local := _orbit_local(target_arm, pitch)

	# Use this frame's visual pivot so the camera never sits past what the ray allows.
	var pivot_global := global_position
	var desired_global := global_transform * desired_local

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot_global, desired_global)
	query.collision_mask = collision_mask
	var exclude: Array[RID] = [play_char.get_rid()]
	query.exclude = exclude
	var hit := space.intersect_ray(query)

	if hit:
		var full_dist := pivot_global.distance_to(desired_global)
		var safe_dist := maxf(pivot_global.distance_to(hit.position) - collision_margin, 0.2)
		# Snap onto the ray immediately — never lerp into geometry.
		if full_dist > 0.0001:
			var t := clampf(safe_dist / full_dist, 0.0, 1.0)
			camera.position = desired_local * t
			_arm_length = target_arm * t
		else:
			camera.position = desired_local.normalized() * 0.2
			_arm_length = 0.2
	else:
		# Only smooth when extending back out into free space.
		var smooth_t := clampf(collision_smooth_speed * delta, 0.0, 1.0)
		_arm_length = lerpf(_arm_length, target_arm, smooth_t)
		camera.position = _orbit_local(_arm_length, pitch)

func zoom() -> void:
	if Input.is_action_just_pressed(zoom_action):
		zoom_on = !zoom_on
		if !zoom_on: zoom_has_occured = false
		change_fov()

func _kill_fov_tween() -> void:
	if _fov_tween and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = null

func change_fov() -> void:
	if zoom_has_occured:
		return

	state = play_char.state_machine.curr_state_name
	_kill_fov_tween()
	_fov_tween = get_tree().create_tween()
	var fov_change_tween := _fov_tween

	if !zoom_on and !zoom_has_occured:
		if state != null and state != "Jump" and state != "Inair" and state != "Wallrun":
			var state_fovs := get_state_fovs(state)
			fov_change_tween.tween_property(camera, "fov", state_fovs.x, state_fovs.y)
			fov_change_tween.finished.connect(Callable(fov_change_tween, "kill"))
		else:
			if state != "Jump" and state != "Inair" and state != "Wallrun":
				var default_fovs := get_state_fovs("Default")
				fov_change_tween.tween_property(camera, "fov", default_fovs.x, default_fovs.y)
				fov_change_tween.finished.connect(Callable(fov_change_tween, "kill"))
			else:
				var walk_or_run_state: String
				if play_char.walk_or_run == "WalkState":
					walk_or_run_state = "Walk"
				if play_char.walk_or_run == "RunState":
					if (play_char.velocity.x < 1.0 and play_char.velocity.x > -1.0 and play_char.velocity.z < 1.0 and play_char.velocity.z > -1.0):
						walk_or_run_state = "Walk"
					else:
						walk_or_run_state = "Run"
				var walk_or_run_fovs := get_state_fovs(walk_or_run_state)
				fov_change_tween.tween_property(camera, "fov", walk_or_run_fovs.x, walk_or_run_fovs.y)
				fov_change_tween.finished.connect(Callable(fov_change_tween, "kill"))

	if zoom_on and !zoom_has_occured:
		zoom_has_occured = true
		fov_change_tween.tween_property(camera, "fov", camera.fov - zoom_val, zoom_duration)
		fov_change_tween.finished.connect(Callable(fov_change_tween, "kill"))

func get_cam_fov() -> float:
	if Engine.is_editor_hint(): return cam_fov
	if clamp_fov: return clampf(cam_fov, clamp_fov_values.x, clamp_fov_values.y)
	return cam_fov

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_orbiting(false)

func _sync_mouse_mode() -> void:
	if not is_multiplayer_authority():
		return
	if not camera.current:
		return
	if play_char is PlayerCharacter and (play_char as PlayerCharacter).is_gameplay_blocked():
		if _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
		return
	var want_capture := _orbiting or is_aiming
	if want_capture:
		if not _mouse_captured:
			if not _has_stored_cursor:
				_stored_cursor_vp = get_viewport().get_mouse_position()
				_has_stored_cursor = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mouse_captured = true
	elif _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false
		if _has_stored_cursor:
			var pos := _stored_cursor_vp
			_has_stored_cursor = false
			# Windows + stretch: first warp after uncapture often misses (centers / drifts).
			# Viewport get/warp is the matching stretch-safe pair; warp repeatedly.
			_restore_cursor_vp(pos)

func _restore_cursor_vp(pos: Vector2) -> void:
	var vp := get_viewport()
	# Known Godot/Windows bug: need multiple warps after leaving CAPTURED.
	for _i in 8:
		vp.warp_mouse(pos)
	# One more after the OS finishes uncapture.
	_restore_cursor_vp_deferred.call_deferred(pos)

func _restore_cursor_vp_deferred(pos: Vector2) -> void:
	var vp := get_viewport()
	for _i in 8:
		vp.warp_mouse(pos)
