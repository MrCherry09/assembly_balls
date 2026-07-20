extends Node
class_name ItemGrabber

## Free-cursor grab: LMB picks an item; mouse moves it on a depth plane in world space.
## Release keeps the item's current velocity so a flick throws it.

@export var grab_range: float = 8.0
@export var hold_follow_speed: float = 12.0
## Scales release velocity (1 = keep drag speed as-is).
@export var throw_velocity_scale: float = 0.825
## Caps how hard a flick can launch an item.
@export var throw_max_speed: float = 15.0
## Must match HoldableItem.LAYER_HOLDABLE (physics layer bit 4).
@export var grab_collision_mask: int = 4

var held_item: HoldableItem = null
var _grab_held: bool = false
## Distance along the view ray from the camera to the grab point (kept while held).
var _grab_depth: float = 0.0
## Object origin relative to the ray hit point — stops the mesh snapping under the cursor.
var _grab_offset: Vector3 = Vector3.ZERO
## Smoothed velocity while dragging — used as throw impulse on release.
var _throw_velocity: Vector3 = Vector3.ZERO

@onready var _player: PlayerCharacter = get_parent() as PlayerCharacter

func _camera() -> Camera3D:
	if _player and _player.cam:
		return _player.cam
	return null

func _look_busy() -> bool:
	if _player == null or _player.cam_holder == null:
		return true
	return _player.cam_holder.is_look_busy()

func _is_local_player() -> bool:
	if _player == null:
		return false
	if multiplayer.has_multiplayer_peer():
		return _player.is_multiplayer_authority()
	return true

func _input(event: InputEvent) -> void:
	if not _is_local_player():
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		if _look_busy():
			return
		_grab_held = true
		_try_grab()
	else:
		_grab_held = false
		_release_held()

func _physics_process(delta: float) -> void:
	if not _is_local_player():
		return
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		return
	if not _grab_held:
		_release_held()
		return
	# While looking, cursor is captured — keep dragging via the pre-capture screen pos
	# so the item tracks that point as the camera moves.
	_drag_on_depth_plane(delta)

func _drag_cursor_vp() -> Vector2:
	if _look_busy() and _player and _player.cam_holder:
		return _player.cam_holder.get_drag_cursor_vp()
	return get_viewport().get_mouse_position()

func _try_grab() -> void:
	if held_item != null:
		return
	var cam := _camera()
	if cam == null:
		return
	var hit := _raycast_at_mouse()
	if hit.is_empty():
		return
	var item := _find_holdable(hit.collider)
	if item == null or item.is_held:
		return
	var mouse := _drag_cursor_vp()
	var from: Vector3 = hit.from if hit.has("from") else cam.project_ray_origin(mouse)
	# Lock depth at the surface under the cursor — object stays at that world distance.
	_grab_depth = from.distance_to(hit.position)
	_grab_offset = item.global_position - hit.position
	_throw_velocity = Vector3.ZERO
	held_item = item
	held_item.set_held(self, true)

func _release_held() -> void:
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		_grab_depth = 0.0
		_grab_offset = Vector3.ZERO
		_throw_velocity = Vector3.ZERO
		return
	var item := held_item
	var release_vel := _throw_velocity
	if release_vel.length() < item.linear_velocity.length():
		release_vel = item.linear_velocity
	release_vel *= throw_velocity_scale
	if release_vel.length() > throw_max_speed:
		release_vel = release_vel.normalized() * throw_max_speed
	held_item = null
	_grab_depth = 0.0
	_grab_offset = Vector3.ZERO
	_throw_velocity = Vector3.ZERO
	item.set_held(self, false, release_vel)

func _drag_on_depth_plane(delta: float) -> void:
	var cam := _camera()
	if cam == null or held_item == null:
		return
	var mouse := _drag_cursor_vp()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var target := origin + dir * _grab_depth + _grab_offset
	held_item.drive_toward(target, hold_follow_speed, delta)
	# Blend toward current drag velocity so a flick still has momentum on release.
	var sample := held_item.linear_velocity
	var blend := clampf(18.0 * delta, 0.0, 1.0)
	_throw_velocity = _throw_velocity.lerp(sample, blend)

func _raycast_at_mouse() -> Dictionary:
	var cam := _camera()
	if cam == null:
		return {}
	var mouse := _drag_cursor_vp()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * grab_range
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = grab_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _player:
		query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	hit["from"] = from
	return hit

func _find_holdable(node: Object) -> HoldableItem:
	var current: Object = node
	while current:
		if current is HoldableItem:
			return current as HoldableItem
		if current is Node:
			current = (current as Node).get_parent()
		else:
			break
	return null
