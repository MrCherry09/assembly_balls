extends CanvasLayer

class_name HUD

@export var play_char: PlayerCharacter
@export var crosshair: Control
@export var player_info: Control
@export var frames_info: Control

@onready var current_state_label_text: Label = %CurrentStateLabelText
@onready var move_speed_label_text: Label = %DesiredMoveSpeedLabelText
@onready var velocity_label_text: Label = %VelocityLabelText
@onready var velocity_vector_label_text: Label = %VelocityVectorLabelText
@onready var is_on_floor_label_text: Label = %IsOnFloorLabelText
@onready var ceiling_check_label_text: Label = %CeilingCheckLabelText
@onready var jump_buffer_label_text: Label = %JumpBufferLabelText
@onready var coyote_time_label_text: Label = %CoyoteTimeLabelText
@onready var jump_cooldown_label_text: Label = %JumpCooldownLabelText
@onready var frames_per_second_label_text: Label = %FramesPerSecondLabelText
@onready var camera_rotation_label_text: Label = %CameraRotationLabelText
@onready var current_fov_label_text: Label = %CurrentFOVLabelText
@onready var camera_bob_vertical_offset_label_text: Label = %CameraBobVerticalOffsetLabelText
@onready var speed_lines_container: ColorRect = %SpeedLinesContainer
var look_hint_label: Label

func _ready() -> void:
	_cicle_ui(0)
	_setup_look_hint_label()
	_hide_removed_debug_rows()

func _hide_removed_debug_rows() -> void:
	for path in [
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/NbJumpsInAirAllowedLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/NbJumpsInAirAllowedLabelText",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/SlideTimeLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/SlideTimeLabelText",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/SlideCooldownLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/SlideCooldownLabelText",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/NbDashsAllowedLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/NbDashsAllowedLabelText",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/DashCooldownLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/DashCooldownLabelText",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/WallrunTimeLabel",
		"PlayerInfo/PanelContainer/PlayCharInfos/VBoxContainer/WallrunTimeLabelText",
	]:
		var node := get_node_or_null(path)
		if node:
			node.visible = false

func _setup_look_hint_label() -> void:
	look_hint_label = Label.new()
	look_hint_label.name = "LookHintLabel"
	look_hint_label.position = Vector2(16, 16)
	look_hint_label.text = "RMB look  |  V aim  |  LMB grab items (free cursor)"

	look_hint_label.add_theme_font_size_override("font_size", 18)
	look_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	look_hint_label.add_theme_constant_override("outline_size", 4)
	add_child(look_hint_label)

func _process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		if visible:
			hide()
		return
	display_current_FPS()
	display_properties()
	if look_hint_label and not look_hint_label.visible:
		look_hint_label.visible = true

func display_properties() -> void:
	current_state_label_text.set_text(str(play_char.state_machine.curr_state_name))
	move_speed_label_text.set_text(str(round_to_3_decimals(play_char.move_speed)))
	velocity_label_text.set_text(str(round_to_3_decimals(play_char.velocity.length())))
	velocity_vector_label_text.set_text(str("[ ", round_to_3_decimals(play_char.velocity.x), " ", round_to_3_decimals(play_char.velocity.y), " ", round_to_3_decimals(play_char.velocity.z), " ]"))
	is_on_floor_label_text.set_text(str(play_char.is_on_floor()))
	ceiling_check_label_text.set_text(str(play_char.ceiling_check.is_colliding()))
	jump_buffer_label_text.set_text(str(play_char.jump_buff_on))
	coyote_time_label_text.set_text(str(round_to_3_decimals(play_char.coyote_jump_cooldown)))
	jump_cooldown_label_text.set_text(str(round_to_3_decimals(play_char.jump_cooldown)))
	camera_rotation_label_text.set_text(str("[ ", round_to_3_decimals(play_char.cam.rotation.x), " ", round_to_3_decimals(play_char.cam.rotation.y), " ", round_to_3_decimals(play_char.cam.rotation.z), " ]"))
	current_fov_label_text.set_text(str(play_char.cam.fov))
	camera_bob_vertical_offset_label_text.set_text(str(round_to_3_decimals(play_char.cam.v_offset)))

func display_current_FPS() -> void:
	frames_per_second_label_text.set_text(str(int(Engine.get_frames_per_second())))

func display_speed_lines(value: bool) -> void:
	speed_lines_container.visible = value

func round_to_3_decimals(value: float) -> float:
	return round(value * 1000.0) / 1000.0

#region UI Components Toggling
var _ui_cicle_index := 0

func _cicle_ui(new_cicle_index: int = _ui_cicle_index + 1) -> void:
	if not is_multiplayer_authority():
		return
	var ui_components: Array[Node] = [player_info, frames_info, crosshair]
	var components_states_matrix: Array[Array] = [
		[false, true, true],
		[true, true, true],
		[false, false, false],
		[false, false, true],
	]
	_ui_cicle_index = wrapi(new_cicle_index, 0, components_states_matrix.size())
	for i in ui_components.size():
		ui_components[i].visible = components_states_matrix[_ui_cicle_index][i]
	if look_hint_label:
		look_hint_label.visible = is_multiplayer_authority()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("cicle_player_hud"):
		_cicle_ui()
		get_viewport().set_input_as_handled()
#endregion
