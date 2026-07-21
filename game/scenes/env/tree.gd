extends StaticBody3D
class_name TreePlaceholder

@export var hp: float = 100.0
@export var log_scene: PackedScene = preload("res://scenes/items/log.tscn")

@export_group("Drops")
@export var min_drop_amount: int = 3
@export var max_drop_amount: int = 5
@export var lumber_luck: float = 1.0

func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		spawn_logs()
		queue_free()

func spawn_logs() -> void:
	if not log_scene:
		return
		
	var r := randf()
	r = pow(r, 1.0 / max(0.01, lumber_luck))
	var num_logs := min_drop_amount + int(r * (max_drop_amount - min_drop_amount + 0.9999))
	if num_logs > max_drop_amount:
		num_logs = max_drop_amount
	var parent := get_parent()
	for i in range(num_logs):
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
