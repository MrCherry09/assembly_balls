extends State

class_name InairState

var state_name: String = "Inair"
var play_char: CharacterBody3D

func enter(play_char_ref: CharacterBody3D) -> void:
	play_char = play_char_ref
	verifications()

func verifications() -> void:
	if play_char.floor_snap_length != 0.0:
		play_char.floor_snap_length = 0.0
	play_char.tween_hitbox_height(play_char.base_hitbox_height)
	play_char.tween_model_height(play_char.base_model_height)

func physics_update(delta: float) -> void:
	applies(delta)
	play_char.gravity_apply(delta)
	input_management()
	move()

func applies(delta: float) -> void:
	if !play_char.is_on_floor():
		if play_char.jump_cooldown > 0.0:
			play_char.jump_cooldown -= delta
		if play_char.coyote_jump_cooldown > 0.0:
			play_char.coyote_jump_cooldown -= delta
	if play_char.is_on_floor():
		if play_char.jump_buff_on:
			play_char.buffered_jump = true
			play_char.jump_buff_on = false
			transitioned.emit(self, "JumpState")
		elif play_char.move_direction:
			transitioned.emit(self, play_char.walk_or_run)
		else:
			transitioned.emit(self, "IdleState")

func input_management() -> void:
	if Input.is_action_just_pressed(play_char.jump_action):
		if play_char.floor_check.is_colliding() and play_char.last_frame_position.y > play_char.position.y:
			play_char.jump_buff_on = true
		if play_char.was_on_floor and play_char.coyote_jump_cooldown > 0.0 and play_char.last_frame_position.y > play_char.position.y and play_char.jump_cooldown < 0.0:
			play_char.coyote_jump_on = true
			transitioned.emit(self, "JumpState")

func move() -> void:
	play_char.input_direction = Input.get_vector(play_char.move_left_action, play_char.move_right_action, play_char.move_forward_action, play_char.move_backward_action)
	play_char.move_direction = (play_char.cam_holder.global_basis * Vector3(play_char.input_direction.x, 0.0, play_char.input_direction.y)).normalized()
	if !play_char.is_on_floor():
		play_char.set_horizontal_velocity_from_input(play_char.move_direction, play_char.current_ground_move_speed())
