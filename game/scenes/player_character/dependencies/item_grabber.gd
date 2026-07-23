extends Node
class_name ItemGrabber

## Free-cursor grab: LMB picks an item; mouse moves it on a depth plane in world space.
## In multiplayer, grab/drag/release go through WorldNet (host-authoritative).

const PICKUP_ACTION: StringName = &"pickup_holdable_item"

@export var grab_range: float = 8.0
@export var hold_follow_speed: float = 12.0
## Scales release velocity (1 = keep drag speed as-is).
@export var throw_velocity_scale: float = 0.825
## Caps how hard a flick can launch an item.
@export var throw_max_speed: float = 15.0
## Must match HoldableItem.LAYER_HOLDABLE (physics layer bit 4).
@export var grab_collision_mask: int = 4
## Depth used when spawning an item from the inventory into a held state.
@export var inventory_drag_depth: float = 3.0

var held_item: HoldableItem = null
var _grab_held: bool = false
## Distance along the view ray from the camera to the grab point (kept while held).
var _grab_depth: float = 0.0
## Object origin relative to the ray hit point — stops the mesh snapping under the cursor.
var _grab_offset: Vector3 = Vector3.ZERO
## Smoothed velocity while dragging — used as throw impulse on release.
var _throw_velocity: Vector3 = Vector3.ZERO
var _pending_grab_id: int = 0

@onready var _player: PlayerCharacter = get_parent() as PlayerCharacter

func _ready() -> void:
	_ensure_pickup_action()
	if not WorldNet.item_held.is_connected(_on_item_held):
		WorldNet.item_held.connect(_on_item_held)
	if not WorldNet.item_released.is_connected(_on_item_released):
		WorldNet.item_released.connect(_on_item_released)
	if not WorldNet.inventory_granted.is_connected(_on_inventory_granted):
		WorldNet.inventory_granted.connect(_on_inventory_granted)

func _ensure_pickup_action() -> void:
	if not InputMap.has_action(PICKUP_ACTION):
		InputMap.add_action(PICKUP_ACTION)
	else:
		InputMap.action_erase_events(PICKUP_ACTION)

	var input_event_key := InputEventKey.new()
	input_event_key.keycode = Key.KEY_E
	input_event_key.physical_keycode = Key.KEY_E
	InputMap.action_add_event(PICKUP_ACTION, input_event_key)

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

func _gameplay_blocked() -> bool:
	return _player != null and _player.is_gameplay_blocked()

func _my_peer_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1

func _hud() -> HUD:
	if _player == null:
		return null
	return _player.hud as HUD

func _uses_world_net() -> bool:
	return WorldNet != null and WorldNet.is_net_active()

func _input(event: InputEvent) -> void:
	if not _is_local_player():
		return
	if _gameplay_blocked():
		if _grab_held or held_item != null:
			_grab_held = false
			_release_held()
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		var hud := _hud()
		if hud and hud.is_point_over_inventory_ui(event.position):
			return
		if _look_busy():
			if held_item == null and _player.has_method("attack"):
				_player.attack()
			return
		_grab_held = true
		if not _try_grab() and held_item == null:
			if _player.has_method("attack"):
				_player.attack()
	else:
		_grab_held = false
		_release_held()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player() or _gameplay_blocked():
		return
	if not event.is_action_pressed(PICKUP_ACTION):
		return
	_try_pickup_to_inventory()
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not _is_local_player() or _gameplay_blocked():
		return
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		return
	if not _grab_held:
		_release_held()
		return
	_drag_on_depth_plane(delta)

func _drag_cursor_vp() -> Vector2:
	if _look_busy() and _player and _player.cam_holder:
		return _player.cam_holder.get_drag_cursor_vp()
	return get_viewport().get_mouse_position()

func _on_item_held(item_id: int, peer_id: int) -> void:
	if not _is_local_player():
		return
	if peer_id != _my_peer_id():
		return
	var item := WorldNet.get_item(item_id)
	if item == null:
		return
	held_item = item
	_grab_held = true
	if _pending_grab_id == item_id or _grab_depth <= 0.0:
		_ensure_grab_depth_for(item)
	_pending_grab_id = 0

func _on_item_released(item_id: int) -> void:
	if held_item and is_instance_valid(held_item) and held_item.item_id == item_id:
		held_item = null
		_grab_held = false
		_grab_depth = 0.0
		_grab_offset = Vector3.ZERO
		_throw_velocity = Vector3.ZERO

func _on_inventory_granted(scene_path: String, icon_path: String) -> void:
	if not _is_local_player():
		return
	var hud := _hud()
	if hud:
		hud.add_inventory_item_from_net(scene_path, icon_path)

func _ensure_grab_depth_for(item: HoldableItem) -> void:
	var cam := _camera()
	if cam == null:
		return
	var mouse := _drag_cursor_vp()
	var from := cam.project_ray_origin(mouse)
	_grab_depth = from.distance_to(item.global_position)
	_grab_offset = Vector3.ZERO

func _try_grab() -> bool:
	if held_item != null:
		return false
	var cam := _camera()
	if cam == null:
		return false
	var hit := _raycast_at_mouse()
	if hit.is_empty():
		return false
	var item := _find_holdable(hit.collider)
	if item == null or item.is_held:
		return false
	var mouse := _drag_cursor_vp()
	var from: Vector3 = hit.from if hit.has("from") else cam.project_ray_origin(mouse)
	_grab_depth = from.distance_to(hit.position)
	_grab_offset = item.global_position - hit.position
	_throw_velocity = Vector3.ZERO
	if _uses_world_net():
		_pending_grab_id = item.item_id
		WorldNet.request_grab(item.item_id)
		return true
	held_item = item
	held_item.set_held(self, true)
	return true

func _try_pickup_to_inventory() -> void:
	var hud := _hud()
	if hud == null:
		return

	if held_item != null and is_instance_valid(held_item):
		if _uses_world_net():
			WorldNet.request_pickup(held_item.item_id)
			held_item = null
			_grab_held = false
			_grab_depth = 0.0
			_grab_offset = Vector3.ZERO
			_throw_velocity = Vector3.ZERO
			return
		if hud.try_add_holdable_item(held_item):
			var item := held_item
			held_item = null
			_grab_held = false
			_grab_depth = 0.0
			_grab_offset = Vector3.ZERO
			_throw_velocity = Vector3.ZERO
			item.queue_free()
		return

	var hit := _raycast_at_mouse()
	if hit.is_empty():
		return
	var item := _find_holdable(hit.collider)
	if item == null or item.is_held:
		return
	if _uses_world_net():
		WorldNet.request_pickup(item.item_id)
		return
	if hud.try_add_holdable_item(item):
		item.queue_free()

func begin_inventory_drag(item: HoldableItem) -> bool:
	## Offline-only path. Multiplayer drops go through WorldNet.request_drop.
	if not _is_local_player():
		return false
	if item == null or held_item != null:
		return false
	var cam := _camera()
	if cam == null:
		return false

	var mouse := _drag_cursor_vp()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var target := origin + dir * inventory_drag_depth

	held_item = item
	_grab_held = true
	_grab_depth = origin.distance_to(target)
	_grab_offset = Vector3.ZERO
	_throw_velocity = Vector3.ZERO
	held_item.global_position = target
	held_item.set_held(self, true)
	return true

func begin_net_inventory_drag(scene_path: String) -> void:
	if not _is_local_player():
		return
	var cam := _camera()
	if cam == null:
		return
	var mouse := _drag_cursor_vp()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var target := origin + dir * inventory_drag_depth
	_grab_depth = inventory_drag_depth
	_grab_offset = Vector3.ZERO
	_throw_velocity = Vector3.ZERO
	_grab_held = true
	WorldNet.request_drop(scene_path, target, true)

func _release_held() -> void:
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		_grab_depth = 0.0
		_grab_offset = Vector3.ZERO
		_throw_velocity = Vector3.ZERO
		_pending_grab_id = 0
		return
	var item := held_item
	var release_vel := _throw_velocity
	if release_vel.length() < item.linear_velocity.length():
		release_vel = item.linear_velocity
	release_vel *= throw_velocity_scale
	if release_vel.length() > throw_max_speed:
		release_vel = release_vel.normalized() * throw_max_speed
	var item_id := item.item_id
	held_item = null
	_grab_depth = 0.0
	_grab_offset = Vector3.ZERO
	_throw_velocity = Vector3.ZERO
	_pending_grab_id = 0
	if _uses_world_net():
		WorldNet.request_release(item_id, release_vel)
	else:
		item.set_held(self, false, release_vel)

func _drag_on_depth_plane(delta: float) -> void:
	var cam := _camera()
	if cam == null or held_item == null:
		return
	var mouse := _drag_cursor_vp()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var target := origin + dir * _grab_depth + _grab_offset
	if _uses_world_net():
		WorldNet.update_drag_target(held_item.item_id, target)
		# Visuals come from host poses on all peers (including this client).
		var desired_vel := (target - held_item.global_position) * hold_follow_speed
		var blend := clampf(18.0 * delta, 0.0, 1.0)
		_throw_velocity = _throw_velocity.lerp(desired_vel, blend)
		return
	held_item.drive_toward(target, hold_follow_speed, delta)
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
