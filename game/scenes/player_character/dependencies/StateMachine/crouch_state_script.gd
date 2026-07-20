extends State

class_name CrouchState

var state_name: String = "Crouch"
var play_char: CharacterBody3D

func enter(play_char_ref: CharacterBody3D) -> void:
	play_char = play_char_ref
	verifications()

func verifications() -> void:
	play_char.move_speed = play_char.get_crouch_speed()
	play_char.floor_snap_length = 1.0
	if play_char.jump_cooldown > 0.0:
		play_char.jump_cooldown = -1.0
	if play_char.coyote_jump_cooldown < play_char.coyote_jump_cooldown_ref:
		play_char.coyote_jump_cooldown = play_char.coyote_jump_cooldown_ref
	play_char.tween_hitbox_height(play_char.crouch_hitbox_height)
	play_char.tween_model_height(play_char.crouch_model_height)

func physics_update(_delta: float) -> void:
	applies()
	play_char.gravity_apply(_delta)
	input_management()
	move()

func applies() -> void:
	if !play_char.is_on_floor() and !play_char.is_on_wall():
		if play_char.velocity.y < 0.0:
			transitioned.emit(self, "InairState")
	if play_char.is_on_floor():
		if play_char.jump_buff_on and play_char.jump_cooldown < 0.0:
			play_char.buffered_jump = true
			play_char.jump_buff_on = false
			transitioned.emit(self, "JumpState")

func input_management() -> void:
	if Input.is_action_just_pressed(play_char.jump_action):
		if play_char.jump_cooldown < 0.0 and !raycast_verification():
			transitioned.emit(self, "JumpState")
	if play_char.continious_crouch:
		if Input.is_action_just_pressed(play_char.crouch_action):
			if !raycast_verification():
				play_char.walk_or_run = "WalkState"
				transitioned.emit(self, "WalkState")
	elif !Input.is_action_pressed(play_char.crouch_action):
		if !raycast_verification():
			play_char.walk_or_run = "WalkState"
			transitioned.emit(self, "WalkState")

func raycast_verification() -> bool:
	return play_char.ceiling_check.is_colliding()

func move() -> void:
	play_char.input_direction = Input.get_vector(play_char.move_left_action, play_char.move_right_action, play_char.move_forward_action, play_char.move_backward_action)
	play_char.move_direction = (play_char.cam_holder.global_basis * Vector3(play_char.input_direction.x, 0.0, play_char.input_direction.y)).normalized()
	play_char.set_horizontal_velocity_from_input(play_char.move_direction, play_char.move_speed)
