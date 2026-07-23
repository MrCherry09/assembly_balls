extends State

class_name IdleState

var state_name: String = "Idle"
var play_char: CharacterBody3D

func enter(play_char_ref: CharacterBody3D) -> void:
	play_char = play_char_ref
	verifications()

func verifications() -> void:
	play_char.floor_snap_length = 1.0
	if play_char.coyote_jump_cooldown < play_char.coyote_jump_cooldown_ref:
		play_char.coyote_jump_cooldown = play_char.coyote_jump_cooldown_ref
	play_char.tween_hitbox_height(play_char.base_hitbox_height)
	play_char.tween_model_height(play_char.base_model_height)

func physics_update(_delta: float) -> void:
	applies()
	play_char.gravity_apply(_delta)
	input_management()
	move()

func applies() -> void:
	if play_char.jump_cooldown > 0.0:
		play_char.jump_cooldown = -1.0
	if !play_char.is_on_floor() and !play_char.is_on_wall():
		transitioned.emit(self, "InairState")
	if play_char.is_on_floor():
		if play_char.jump_buff_on and play_char.jump_cooldown < 0.0:
			play_char.buffered_jump = true
			play_char.jump_buff_on = false
			transitioned.emit(self, "JumpState")

func input_management() -> void:
	if play_char.action_just_pressed(play_char.jump_action):
		if play_char.jump_cooldown < 0.0:
			transitioned.emit(self, "JumpState")
	if play_char.action_just_pressed(play_char.crouch_action):
		transitioned.emit(self, "CrouchState")
	if play_char.action_just_pressed(play_char.run_action):
		if play_char.walk_or_run == "WalkState":
			play_char.walk_or_run = "RunState"
		elif play_char.walk_or_run == "RunState":
			play_char.walk_or_run = "WalkState"

func move() -> void:
	play_char.input_direction = play_char.get_move_input()
	play_char.move_direction = (play_char.cam_holder.global_basis * Vector3(play_char.input_direction.x, 0.0, play_char.input_direction.y)).normalized()
	if play_char.move_direction and play_char.is_on_floor():
		transitioned.emit(self, play_char.walk_or_run)
	else:
		play_char.set_horizontal_velocity_from_input(Vector3.ZERO, 0.0)
