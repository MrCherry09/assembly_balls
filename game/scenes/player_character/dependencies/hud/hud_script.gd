extends CanvasLayer

class_name HUD

const INVENTORY_TOGGLE_ACTION: StringName = &"toggle_inventory"
const INVENTORY_PICKUP_ACTION: StringName = &"pickup_holdable_item"
const INVENTORY_SLOT_COUNT: int = 30
const INVENTORY_COLUMNS: int = 5
const INVENTORY_HEIGHT_SCALE: float = 0.5
const DEFAULT_INVENTORY_ICON: Texture2D = preload("res://icon.png")

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
@onready var inventory_root: Control = %InventoryRoot
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var inventory_slots_grid: GridContainer = %InventorySlotsGrid
var look_hint_label: Label
var inventory_open: bool = false
var _inventory_tween: Tween
var _inventory_slot_style: StyleBoxFlat
var _inventory_slot_icons: Array[TextureRect] = []
var _inventory_slot_textures: Array[Texture2D] = []
var _inventory_slot_scene_paths: Array[String] = []

func _ready() -> void:
	_ensure_inventory_action()
	_ensure_inventory_pickup_action()
	get_viewport().size_changed.connect(_refresh_inventory_layout)
	_setup_inventory_ui()
	_cicle_ui(0)
	_setup_look_hint_label()
	_hide_removed_debug_rows()
	_refresh_inventory_layout()
	inventory_root.visible = false

func _ensure_inventory_action() -> void:
	if not InputMap.has_action(INVENTORY_TOGGLE_ACTION):
		InputMap.add_action(INVENTORY_TOGGLE_ACTION)
	else:
		InputMap.action_erase_events(INVENTORY_TOGGLE_ACTION)

	var input_event_key := InputEventKey.new()
	input_event_key.keycode = Key.KEY_TAB
	input_event_key.physical_keycode = Key.KEY_TAB
	InputMap.action_add_event(INVENTORY_TOGGLE_ACTION, input_event_key)

func _ensure_inventory_pickup_action() -> void:
	if not InputMap.has_action(INVENTORY_PICKUP_ACTION):
		InputMap.add_action(INVENTORY_PICKUP_ACTION)
	else:
		InputMap.action_erase_events(INVENTORY_PICKUP_ACTION)

	var input_event_key := InputEventKey.new()
	input_event_key.keycode = Key.KEY_E
	input_event_key.physical_keycode = Key.KEY_E
	InputMap.action_add_event(INVENTORY_PICKUP_ACTION, input_event_key)

func _setup_inventory_ui() -> void:
	_inventory_slot_style = _build_inventory_slot_style()
	_inventory_slot_icons.clear()
	_inventory_slot_textures.clear()
	_inventory_slot_scene_paths.clear()
	for child in inventory_slots_grid.get_children():
		child.queue_free()

	for slot_index in INVENTORY_SLOT_COUNT:
		var slot := PanelContainer.new()
		slot.name = "Slot_%02d" % (slot_index + 1)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_ARROW
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", _inventory_slot_style)
		slot.gui_input.connect(Callable(self, "_on_inventory_slot_gui_input").bind(slot_index))

		var icon := TextureRect.new()
		icon.name = "SlotIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)

		_inventory_slot_icons.append(icon)
		_inventory_slot_textures.append(null)
		_inventory_slot_scene_paths.append("")
		inventory_slots_grid.add_child(slot)

func _build_inventory_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.96)
	style.border_color = Color(0.28, 0.31, 0.35, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

func _get_inventory_panel_width() -> float:
	return get_viewport().get_visible_rect().size.x / 3.0

func _get_inventory_open_x() -> float:
	var viewport_width := get_viewport().get_visible_rect().size.x
	return viewport_width - _get_inventory_panel_width()

func _get_inventory_hidden_x() -> float:
	return get_viewport().get_visible_rect().size.x

func _refresh_inventory_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := viewport_size.x / 3.0
	var panel_height := viewport_size.y * INVENTORY_HEIGHT_SCALE
	inventory_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_panel.position = Vector2(
		_get_inventory_hidden_x() if not inventory_open else _get_inventory_open_x(),
		viewport_size.y - panel_height
	)
	inventory_panel.size = Vector2(panel_width, panel_height)
	inventory_slots_grid.columns = INVENTORY_COLUMNS
	inventory_slots_grid.add_theme_constant_override("h_separation", 10)
	inventory_slots_grid.add_theme_constant_override("v_separation", 10)

func _find_first_free_inventory_slot() -> int:
	for i in _inventory_slot_textures.size():
		if _inventory_slot_textures[i] == null:
			return i
	return -1

func _set_inventory_slot_content(slot_index: int, scene_path: String, texture: Texture2D) -> void:
	if slot_index < 0 or slot_index >= _inventory_slot_icons.size():
		return
	_inventory_slot_scene_paths[slot_index] = scene_path
	_inventory_slot_textures[slot_index] = texture
	var icon := _inventory_slot_icons[slot_index]
	if icon:
		icon.texture = texture
	var slot := icon.get_parent() if icon else null
	if slot is Control:
		(slot as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if scene_path != "" else Control.CURSOR_ARROW

func _clear_inventory_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _inventory_slot_icons.size():
		return
	_inventory_slot_scene_paths[slot_index] = ""
	_inventory_slot_textures[slot_index] = null
	var icon := _inventory_slot_icons[slot_index]
	if icon:
		icon.texture = null
		var slot := icon.get_parent()
		if slot is Control:
			(slot as Control).mouse_default_cursor_shape = Control.CURSOR_ARROW

func _get_item_grabber() -> ItemGrabber:
	if play_char == null:
		return null
	return play_char.get_node_or_null("ItemGrabber") as ItemGrabber

func is_point_over_inventory_ui(point: Vector2) -> bool:
	if not inventory_open or not inventory_root.visible:
		return false
	return inventory_panel.get_global_rect().has_point(point)

func _instantiate_inventory_item(slot_index: int) -> HoldableItem:
	if slot_index < 0 or slot_index >= _inventory_slot_scene_paths.size():
		return null
	var scene_path := _inventory_slot_scene_paths[slot_index]
	if scene_path == "":
		return null
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		return null
	var item := packed_scene.instantiate() as HoldableItem
	if item == null:
		return null
	var world_root := get_tree().current_scene
	if world_root == null:
		item.queue_free()
		return null
	world_root.add_child(item)
	return item

func try_add_holdable_item(item: HoldableItem) -> bool:
	if item == null:
		return false
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false

	var slot_index := _find_first_free_inventory_slot()
	if slot_index == -1:
		return false

	var scene_path := item.scene_file_path
	if scene_path == "":
		return false
	var icon_texture := item.inventory_icon if item.inventory_icon else DEFAULT_INVENTORY_ICON
	_set_inventory_slot_content(slot_index, scene_path, icon_texture)
	return true

func _try_begin_inventory_slot_drag(slot_index: int) -> void:
	var item := _instantiate_inventory_item(slot_index)
	if item == null:
		return
	var grabber := _get_item_grabber()
	if grabber == null or not grabber.begin_inventory_drag(item):
		item.queue_free()
		return
	_clear_inventory_slot(slot_index)

func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not inventory_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_begin_inventory_slot_drag(slot_index)
		get_viewport().set_input_as_handled()

func _set_inventory_open(value: bool) -> void:
	if inventory_open == value:
		return
	inventory_open = value

	if _inventory_tween and _inventory_tween.is_valid():
		_inventory_tween.kill()

	_refresh_inventory_layout()
	inventory_root.visible = true

	_inventory_tween = create_tween()
	_inventory_tween.set_trans(Tween.TRANS_CUBIC)
	_inventory_tween.set_ease(Tween.EASE_OUT if inventory_open else Tween.EASE_IN)

	var target_x := _get_inventory_open_x() if inventory_open else _get_inventory_hidden_x()
	_inventory_tween.tween_property(inventory_panel, "position:x", target_x, 0.22 if inventory_open else 0.18)
	_inventory_tween.finished.connect(_on_inventory_tween_finished)

func _on_inventory_tween_finished() -> void:
	if not inventory_open:
		inventory_root.visible = false

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
	look_hint_label.text = "RMB look  |  V aim  |  E pickup  |  Tab inventory  |  LMB grab items (free cursor)"

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
	elif event.is_action_pressed(INVENTORY_TOGGLE_ACTION):
		_set_inventory_open(not inventory_open)
		get_viewport().set_input_as_handled()
	elif inventory_open and event.is_action_pressed("ui_cancel"):
		_set_inventory_open(false)
		get_viewport().set_input_as_handled()
#endregion
