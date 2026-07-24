extends Control
class_name ToolHotbar

signal selection_changed(index: int, tool: ToolDefinition)

const SLOT_COUNT: int = 9
const CARD_WIDTH: float = 96.0
const ICON_SIZE: float = 64.0
const SELECTED_SCALE: float = 1.08
const DEFAULT_ICON: Texture2D = preload("res://icon.png")
const VIBRANCY_MATERIAL: ShaderMaterial = preload("res://common/shaders/vibrancy_backdrop.tres")

@export var hud: HUD

var selected_index: int = 0
var _tools: Array[ToolDefinition] = []
var _cards: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _name_labels: Array[Label] = []
var _card_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _slots_row: HBoxContainer
var _select_tween: Tween

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
	if not visible:
		return false
	for card in _cards:
		if card.get_global_rect().has_point(point):
			return true
	return false

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
	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = Color(0.1, 0.1, 0.11, 0.42)
	_card_style.border_color = Color(1, 1, 1, 0.18)
	_card_style.set_border_width_all(1)
	_card_style.set_corner_radius_all(14)
	_card_style.set_content_margin_all(10)

	_selected_style = _card_style.duplicate()
	_selected_style.bg_color = Color(0.18, 0.18, 0.2, 0.55)
	_selected_style.border_color = Color(1, 1, 1, 0.92)
	_selected_style.set_border_width_all(2)
	_selected_style.shadow_color = Color(0, 0, 0, 0.4)
	_selected_style.shadow_size = 8

func _make_vibrancy_material() -> ShaderMaterial:
	return VIBRANCY_MATERIAL.duplicate() as ShaderMaterial

func _build_ui() -> void:
	_slots_row = HBoxContainer.new()
	_slots_row.name = "SlotsRow"
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_row.add_theme_constant_override("separation", 12)
	_slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots_row)

	_cards.clear()
	_icons.clear()
	_key_labels.clear()
	_name_labels.clear()

	for i in SLOT_COUNT:
		var card := PanelContainer.new()
		card.name = "ToolCard_%d" % (i + 1)
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_theme_stylebox_override("panel", _card_style)
		card.material = _make_vibrancy_material()
		card.gui_input.connect(_on_slot_gui_input.bind(i))
		_slots_row.add_child(card)

		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)

		var icon_wrap := Control.new()
		icon_wrap.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon_wrap)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(icon)

		var key_label := Label.new()
		key_label.name = "KeyLabel"
		key_label.text = str(i + 1)
		key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		key_label.position = Vector2(0, -2)
		key_label.add_theme_font_size_override("font_size", 13)
		key_label.add_theme_color_override("font_outline_color", Color.BLACK)
		key_label.add_theme_constant_override("outline_size", 3)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(key_label)

		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size = Vector2(CARD_WIDTH - 16.0, 0.0)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 3)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_label)

		# Pivot after layout; updated in refresh.
		card.resized.connect(_update_card_pivot.bind(card))
		_cards.append(card)
		_icons.append(icon)
		_key_labels.append(key_label)
		_name_labels.append(name_label)

func _update_card_pivot(card: Control) -> void:
	card.pivot_offset = card.size * 0.5

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

	if index < _name_labels.size():
		_name_labels[index].text = def.display_name if def else "Empty"

func _apply_selection_visuals(animate: bool) -> void:
	for i in _cards.size():
		var selected := i == selected_index
		_cards[i].add_theme_stylebox_override("panel", _selected_style if selected else _card_style)
		_update_card_pivot(_cards[i])
		if selected:
			if animate:
				_cards[i].scale = Vector2.ONE * 0.94
				if _select_tween and _select_tween.is_valid():
					_select_tween.kill()
				_select_tween = create_tween()
				_select_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				_select_tween.tween_property(_cards[i], "scale", Vector2.ONE * SELECTED_SCALE, 0.18)
			else:
				_cards[i].scale = Vector2.ONE * SELECTED_SCALE
		else:
			_cards[i].scale = Vector2.ONE

func _punch_selected() -> void:
	if selected_index < 0 or selected_index >= _cards.size():
		return
	var card := _cards[selected_index]
	if _select_tween and _select_tween.is_valid():
		_select_tween.kill()
	_select_tween = create_tween()
	_select_tween.tween_property(card, "scale", Vector2.ONE * (SELECTED_SCALE * 1.06), 0.06)
	_select_tween.tween_property(card, "scale", Vector2.ONE * SELECTED_SCALE, 0.1).set_trans(Tween.TRANS_SINE)

func _refresh_layout() -> void:
	if _slots_row == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_slots_row.reset_size()
	var row_size := _slots_row.get_combined_minimum_size()
	_slots_row.size = row_size
	_slots_row.position = Vector2(
		(viewport_size.x - row_size.x) * 0.5,
		viewport_size.y - row_size.y - 16.0
	)
	for card in _cards:
		_update_card_pivot(card)

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if hud and hud.play_char and hud.play_char.is_gameplay_blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_index(index)
		accept_event()
