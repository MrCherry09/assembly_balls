extends Node

## Host-authoritative world sync for holdables, trees, melee hits, and inventory world mutations.
## Clients request actions; the host validates and replicates results (README dict/RPC pattern).

const HOLD_FOLLOW_SPEED := 12.0
const GRAB_RANGE := 12.0
const PICKUP_RANGE := 12.0
## Steam peers choke if we flood the reliable channel every physics tick.
const POSE_SYNC_INTERVAL_SEC := 0.05
const POSE_STRIDE := 11 # id, px,py,pz, rx,ry,rz, holder, vx,vy,vz

signal item_held(item_id: int, peer_id: int)
signal item_released(item_id: int)
signal inventory_granted(scene_path: String, icon_path: String)

var items_container: Node3D
var _next_item_id: int = 1
var _next_tree_id: int = 1
var _items: Dictionary = {} # int -> HoldableItem
var _trees: Dictionary = {} # int -> TreePlaceholder
var _drag_targets: Dictionary = {} # item_id -> Vector3
var _holders: Dictionary = {} # item_id -> peer_id
var _attack_last_ms: Dictionary = {} # peer_id -> int
var _setup_done: bool = false
var _pose_sync_timer: float = 0.0

func is_net_active() -> bool:
	return multiplayer.has_multiplayer_peer()

func is_host() -> bool:
	return not is_net_active() or multiplayer.is_server()

func setup(items: Node3D) -> void:
	items_container = items
	_setup_done = true
	_register_scene_world()
	if not Online.player_connected.is_connected(_on_player_connected):
		Online.player_connected.connect(_on_player_connected)

func refresh_network() -> void:
	## Call after a multiplayer peer is created so synchronizers/authority attach.
	for item_id in _items.keys():
		var item := get_item(item_id)
		if item:
			item.setup_network()
	for tree_id in _trees.keys():
		var tree := get_tree_by_id(tree_id)
		if tree:
			tree.setup_network()

func _on_player_connected(player_data: PlayerData) -> void:
	if not multiplayer.is_server():
		return
	if player_data.multiplayer_id == multiplayer.get_unique_id():
		return
	sync_world_to_peer.rpc_id(player_data.multiplayer_id, _build_world_snapshot())

func _register_scene_world() -> void:
	_items.clear()
	_trees.clear()
	_next_item_id = 1
	_next_tree_id = 1
	if items_container:
		for child in items_container.get_children():
			if child is HoldableItem:
				_register_existing_item(child as HoldableItem)
	_find_trees_recursive(get_tree().current_scene)

func _find_trees_recursive(node: Node) -> void:
	if node == null:
		return
	if node is TreePlaceholder and not _trees.values().has(node):
		_register_existing_tree(node as TreePlaceholder)
	for child in node.get_children():
		_find_trees_recursive(child)

func _register_existing_item(item: HoldableItem) -> void:
	if item.item_id <= 0:
		item.item_id = _next_item_id
		_next_item_id += 1
	else:
		_next_item_id = maxi(_next_item_id, item.item_id + 1)
	if item.get_spawn_scene_path() == "" and item.scene_file_path != "":
		item.set_spawn_scene_path(item.scene_file_path)
	item.name = "Item_%d" % item.item_id
	_items[item.item_id] = item
	item.setup_network()
	# Bind the instance (not just id) so a deferred free of an old node can't
	# erase a newly registered item that reused the same id.
	var cb := _on_item_tree_exiting.bind(item)
	if not item.tree_exiting.is_connected(cb):
		item.tree_exiting.connect(cb)

func _register_existing_tree(tree: TreePlaceholder) -> void:
	if tree.tree_id <= 0:
		tree.tree_id = _next_tree_id
		_next_tree_id += 1
	else:
		_next_tree_id = maxi(_next_tree_id, tree.tree_id + 1)
	tree.name = "Tree_%d" % tree.tree_id
	_trees[tree.tree_id] = tree
	tree.setup_network()
	if not tree.is_in_group("network_trees"):
		tree.add_to_group("network_trees")

func _on_item_tree_exiting(item: HoldableItem) -> void:
	if item == null:
		return
	var item_id := item.item_id
	if _items.get(item_id) == item:
		_items.erase(item_id)
		_drag_targets.erase(item_id)
		_holders.erase(item_id)

func _disconnect_item_exit(item: HoldableItem) -> void:
	if item == null:
		return
	var cb := _on_item_tree_exiting.bind(item)
	if item.tree_exiting.is_connected(cb):
		item.tree_exiting.disconnect(cb)

func _clear_all_items_immediate() -> void:
	var old_items: Array = _items.values()
	_items.clear()
	_holders.clear()
	_drag_targets.clear()
	for entry in old_items:
		var item := entry as HoldableItem
		if item == null or not is_instance_valid(item):
			continue
		_disconnect_item_exit(item)
		var parent := item.get_parent()
		if parent:
			parent.remove_child(item)
		item.free()
	if items_container:
		for child in items_container.get_children():
			items_container.remove_child(child)
			child.free()

func get_item(item_id: int) -> HoldableItem:
	var item: HoldableItem = _items.get(item_id) as HoldableItem
	if item and is_instance_valid(item):
		return item
	# Self-heal if the registry was wiped but the node still exists in the world.
	if item_id <= 0 or not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("holdable_items"):
		var holdable := node as HoldableItem
		if holdable and holdable.item_id == item_id and is_instance_valid(holdable):
			_items[item_id] = holdable
			return holdable
	return null

func get_tree_by_id(tree_id: int) -> TreePlaceholder:
	var tree: TreePlaceholder = _trees.get(tree_id) as TreePlaceholder
	if tree and is_instance_valid(tree):
		return tree
	return null

func _physics_process(delta: float) -> void:
	if not _setup_done:
		return
	var my_id := _local_peer_id()
	# Whoever holds an item simulates it locally (same drive_toward + collisions as offline).
	for item_id in _holders.keys():
		if int(_holders[item_id]) != my_id:
			continue
		var item := get_item(item_id)
		if item == null or not item.is_held:
			continue
		if not _drag_targets.has(item_id):
			continue
		item.drive_toward(_drag_targets[item_id], HOLD_FOLLOW_SPEED, delta)
	if not is_net_active():
		return
	_pose_sync_timer += delta
	if _pose_sync_timer < POSE_SYNC_INTERVAL_SEC:
		return
	_pose_sync_timer = 0.0
	if multiplayer.is_server():
		if _peer_holds_any(my_id):
			_broadcast_item_poses(true, false, my_id)
		_broadcast_item_poses(false, true, 0)
	elif _peer_holds_any(my_id):
		_broadcast_item_poses(true, false, my_id)

func _local_peer_id() -> int:
	if is_net_active():
		return multiplayer.get_unique_id()
	return 1

func _peer_holds_any(peer_id: int) -> bool:
	for holder in _holders.values():
		if int(holder) == peer_id:
			return true
	return false

func _broadcast_item_poses(held_only: bool = false, free_only: bool = false, holder_filter: int = 0) -> void:
	if _items.is_empty():
		return
	var poses: Array = []
	for item_id in _items.keys():
		var is_held_item := _holders.has(item_id)
		if held_only and not is_held_item:
			continue
		if free_only and is_held_item:
			continue
		if holder_filter != 0 and int(_holders.get(item_id, 0)) != holder_filter:
			continue
		var item := get_item(item_id)
		if item == null:
			continue
		var pos := item.global_position
		var rot := item.rotation
		var vel := item.linear_velocity
		poses.append([
			item_id,
			pos.x, pos.y, pos.z,
			rot.x, rot.y, rot.z,
			int(_holders.get(item_id, 0)),
			vel.x, vel.y, vel.z,
		])
	if poses.is_empty():
		return
	_rpc_sync_item_poses.rpc(poses)

@rpc("any_peer", "reliable")
func _rpc_sync_item_poses(poses: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var my_id := multiplayer.get_unique_id()
	if sender == my_id:
		return
	for entry in poses:
		if typeof(entry) != TYPE_ARRAY or entry.size() < POSE_STRIDE:
			continue
		var item_id := int(entry[0])
		var holder := int(entry[7])
		# Held: only the holder may publish. Free: only the host.
		if holder != 0:
			if sender != holder or int(_holders.get(item_id, -1)) != holder:
				continue
		elif sender != 1:
			continue
		var item := get_item(item_id)
		if item == null:
			continue
		item.apply_network_pose(
			Vector3(float(entry[1]), float(entry[2]), float(entry[3])),
			Vector3(float(entry[4]), float(entry[5]), float(entry[6])),
			holder != 0,
			holder,
			Vector3(float(entry[8]), float(entry[9]), float(entry[10]))
		)

# --- Grab / drag / release ---------------------------------------------------

func request_grab(item_id: int) -> void:
	if not is_net_active():
		_server_try_grab(item_id, 1)
		return
	if multiplayer.is_server():
		_server_try_grab(item_id, multiplayer.get_unique_id())
	else:
		_rpc_request_grab.rpc_id(1, item_id)

@rpc("any_peer", "reliable")
func _rpc_request_grab(item_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_try_grab(item_id, multiplayer.get_remote_sender_id())

func _server_try_grab(item_id: int, peer_id: int) -> void:
	var item := get_item(item_id)
	if item == null or item.is_held:
		return
	_holders[item_id] = peer_id
	_drag_targets[item_id] = item.global_position
	if is_net_active():
		_rpc_apply_held.rpc(item_id, peer_id, true, Vector3.ZERO)
		if peer_id == multiplayer.get_unique_id():
			_broadcast_item_poses(true, false, peer_id)
	else:
		_apply_held(item_id, peer_id, true, Vector3.ZERO)

func update_drag_target(item_id: int, target: Vector3) -> void:
	## Drag targets stay on the holding peer — they simulate locally.
	if not is_net_active():
		_drag_targets[item_id] = target
		var item := get_item(item_id)
		if item and item.is_held:
			item.drive_toward(target, HOLD_FOLLOW_SPEED, get_physics_process_delta_time())
		return
	if int(_holders.get(item_id, -1)) != multiplayer.get_unique_id():
		return
	_drag_targets[item_id] = target

func request_release(item_id: int, velocity: Vector3) -> void:
	if not is_net_active():
		_server_release(item_id, 1, velocity)
		return
	if multiplayer.is_server():
		_server_release(item_id, multiplayer.get_unique_id(), velocity)
	else:
		_rpc_request_release.rpc_id(1, item_id, velocity)

@rpc("any_peer", "reliable")
func _rpc_request_release(item_id: int, velocity: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_server_release(item_id, multiplayer.get_remote_sender_id(), velocity)

func _server_release(item_id: int, peer_id: int, velocity: Vector3) -> void:
	if _holders.get(item_id, -1) != peer_id:
		return
	_holders.erase(item_id)
	_drag_targets.erase(item_id)
	if is_net_active():
		_rpc_apply_held.rpc(item_id, peer_id, false, velocity)
		_broadcast_item_poses(false, true, 0)
	else:
		_apply_held(item_id, peer_id, false, velocity)

@rpc("any_peer", "reliable", "call_local")
func _rpc_apply_held(item_id: int, peer_id: int, held: bool, release_velocity: Vector3) -> void:
	if is_net_active() and not multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		if sender != 1:
			return
	_apply_held(item_id, peer_id, held, release_velocity)

func _apply_held(item_id: int, peer_id: int, held: bool, release_velocity: Vector3) -> void:
	# Keep holder map in sync on every peer (needed for local sim + pose validation).
	if held:
		_holders[item_id] = peer_id
		if not _drag_targets.has(item_id):
			var existing := get_item(item_id)
			if existing:
				_drag_targets[item_id] = existing.global_position
	else:
		_holders.erase(item_id)
		_drag_targets.erase(item_id)
	var item := get_item(item_id)
	if item == null:
		return
	if held:
		item.set_held_network(peer_id, true, Vector3.ZERO)
		item_held.emit(item_id, peer_id)
	else:
		item.set_held_network(peer_id, false, release_velocity)
		item_released.emit(item_id)

# --- Inventory pickup / drop -------------------------------------------------

func request_pickup(item_id: int) -> void:
	if not is_net_active():
		_server_pickup(item_id, 1)
		return
	if multiplayer.is_server():
		_server_pickup(item_id, multiplayer.get_unique_id())
	else:
		_rpc_request_pickup.rpc_id(1, item_id)

@rpc("any_peer", "reliable")
func _rpc_request_pickup(item_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_pickup(item_id, multiplayer.get_remote_sender_id())

func _server_pickup(item_id: int, peer_id: int) -> void:
	var item := get_item(item_id)
	if item == null:
		return
	if item.is_held and _holders.get(item_id, -1) != peer_id:
		return
	var scene_path := item.get_spawn_scene_path()
	if scene_path == "":
		return
	var icon_path := ""
	if item.inventory_icon and item.inventory_icon.resource_path:
		icon_path = item.inventory_icon.resource_path
	_holders.erase(item_id)
	_drag_targets.erase(item_id)
	if is_net_active():
		_rpc_despawn_item.rpc(item_id)
		if peer_id == multiplayer.get_unique_id():
			inventory_granted.emit(scene_path, icon_path)
		else:
			_rpc_grant_inventory.rpc_id(peer_id, scene_path, icon_path)
		_broadcast_item_poses(false, true, 0)
	else:
		_despawn_item(item_id)
		inventory_granted.emit(scene_path, icon_path)

@rpc("any_peer", "reliable")
func _rpc_grant_inventory(scene_path: String, icon_path: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	inventory_granted.emit(scene_path, icon_path)

func request_drop(scene_path: String, position: Vector3, grab_after: bool) -> void:
	if not is_net_active():
		_server_drop(scene_path, position, grab_after, 1)
		return
	if multiplayer.is_server():
		_server_drop(scene_path, position, grab_after, multiplayer.get_unique_id())
	else:
		_rpc_request_drop.rpc_id(1, scene_path, position, grab_after)

@rpc("any_peer", "reliable")
func _rpc_request_drop(scene_path: String, position: Vector3, grab_after: bool) -> void:
	if not multiplayer.is_server():
		return
	_server_drop(scene_path, position, grab_after, multiplayer.get_remote_sender_id())

func _server_drop(scene_path: String, position: Vector3, grab_after: bool, peer_id: int) -> void:
	var item_id := _host_spawn_item(scene_path, position, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	if item_id <= 0:
		return
	if grab_after:
		_server_try_grab(item_id, peer_id)
	elif is_net_active() and multiplayer.is_server():
		_broadcast_item_poses(false, true, 0)

# --- Attack / trees ----------------------------------------------------------

func request_attack(damage: float, cooldown_ms: int, hit_area: Vector3, body_yaw: float, hitbox_height: float) -> void:
	if not is_net_active():
		_server_attack(1, damage, cooldown_ms, hit_area, body_yaw, hitbox_height)
		return
	if multiplayer.is_server():
		_server_attack(multiplayer.get_unique_id(), damage, cooldown_ms, hit_area, body_yaw, hitbox_height)
	else:
		_rpc_request_attack.rpc_id(1, damage, cooldown_ms, hit_area, body_yaw, hitbox_height)

@rpc("any_peer", "reliable")
func _rpc_request_attack(damage: float, cooldown_ms: int, hit_area: Vector3, body_yaw: float, hitbox_height: float) -> void:
	if not multiplayer.is_server():
		return
	_server_attack(multiplayer.get_remote_sender_id(), damage, cooldown_ms, hit_area, body_yaw, hitbox_height)

func _server_attack(peer_id: int, damage: float, cooldown_ms: int, hit_area: Vector3, body_yaw: float, hitbox_height: float) -> void:
	var now := Time.get_ticks_msec()
	var last: int = _attack_last_ms.get(peer_id, -999999)
	if now - last < cooldown_ms:
		return
	_attack_last_ms[peer_id] = now
	# Show swing on every peer (attacker already played local VFX).
	if is_net_active():
		_rpc_play_attack_fx.rpc(peer_id, body_yaw, hit_area, hitbox_height)
	var player := _get_player(peer_id)
	if player == null:
		return
	var forward := -Vector3(sin(body_yaw), 0.0, cos(body_yaw))
	var local_pos := Vector3(0.0, hitbox_height * 0.5, 0.0) + forward * 1.0
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = hit_area
	query.shape = box_shape
	query.transform = Transform3D(Basis().rotated(Vector3.UP, body_yaw), player.global_position + local_pos)
	query.exclude = [player.get_rid()]
	var results := space.intersect_shape(query)
	for result in results:
		var collider = result.get("collider")
		if collider == null or collider == player:
			continue
		var tree := _find_tree(collider)
		if tree:
			tree.take_damage_host(damage)
			continue
		if collider.has_method("take_damage"):
			collider.take_damage(damage)

@rpc("any_peer", "reliable", "call_local")
func _rpc_play_attack_fx(peer_id: int, body_yaw: float, hit_area: Vector3, hitbox_height: float) -> void:
	if is_net_active() and not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 1:
			return
	# Attacker already played VFX locally when they pressed attack.
	if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		return
	var player := _get_player(peer_id)
	if player and player.has_method("play_attack_vfx_network"):
		player.play_attack_vfx_network(body_yaw, hit_area, hitbox_height)

func host_spawn_logs_from_tree(tree: TreePlaceholder, count: int) -> void:
	if not is_host() or tree == null or tree.log_scene == null:
		return
	for _i in count:
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.5, 2.5),
			randf_range(-1.0, 1.0)
		)
		var rot := Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))
		var path := tree.log_scene.resource_path
		if path == "":
			path = "res://scenes/items/log.tscn"
		_host_spawn_item(path, tree.global_position + offset, rot, Vector3.ZERO, Vector3.ZERO)

func host_despawn_tree(tree_id: int) -> void:
	if is_net_active():
		_rpc_despawn_tree.rpc(tree_id)
	else:
		_despawn_tree(tree_id)

@rpc("any_peer", "reliable", "call_local")
func _rpc_despawn_tree(tree_id: int) -> void:
	if is_net_active() and not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 1:
			return
	_despawn_tree(tree_id)

func _despawn_tree(tree_id: int) -> void:
	var tree := get_tree_by_id(tree_id)
	_trees.erase(tree_id)
	if tree and is_instance_valid(tree):
		tree.queue_free()

# --- Spawn / despawn items ---------------------------------------------------

func _host_spawn_item(scene_path: String, position: Vector3, rotation_euler: Vector3, linear_vel: Vector3, angular_vel: Vector3) -> int:
	if not is_host():
		return -1
	var item_id := _next_item_id
	_next_item_id += 1
	var data := {
		"item_id": item_id,
		"scene_path": scene_path,
		"position": position,
		"rotation": rotation_euler,
		"linear_velocity": linear_vel,
		"angular_velocity": angular_vel,
	}
	if is_net_active():
		_rpc_spawn_item.rpc(data)
	else:
		_spawn_item_from_dict(data)
	return item_id

@rpc("any_peer", "reliable", "call_local")
func _rpc_spawn_item(data: Dictionary) -> void:
	if is_net_active() and not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 1:
			return
	_spawn_item_from_dict(data)

func _spawn_item_from_dict(data: Dictionary) -> void:
	var scene_path: String = data.get("scene_path", "")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var item := packed.instantiate() as HoldableItem
	if item == null:
		return
	item.item_id = int(data.get("item_id", 0))
	item.set_spawn_scene_path(scene_path)
	if items_container:
		items_container.add_child(item, true)
	else:
		get_tree().current_scene.add_child(item, true)
	item.global_position = data.get("position", Vector3.ZERO)
	item.rotation = data.get("rotation", Vector3.ZERO)
	item.linear_velocity = data.get("linear_velocity", Vector3.ZERO)
	item.angular_velocity = data.get("angular_velocity", Vector3.ZERO)
	_register_existing_item(item)

@rpc("any_peer", "reliable", "call_local")
func _rpc_despawn_item(item_id: int) -> void:
	if is_net_active() and not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 1:
			return
	_despawn_item(item_id)

func _despawn_item(item_id: int) -> void:
	var item := get_item(item_id)
	if item:
		_disconnect_item_exit(item)
	_items.erase(item_id)
	_holders.erase(item_id)
	_drag_targets.erase(item_id)
	if item and is_instance_valid(item):
		var parent := item.get_parent()
		if parent:
			parent.remove_child(item)
		item.free()

# --- Late join snapshot ------------------------------------------------------

func _build_world_snapshot() -> Dictionary:
	var items: Array = []
	for item_id in _items:
		var item := get_item(item_id)
		if item == null:
			continue
		var scene_path := item.get_spawn_scene_path()
		if scene_path == "":
			continue
		items.append({
			"item_id": item_id,
			"scene_path": scene_path,
			"position": item.global_position,
			"rotation": item.rotation,
			"linear_velocity": item.linear_velocity,
			"angular_velocity": item.angular_velocity,
			"held": item.is_held,
			"holder_peer_id": _holders.get(item_id, 0),
		})
	var trees: Array = []
	for tree_id in _trees:
		var tree := get_tree_by_id(tree_id)
		if tree == null:
			continue
		trees.append({
			"tree_id": tree_id,
			"hp": tree.hp,
			"position": tree.global_position,
			"rotation": tree.rotation,
		})
	return {"items": items, "trees": trees, "next_item_id": _next_item_id, "next_tree_id": _next_tree_id}

@rpc("any_peer", "reliable")
func sync_world_to_peer(snapshot: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_world_snapshot(snapshot)

func _apply_world_snapshot(snapshot: Dictionary) -> void:
	# Immediate free (not queue_free): deferred frees were erasing newly registered
	# items that reused the same ids when their tree_exiting fired a frame later.
	_clear_all_items_immediate()
	_next_item_id = int(snapshot.get("next_item_id", 1))
	_next_tree_id = int(snapshot.get("next_tree_id", 1))
	for entry in snapshot.get("items", []):
		_spawn_item_from_dict(entry)
		var item_id: int = int(entry.get("item_id", 0))
		if entry.get("held", false):
			var peer_id: int = int(entry.get("holder_peer_id", 0))
			_holders[item_id] = peer_id
			_apply_held(item_id, peer_id, true, Vector3.ZERO)
	for entry in snapshot.get("trees", []):
		var tree_id: int = int(entry.get("tree_id", 0))
		var tree := get_tree_by_id(tree_id)
		if tree == null:
			continue
		tree.hp = float(entry.get("hp", tree.hp))
		if tree.hp <= 0.0:
			_despawn_tree(tree_id)

func _get_player(peer_id: int) -> PlayerCharacter:
	var lobby := get_tree().current_scene
	if lobby == null:
		return null
	var container := lobby.get_node_or_null("World3D/PlayersContainer")
	if container == null:
		return null
	return container.get_node_or_null(str(peer_id)) as PlayerCharacter

func _find_tree(node: Object) -> TreePlaceholder:
	var cur := node as Node
	while cur:
		if cur is TreePlaceholder:
			return cur as TreePlaceholder
		cur = cur.get_parent()
	return null
