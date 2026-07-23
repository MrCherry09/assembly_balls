extends Control
class_name ToolHotbar

signal selection_changed(index: int, tool: ToolDefinition)

const SLOT_COUNT: int = 9
const SLOT_SIZE: float = 64.0
const SELECTED_SCALE: float = 1.1
const DEFAULT_ICON: Texture2D = preload("res://icon.png")

@export var hud: HUD

var selected_index: int = 0
var _tools: Array[ToolDefinition] = []
var _slots: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _slot_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _panel: PanelContainer
var _slots_row: HBoxContainer
var _select_tween: Tween
var _name_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ensure_input_actions()
	_build_styles()
	_build_ui()
	_seed_placeholder_loadout()
	_refresh_all_slots()
	_apply_selection_visuals(false)
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()

func get_selected_index() -> int:
	return selected_index

func get_selected_tool() -> ToolDefinition:
	if selected_index < 0 or selected_index >= _tools.size():
		return null
	return _tools[selected_index]

func get_tool_at(index: int) -> ToolDefinition:
	if index < 0 or index >= _tools.size():
		return null
	return _tools[index]

func set_tool(index: int, tool: ToolDefinition) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	while _tools.size() < SLOT_COUNT:
		_tools.append(null)
	_tools[index] = tool
	_refresh_slot(index)

func select_index(index: int, animate: bool = true) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	if selected_index == index:
		if animate:
			_punch_selected()
		return
	selected_index = index
	_apply_selection_visuals(animate)
	selection_changed.emit(selected_index, get_selected_tool())

func cycle(delta: int) -> void:
	select_index(wrapi(selected_index + delta, 0, SLOT_COUNT))

func is_point_over(point: Vector2) -> bool:
	if not visible or _panel == null:
		return false
	return _panel.get_global_rect().has_point(point)

func _unhandled_input(event: InputEvent) -> void:
	if hud and not hud.is_local_hud():
		return
	if hud and hud.play_char and hud.play_char.is_gameplay_blocked():
		return

	for i in SLOT_COUNT:
		var action := _slot_action(i)
		if event.is_action_pressed(action):
			select_index(i)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"hotbar_next"):
		cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_prev"):
		cycle(1)
		get_viewport().set_input_as_handled()

func _ensure_input_actions() -> void:
	var keycodes: Array[Key] = [
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	]
	for i in SLOT_COUNT:
		var action := _slot_action(i)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		var key_event := InputEventKey.new()
		key_event.keycode = keycodes[i]
		key_event.physical_keycode = keycodes[i]
		InputMap.action_add_event(action, key_event)

	_bind_wheel_action(&"hotbar_next", MOUSE_BUTTON_WHEEL_UP)
	_bind_wheel_action(&"hotbar_prev", MOUSE_BUTTON_WHEEL_DOWN)

func _bind_wheel_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = button
	InputMap.action_add_event(action, wheel)

func _slot_action(index: int) -> StringName:
	return StringName("hotbar_%d" % (index + 1))

func _build_styles() -> void:
	_slot_style = StyleBoxFlat.new()
	_slot_style.bg_color = Color(0.09, 0.10, 0.12, 0.96)
	_slot_style.border_color = Color(0.28, 0.31, 0.35, 1.0)
	_slot_style.set_border_width_all(2)
	_slot_style.set_corner_radius_all(8)
	_slot_style.set_content_margin_all(6)

	_selected_style = _slot_style.duplicate()
	_selected_style.bg_color = Color(0.16, 0.12, 0.22, 0.98)
	_selected_style.border_color = Color(0.72, 0.58, 0.92, 1.0)
	_selected_style.set_border_width_all(3)
	_selected_style.shadow_color = Color(0.45, 0.28, 0.7, 0.45)
	_selected_style.shadow_size = 8

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "HotbarPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.24, 0.18, 0.31, 0.88)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(10)
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 10
	panel_style.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.name = "SelectedToolName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	_slots_row = HBoxContainer.new()
	_slots_row.name = "SlotsRow"
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_row.add_theme_constant_override("separation", 8)
	_slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_slots_row)

	_slots.clear()
	_icons.clear()
	_key_labels.clear()
	for i in SLOT_COUNT:
		var slot := PanelContainer.new()
		slot.name = "ToolSlot_%d" % (i + 1)
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.add_theme_stylebox_override("panel", _slot_style)
		slot.pivot_offset = Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		_slots_row.add_child(slot)

		var stack := Control.new()
		stack.custom_minimum_size = Vector2(SLOT_SIZE - 12.0, SLOT_SIZE - 12.0)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stack)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)

		var key_label := Label.new()
		key_label.name = "KeyLabel"
		key_label.text = str(i + 1)
		key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		key_label.position = Vector2(4, 2)
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_outline_color", Color.BLACK)
		key_label.add_theme_constant_override("outline_size", 3)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(key_label)

		_slots.append(slot)
		_icons.append(icon)
		_key_labels.append(key_label)

func _seed_placeholder_loadout() -> void:
	_tools.clear()
	_tools.resize(SLOT_COUNT)
	_tools[0] = _make_tool(&"hands", "Hands", DEFAULT_ICON)
	_tools[1] = _make_tool(&"axe", "Axe", DEFAULT_ICON)
	_tools[2] = _make_tool(&"pickaxe", "Pickaxe", DEFAULT_ICON)
	for i in range(3, SLOT_COUNT):
		_tools[i] = null

func _make_tool(id: StringName, tool_name: String, icon: Texture2D) -> ToolDefinition:
	var def := ToolDefinition.new()
	def.id = id
	def.display_name = tool_name
	def.icon = icon
	return def

func _refresh_all_slots() -> void:
	for i in SLOT_COUNT:
		_refresh_slot(i)
	_update_name_label()

func _refresh_slot(index: int) -> void:
	if index < 0 or index >= _icons.size():
		return
	var def := get_tool_at(index)
	if def and def.icon:
		_icons[index].texture = def.icon
		_icons[index].modulate = Color.WHITE
	elif def:
		_icons[index].texture = DEFAULT_ICON
		_icons[index].modulate = Color.WHITE
	else:
		_icons[index].texture = null
		_icons[index].modulate = Color(1, 1, 1, 0.35)

func _apply_selection_visuals(animate: bool) -> void:
	for i in _slots.size():
		var selected := i == selected_index
		_slots[i].add_theme_stylebox_override("panel", _selected_style if selected else _slot_style)
		if selected:
			if animate:
				_slots[i].scale = Vector2.ONE * 0.92
				if _select_tween and _select_tween.is_valid():
					_select_tween.kill()
				_select_tween = create_tween()
				_select_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				_select_tween.tween_property(_slots[i], "scale", Vector2.ONE * SELECTED_SCALE, 0.18)
			else:
				_slots[i].scale = Vector2.ONE * SELECTED_SCALE
		else:
			_slots[i].scale = Vector2.ONE
	_update_name_label()

func _punch_selected() -> void:
	if selected_index < 0 or selected_index >= _slots.size():
		return
	var slot := _slots[selected_index]
	if _select_tween and _select_tween.is_valid():
		_select_tween.kill()
	_select_tween = create_tween()
	_select_tween.tween_property(slot, "scale", Vector2.ONE * (SELECTED_SCALE * 1.08), 0.06)
	_select_tween.tween_property(slot, "scale", Vector2.ONE * SELECTED_SCALE, 0.1).set_trans(Tween.TRANS_SINE)

func _update_name_label() -> void:
	if _name_label == null:
		return
	var def := get_selected_tool()
	_name_label.text = def.display_name if def else ""

func _refresh_layout() -> void:
	if _panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _panel.get_combined_minimum_size()
	_panel.size = panel_size
	_panel.position = Vector2(
		(viewport_size.x - panel_size.x) * 0.5,
		viewport_size.y - panel_size.y - 18.0
	)

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if hud and hud.play_char and hud.play_char.is_gameplay_blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_index(index)
		accept_event()
