extends State

class_name JumpState

var state_name: String = "Jump"
var play_char: CharacterBody3D

func enter(play_char_ref: CharacterBody3D) -> void:
	play_char = play_char_ref
	verifications()
	jump()

func verifications() -> void:
	if play_char.floor_snap_length != 0.0:
		play_char.floor_snap_length = 0.0
	if play_char.jump_cooldown < play_char.jump_cooldown_ref:
		play_char.jump_cooldown = play_char.jump_cooldown_ref
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
		if play_char.velocity.y < 0.0:
			transitioned.emit(self, "InairState")
	if play_char.is_on_floor():
		if play_char.move_direction:
			transitioned.emit(self, play_char.walk_or_run)
		else:
			transitioned.emit(self, "IdleState")

func input_management() -> void:
	if play_char.action_just_pressed(play_char.jump_action):
		if play_char.jump_cooldown < 0.0:
			jump()

func move() -> void:
	play_char.input_direction = play_char.get_move_input()
	play_char.move_direction = (play_char.cam_holder.global_basis * Vector3(play_char.input_direction.x, 0.0, play_char.input_direction.y)).normalized()
	if !play_char.is_on_floor():
		play_char.set_horizontal_velocity_from_input(play_char.move_direction, play_char.current_ground_move_speed())

func jump() -> void:
	var can_jump := false
	if !play_char.is_on_floor():
		if play_char.coyote_jump_on:
			play_char.jump_cooldown = play_char.jump_cooldown_ref
			play_char.coyote_jump_cooldown = -1.0
			play_char.coyote_jump_on = false
			can_jump = true
	if play_char.is_on_floor():
		play_char.jump_cooldown = play_char.jump_cooldown_ref
		can_jump = true
	if play_char.buffered_jump:
		play_char.buffered_jump = false
		play_char.jump_cooldown = play_char.jump_cooldown_ref
	if can_jump:
		play_char.velocity.y = play_char.jump_velocity
