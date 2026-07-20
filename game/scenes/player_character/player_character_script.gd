extends CharacterBody3D
class_name PlayerCharacter

## Based on "Jeheno Advanced First Person Controller" by Jeh3no
## with modified logic, models and multiplayer compatibility

@export var nick_label: Label3D

@export_group("Speeds")
## Multiplies all movement speeds at runtime.
@export var speed_modifier: float = 1.0
@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var jump_height: float = 2.2

@export_group("Movement")
var move_speed: float
var input_direction: Vector2
var move_direction: Vector3
var last_frame_position: Vector3
var last_frame_velocity: Vector3
var was_on_floor: bool
var walk_or_run: String = "WalkState"
@export var base_hitbox_height: float = 2.0
@export var base_model_height: float = 2.0
@export var height_change_duration: float = 0.15
@export var continious_run: bool = false

@export_group("Crouch")
@export var continious_crouch: bool = false
@export var crouch_hitbox_height: float = 1.2
@export var crouch_model_height: float = 1.2

@export_group("Jump")
@export var jump_time_to_peak: float = 0.35
@export var jump_time_to_fall: float = 0.3
@onready var jump_velocity: float:
	get: return (jump_height / jump_time_to_peak) / gravity_modifier
@export var jump_cooldown: float = 0.25
var jump_cooldown_ref: float
var jump_buff_on: bool = false
var buffered_jump: bool = false
@export var coyote_jump_cooldown: float = 0.12
var coyote_jump_cooldown_ref: float
var coyote_jump_on: bool = false
@export var _gravity_modifier: float = 1.0:
	set(value):
		if _gravity_modifier != value:
			gravity_modifier += value - gravity_modifier
			_gravity_modifier = value
var gravity_modifier: float = 1.0

func get_fall_gravity() -> float:
	return (-jump_height) / (jump_time_to_fall * jump_time_to_fall) * gravity_modifier

func get_jump_gravity() -> float:
	return (-jump_height) / (jump_time_to_peak * jump_time_to_peak) * gravity_modifier

var fall_gravity: float: get = get_fall_gravity
var jump_gravity: float: get = get_jump_gravity

@export_group("Body facing")
@export var body_turn_speed: float = 12.0
@export var aim_body_turn_speed: float = 40.0
var body_yaw: float = 0.0

@export_group("Keybinds")
@export var move_forward_action: StringName = "play_char_move_forward_action"
@export var move_backward_action: StringName = "play_char_move_backward_action"
@export var move_left_action: StringName = "play_char_move_left_ation"
@export var move_right_action: StringName = "play_char_move_right_action"
@export var run_action: StringName = "play_char_run_action"
@export var crouch_action: StringName = "play_char_crouch_action"
@export var jump_action: StringName = "play_char_jump_action"

@onready var input_actions_list: Array[StringName] = [
	move_forward_action, move_backward_action, move_left_action, move_right_action,
	run_action, crouch_action, jump_action,
]
@export var check_on_ready_if_inputs_registered: bool = true
var default_input_actions: Dictionary

@onready var cam_holder: CameraObject = %CameraHolder
@onready var cam: Camera3D = %Camera
@onready var model: MeshInstance3D = $Model
@onready var hitbox: CollisionShape3D = $Hitbox
@onready var state_machine: Node = $StateMachine
@onready var hud: CanvasLayer = $HUD
@onready var ceiling_check: RayCast3D = %CeilingCheck
@onready var floor_check: RayCast3D = %FloorCheck
@onready var character_model: Node3D = %CharacterModel

func _ready() -> void:
	# Holdables never collide with the player (separate physics layers).
	collision_priority = 100.0

	if not is_multiplayer_authority():
		cam_holder.camera.clear_current()
		return

	jump_cooldown_ref = jump_cooldown
	jump_cooldown = -1.0
	coyote_jump_cooldown_ref = coyote_jump_cooldown

	build_default_keybinding()
	input_actions_check()
	body_yaw = cam_holder.rotation.y

func build_default_keybinding() -> void:
	default_input_actions = {
		move_forward_action: [Key.KEY_W, Key.KEY_UP],
		move_backward_action: [Key.KEY_S, Key.KEY_DOWN],
		move_left_action: [Key.KEY_A, Key.KEY_LEFT],
		move_right_action: [Key.KEY_D, Key.KEY_RIGHT],
		run_action: [Key.KEY_SHIFT],
		crouch_action: [Key.KEY_CTRL],
		jump_action: [Key.KEY_SPACE],
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

func _yaw_from_direction(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)

func _update_model_visuals(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if cam_holder.is_aiming:
		body_yaw = lerp_angle(body_yaw, cam_holder.get_look_yaw(), clampf(aim_body_turn_speed * delta, 0.0, 1.0))
	else:
		var face_dir := move_direction
		face_dir.y = 0.0
		if face_dir.length_squared() > 0.0001:
			var target_yaw := _yaw_from_direction(face_dir.normalized())
			body_yaw = lerp_angle(body_yaw, target_yaw, clampf(body_turn_speed * delta, 0.0, 1.0))
	character_model.rotation.y = body_yaw

func _update_nick_label() -> void:
	nick_label.visible = multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		nick_label.visible = multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()
		var nickname := Online.personal_player_data.display_name
		if not Online.steam_lobby_id and multiplayer.has_multiplayer_peer():
			var player_number := 0
			for mult_id: int in Online.players:
				player_number += 1
				var player_data: PlayerData = Online.players.get(mult_id)
				if not player_data:
					continue
				nickname = "(%s) %s" % [player_number, nickname]
				break
		nick_label.text = nickname

func _process(delta: float) -> void:
	_update_model_visuals(delta)
	_update_nick_label()

func _physics_process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	modify_physics_properties()
	move_and_slide()

func modify_physics_properties() -> void:
	last_frame_position = global_position
	last_frame_velocity = velocity
	was_on_floor = !is_on_floor()

func gravity_apply(delta: float) -> void:
	if not is_on_floor():
		if velocity.y >= 0.0:
			velocity.y += get_jump_gravity() * delta
		elif velocity.y < 0.0:
			velocity.y += get_fall_gravity() * delta

func set_horizontal_velocity_from_input(direction: Vector3, speed: float) -> void:
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func current_ground_move_speed() -> float:
	if walk_or_run == "RunState":
		return scaled(run_speed)
	return scaled(walk_speed)

func scaled(base_speed: float) -> float:
	return base_speed * speed_modifier

func get_walk_speed() -> float:
	return scaled(walk_speed)

func get_run_speed() -> float:
	return scaled(run_speed)

func get_crouch_speed() -> float:
	return scaled(crouch_speed)

func tween_hitbox_height(state_hitbox_height: float) -> void:
	var hitbox_tween: Tween = create_tween()
	if hitbox != null:
		hitbox_tween.tween_method(func(v): set_hitbox_height(v), hitbox.shape.height,
			state_hitbox_height, height_change_duration)
	else:
		hitbox_tween.tween_interval(0.1)
	hitbox_tween.finished.connect(Callable(hitbox_tween, "kill"))
	await hitbox_tween.finished

func set_hitbox_height(value: float) -> void:
	if hitbox.shape is CapsuleShape3D:
		hitbox.shape.height = value

func tween_model_height(state_model_height: float) -> void:
	if character_model:
		var size_diff: float = (base_model_height - state_model_height) / 2 / base_hitbox_height
		character_model.position.y = size_diff
