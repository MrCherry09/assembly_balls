extends Node
class_name ItemGrabber

## Free-cursor grab: click an item with LMB while not aiming / RMB-looking.

@export var grab_range: float = 8.0
@export var hold_distance: float = 2.5
@export var hold_follow_speed: float = 22.0
@export var release_throw_strength: float = 3.5
@export var grab_collision_mask: int = 1

var held_item: HoldableItem = null
var _grab_held: bool = false

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
	if not _grab_held or _look_busy():
		_release_held()
		return
	_follow_mouse_hold_point(delta)

func _try_grab() -> void:
	if held_item != null:
		return
	var item := _raycast_holdable_at_mouse()
	if item == null or item.is_held:
		return
	held_item = item
	held_item.set_held(self, true)

func _release_held() -> void:
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		return
	var cam := _camera()
	var throw_vel := Vector3.ZERO
	if cam:
		var mouse := get_viewport().get_mouse_position()
		throw_vel = cam.project_ray_normal(mouse) * release_throw_strength
	var item := held_item
	held_item = null
	item.set_held(self, false)
	item.apply_release_impulse(throw_vel)

func _follow_mouse_hold_point(delta: float) -> void:
	var cam := _camera()
	if cam == null or held_item == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var target := origin + dir * hold_distance
	var t := clampf(hold_follow_speed * delta, 0.0, 1.0)
	held_item.global_position = held_item.global_position.lerp(target, t)

func _raycast_holdable_at_mouse() -> HoldableItem:
	var cam := _camera()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
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
		return null
	return _find_holdable(hit.collider)

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
