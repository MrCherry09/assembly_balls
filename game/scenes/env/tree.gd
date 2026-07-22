extends StaticBody3D
class_name TreePlaceholder

@export var hp: float = 100.0
@export var log_scene: PackedScene = preload("res://scenes/items/log.tscn")

@export_group("Drops")
@export var min_drop_amount: int = 3
@export var max_drop_amount: int = 5
@export var lumber_luck: float = 1.0

@export_group("Network")
@export var tree_id: int = 0

func _ready() -> void:
	add_to_group("network_trees")

func setup_network() -> void:
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)

## Called from local attack in offline mode, or ignored on clients in multiplayer.
func take_damage(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	take_damage_host(amount)

## Host-only damage application (WorldNet melee hits).
func take_damage_host(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0.0:
		_die()

func _die() -> void:
	var count := _roll_log_count()
	if WorldNet:
		WorldNet.host_spawn_logs_from_tree(self, count)
		WorldNet.host_despawn_tree(tree_id)
	else:
		spawn_logs_local(count)
		queue_free()

func _roll_log_count() -> int:
	var r := randf()
	r = pow(r, 1.0 / max(0.01, lumber_luck))
	var num_logs := min_drop_amount + int(r * (max_drop_amount - min_drop_amount + 0.9999))
	if num_logs > max_drop_amount:
		num_logs = max_drop_amount
	return num_logs

func spawn_logs_local(count: int = -1) -> void:
	if not log_scene:
		return
	if count < 0:
		count = _roll_log_count()
	var parent := get_parent()
	for i in range(count):
		var log_instance := log_scene.instantiate() as Node3D
		if log_instance:
			parent.add_child(log_instance)
			var offset := Vector3(
				randf_range(-1.0, 1.0),
				randf_range(0.5, 2.5),
				randf_range(-1.0, 1.0)
			)
			log_instance.global_position = global_position + offset
			log_instance.rotation = Vector3(
				randf_range(0, TAU),
				randf_range(0, TAU),
				randf_range(0, TAU)
			)
