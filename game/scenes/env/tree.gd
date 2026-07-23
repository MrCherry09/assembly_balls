extends StaticBody3D
class_name TreePlaceholder

@export var hp: float = 100.0
@export var log_scene: PackedScene = preload("res://scenes/items/log.tscn")

@export_group("Drops")
@export var min_drop_amount: int = 3
@export var max_drop_amount: int = 5
@export var lumber_luck: float = 1.0

@export_group("Break")
@export var break_duration: float = 1.05
@export var break_tip_radians: float = PI * 0.52
@export var break_shake_strength: float = 0.07

@export_group("Hit feedback")
@export var hit_shake_strength: float = 0.045
@export var hit_tip_radians: float = 0.04
@export var hit_shake_duration: float = 0.16
@export var hit_yaw_jitter: float = 0.55
@export var hit_bob_strength: float = 0.028
@export var hit_twist_radians: float = 0.03

@export_group("Network")
@export var tree_id: int = 0

@onready var _model: Node3D = $Model

var _breaking: bool = false
var _hit_tween: Tween
var _rest_model_pos: Vector3 = Vector3.ZERO
var _rest_model_basis: Basis = Basis.IDENTITY
var _rest_pose_cached: bool = false

func _ready() -> void:
	add_to_group("network_trees")
	_cache_rest_pose()

func setup_network() -> void:
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)

func is_breaking() -> bool:
	return _breaking

func _cache_rest_pose() -> void:
	if _model == null:
		_model = get_node_or_null("Model") as Node3D
	if _model == null:
		return
	_rest_model_pos = _model.position
	_rest_model_basis = _model.basis
	_rest_pose_cached = true

## Called from local attack in offline mode, or ignored on clients in multiplayer.
func take_damage(amount: float, hit_yaw: float = 0.0) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	take_damage_host(amount, hit_yaw)

## Host-only damage application (WorldNet melee hits).
func take_damage_host(amount: float, hit_yaw: float = 0.0) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _breaking:
		return
	hp -= amount
	if hp <= 0.0:
		_die(hit_yaw)
	else:
		_host_broadcast_hit_shake(hit_yaw)

func _host_broadcast_hit_shake(hit_yaw: float) -> void:
	var shake_seed := randi()
	if WorldNet and WorldNet.is_net_active():
		WorldNet.host_tree_hit_fx(tree_id, hit_yaw, shake_seed)
	else:
		play_hit_shake(hit_yaw, shake_seed)

func _die(hit_yaw: float) -> void:
	if _breaking:
		return
	var count := _roll_log_count()
	# Tip opposite the hit direction (toward the attacker).
	var fall_yaw := hit_yaw + PI
	if WorldNet:
		WorldNet.host_break_tree(self, count, fall_yaw)
	else:
		spawn_logs_local(count)
		play_break_animation(fall_yaw)

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

## Small chop feedback — synced to all peers via WorldNet (same seed → same motion).
func play_hit_shake(hit_yaw: float, shake_seed: int = 0) -> void:
	if _breaking:
		return
	if _model == null:
		_model = get_node_or_null("Model") as Node3D
	if _model == null:
		return
	if not _rest_pose_cached:
		_cache_rest_pose()

	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_model.position = _rest_model_pos
	_model.basis = _rest_model_basis

	var rng := RandomNumberGenerator.new()
	rng.seed = shake_seed

	var yaw := hit_yaw + rng.randf_range(-hit_yaw_jitter, hit_yaw_jitter)
	var push := Vector3(sin(yaw), 0.0, cos(yaw))
	if push.length_squared() < 0.0001:
		push = Vector3.FORWARD
	push = push.normalized()

	var tip_axis := Vector3.UP.cross(push)
	if tip_axis.length_squared() < 0.0001:
		tip_axis = Vector3.RIGHT
	else:
		tip_axis = tip_axis.normalized()
	# Skew the tip axis so each hit leans a bit differently.
	var skew := rng.randf_range(-0.35, 0.35)
	tip_axis = (tip_axis + push * skew + Vector3.UP * rng.randf_range(-0.12, 0.12)).normalized()

	var strength := hit_shake_strength * rng.randf_range(0.6, 1.35)
	var tip_amount := hit_tip_radians * rng.randf_range(0.65, 1.4)
	if rng.randf() < 0.5:
		tip_amount = -tip_amount
	var twist_amount := hit_twist_radians * rng.randf_range(-1.2, 1.2)
	var bob_up := hit_bob_strength * rng.randf_range(0.45, 1.15)
	if rng.randf() < 0.35:
		bob_up = -bob_up * rng.randf_range(0.35, 0.8)
	var bob_dip := -signf(bob_up) * hit_bob_strength * rng.randf_range(0.25, 0.7)
	var duration := hit_shake_duration * rng.randf_range(0.85, 1.2)
	var peak_t := rng.randf_range(0.35, 0.48)
	var dip_t := rng.randf_range(0.62, 0.78)
	var lateral := tip_axis * strength * rng.randf_range(0.15, 0.55)
	var rest_pos := _rest_model_pos
	var rest_basis := _rest_model_basis

	_hit_tween = create_tween()
	_hit_tween.tween_method(
		func(t: float) -> void:
			# t: 0 → peak → opposite bob → rest
			var pos: Vector3
			var rot_w: float
			if t <= peak_t:
				var u := t / peak_t
				u = sin(u * PI * 0.5) # ease out
				pos = rest_pos.lerp(rest_pos + push * strength + Vector3(0.0, bob_up, 0.0) + lateral, u)
				rot_w = u
			elif t <= dip_t:
				var u := (t - peak_t) / maxf(dip_t - peak_t, 0.0001)
				u = 0.5 - 0.5 * cos(u * PI) # smooth
				var peak := rest_pos + push * strength + Vector3(0.0, bob_up, 0.0) + lateral
				var dip := rest_pos + push * strength * -0.2 + Vector3(0.0, bob_dip, 0.0) - lateral * 0.35
				pos = peak.lerp(dip, u)
				rot_w = lerpf(1.0, 0.35, u)
			else:
				var u := (t - dip_t) / maxf(1.0 - dip_t, 0.0001)
				u = u * u * (3.0 - 2.0 * u) # smoothstep
				var dip := rest_pos + push * strength * -0.2 + Vector3(0.0, bob_dip, 0.0) - lateral * 0.35
				pos = dip.lerp(rest_pos, u)
				rot_w = lerpf(0.35, 0.0, u)
			_model.position = pos
			_model.basis = Basis(tip_axis, tip_amount * rot_w) * Basis(Vector3.UP, twist_amount * rot_w) * rest_basis,
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_LINEAR)

## Plays on every peer (host + clients) from WorldNet's break RPC.
func play_break_animation(fall_yaw: float) -> void:
	if _breaking:
		return
	_breaking = true
	hp = 0.0
	collision_layer = 0
	collision_mask = 0

	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
		_hit_tween = null

	if _model == null:
		_model = get_node_or_null("Model") as Node3D
	if _model == null:
		queue_free()
		return
	if not _rest_pose_cached:
		_cache_rest_pose()
	_model.position = _rest_model_pos
	_model.basis = _rest_model_basis

	var fall_dir := Vector3(sin(fall_yaw), 0.0, cos(fall_yaw))
	var rot_axis := Vector3.UP.cross(fall_dir)
	if rot_axis.length_squared() < 0.0001:
		rot_axis = Vector3.RIGHT
	else:
		rot_axis = rot_axis.normalized()

	var start_basis := _rest_model_basis
	var start_pos := _rest_model_pos
	var shake := break_shake_strength

	var tween := create_tween()
	tween.set_parallel(false)
	# Wind-up shake so the chop reads before the fall.
	tween.tween_property(_model, "position:x", start_pos.x + shake, 0.05).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_model, "position:x", start_pos.x - shake, 0.05)
	tween.tween_property(_model, "position:x", start_pos.x + shake * 0.5, 0.04)
	tween.tween_property(_model, "position:x", start_pos.x, 0.04)
	# Tip over around the base.
	tween.tween_method(
		func(angle: float) -> void:
			_model.basis = Basis(rot_axis, angle) * start_basis
			# Settle slightly into the ground as it lands.
			var t := clampf(angle / maxf(break_tip_radians, 0.001), 0.0, 1.0)
			_model.position = start_pos + Vector3(0.0, -0.15 * t * t, 0.0),
		0.0,
		break_tip_radians,
		break_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Soft impact settle.
	tween.tween_property(_model, "position:y", start_pos.y - 0.22, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)
