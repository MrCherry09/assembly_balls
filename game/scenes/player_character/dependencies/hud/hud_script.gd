extends CanvasLayer

class_name HUD

#references
@export var play_char : PlayerCharacter
@export var crosshair: Control
@export var player_info: Control
@export var frames_info: Control

#label references variables
@onready var current_state_label_text: Label = %CurrentStateLabelText
@onready var desired_move_speed_label_text: Label = %DesiredMoveSpeedLabelText
@onready var velocity_label_text: Label = %VelocityLabelText
@onready var velocity_vector_label_text : Label = %VelocityVectorLabelText
@onready var is_on_floor_label_text: Label = %IsOnFloorLabelText
@onready var ceiling_check_label_text: Label = %CeilingCheckLabelText
@onready var jump_buffer_label_text: Label = %JumpBufferLabelText
@onready var coyote_time_label_text: Label = %CoyoteTimeLabelText
@onready var nb_jumps_in_air_allowed_label_text: Label = %NbJumpsInAirAllowedLabelText
@onready var jump_cooldown_label_text: Label = %JumpCooldownLabelText
@onready var slide_time_label_text: Label = %SlideTimeLabelText
@onready var slide_cooldown_label_text: Label = %SlideCooldownLabelText
@onready var nb_dashs_allowed_label_text: Label = %NbDashsAllowedLabelText
@onready var dash_cooldown_label_text: Label = %DashCooldownLabelText
@onready var wallrun_time_label_text : Label = %WallrunTimeLabelText
@onready var frames_per_second_label_text: Label = %FramesPerSecondLabelText
@onready var camera_rotation_label_text: Label = %CameraRotationLabelText
@onready var current_fov_label_text: Label = %CurrentFOVLabelText
@onready var camera_bob_vertical_offset_label_text: Label = %CameraBobVerticalOffsetLabelText
@onready var speed_lines_container: ColorRect = %SpeedLinesContainer
var camera_mode_label: Label

func _ready() -> void:
	_cicle_ui(0)
	_setup_camera_mode_label()
	if play_char and play_char.cam_holder:
		play_char.cam_holder.camera_mode_changed.connect(_on_camera_mode_changed)
		_on_camera_mode_changed(play_char.cam_holder.is_third_person)

func _setup_camera_mode_label() -> void:
	camera_mode_label = Label.new()
	camera_mode_label.name = "CameraModeLabel"
	camera_mode_label.position = Vector2(16, 16)
	camera_mode_label.add_theme_font_size_override("font_size", 18)
	camera_mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	camera_mode_label.add_theme_constant_override("outline_size", 4)
	add_child(camera_mode_label)

func _on_camera_mode_changed(is_third_person: bool) -> void:
	if camera_mode_label:
		if is_third_person:
			camera_mode_label.text = "Camera: Third Person [V]  |  Hold RMB to look"
		else:
			camera_mode_label.text = "Camera: First Person [V]"
	if crosshair:
		crosshair.visible = not is_third_person and _should_show_crosshair()

func _should_show_crosshair() -> bool:
	# Match the HUD cycle matrix: crosshair is column index 2
	var components_states_matrix: Array[Array] = [
		[false, true, true],
		[true, true, true],
		[false, false, false],
		[false, false, true],
	]
	return components_states_matrix[_ui_cicle_index][2]

func _process(_delta : float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority(): if visible: hide(); return
	display_current_FPS()
	display_properties()
	if camera_mode_label and not camera_mode_label.visible:
		camera_mode_label.visible = true

func display_properties() -> void:
	#player character properties
	current_state_label_text.set_text(str(play_char.state_machine.curr_state_name))
	desired_move_speed_label_text.set_text(str(round_to_3_decimals(play_char.desired_move_speed)))
	velocity_label_text.set_text(str(round_to_3_decimals(play_char.velocity.length())))
	velocity_vector_label_text.set_text(str("[ ", round_to_3_decimals(play_char.velocity.x)," ", round_to_3_decimals(play_char.velocity.y)," ", round_to_3_decimals(play_char.velocity.z), " ]"))
	is_on_floor_label_text.set_text(str(play_char.is_on_floor()))
	ceiling_check_label_text.set_text(str(play_char.ceiling_check.is_colliding()))
	jump_buffer_label_text.set_text(str(play_char.jump_buff_on))
	coyote_time_label_text.set_text(str(round_to_3_decimals(play_char.coyote_jump_cooldown)))
	nb_jumps_in_air_allowed_label_text.set_text(str(play_char.nb_jumps_in_air_allowed))
	jump_cooldown_label_text.set_text(str(round_to_3_decimals(play_char.jump_cooldown)))
	slide_time_label_text.set_text(str(round_to_3_decimals(play_char.slide_time)))
	slide_cooldown_label_text.set_text(str(round_to_3_decimals(play_char.time_bef_can_slide_again)))
	nb_dashs_allowed_label_text.set_text(str(play_char.nb_dashs_allowed))
	dash_cooldown_label_text.set_text(str(round_to_3_decimals(play_char.time_bef_can_dash_again)))
	wallrun_time_label_text.set_text(str(round_to_3_decimals(play_char.wallrun_time)))
	
	#camera properties
	camera_rotation_label_text.set_text(str("[ ", round_to_3_decimals(play_char.cam.rotation.x)," ", round_to_3_decimals(play_char.cam.rotation.y)," ", round_to_3_decimals(play_char.cam.rotation.z), " ]"))
	current_fov_label_text.set_text(str(play_char.cam.fov))
	camera_bob_vertical_offset_label_text.set_text(str(round_to_3_decimals(play_char.cam.v_offset)))
	
func display_current_FPS() -> void:
	frames_per_second_label_text.set_text(str(int(Engine.get_frames_per_second())))
	
func display_speed_lines(value : bool) -> void:
	speed_lines_container.visible = value
	
func round_to_3_decimals(value: float) -> float:
	return round(value * 1000.0) / 1000.0

#region UI Components Toggling
var _ui_cicle_index := 0

func _cicle_ui(new_cicle_index: int = _ui_cicle_index + 1) -> void:
	if not is_multiplayer_authority(): return
	var ui_components: Array[Node] = [player_info,frames_info,crosshair]
	var components_states_matrix: Array[Array] = [
		[false, true, true],
		[true, true, true],
		[false, false, false],
		[false, false, true],
	]
	_ui_cicle_index = wrapi(new_cicle_index,0,components_states_matrix.size())
	for i in ui_components.size():
		var should_show: bool = components_states_matrix[_ui_cicle_index][i]
		# Crosshair stays hidden in third person regardless of HUD cycle
		if ui_components[i] == crosshair and play_char and play_char.cam_holder and play_char.cam_holder.is_third_person:
			should_show = false
		ui_components[i].visible = should_show
	if camera_mode_label:
		camera_mode_label.visible = is_multiplayer_authority()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if event.is_action_pressed("cicle_player_hud"):
		_cicle_ui()
		get_viewport().set_input_as_handled()
#endregion
