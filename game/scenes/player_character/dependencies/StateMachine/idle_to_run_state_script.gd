extends State

class_name IdleToRunState

var state_name: String = "IdleToRun"
var play_char: CharacterBody3D
var transition_timer: float = 0.0
@export var transition_duration: float = 0.15

func enter(play_char_ref: CharacterBody3D) -> void:
	play_char = play_char_ref
	transition_timer = transition_duration
	verifications()

func verifications() -> void:
	play_char.move_speed = play_char.get_run_speed()
	if play_char.floor_snap_length != 1.0:
		play_char.floor_snap_length = 1.0
	if play_char.jump_cooldown > 0.0:
		play_char.jump_cooldown = -1.0
	if play_char.coyote_jump_cooldown < play_char.coyote_jump_cooldown_ref:
		play_char.coyote_jump_cooldown = play_char.coyote_jump_cooldown_ref
	play_char.tween_hitbox_height(play_char.base_hitbox_height)
	play_char.tween_model_height(play_char.base_model_height)

func physics_update(delta: float) -> void:
	applies()
	play_char.gravity_apply(delta)
	input_management()
	move()
	
	if play_char.move_direction and play_char.is_on_floor():
		transition_timer -= delta
		if transition_timer <= 0.0:
			transitioned.emit(self, "RunState")

func applies() -> void:
	if !play_char.is_on_floor():
		if play_char.velocity.y < 0.0:
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

func move() -> void:
	play_char.input_direction = play_char.get_move_input()
	play_char.move_direction = (play_char.cam_holder.global_basis * Vector3(play_char.input_direction.x, 0.0, play_char.input_direction.y)).normalized()
	if play_char.move_direction and play_char.is_on_floor():
		play_char.set_horizontal_velocity_from_input(play_char.move_direction, play_char.move_speed)
	else:
		transitioned.emit(self, "IdleState")
