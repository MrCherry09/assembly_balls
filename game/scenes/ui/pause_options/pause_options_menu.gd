extends Control
class_name PauseOptionsMenu
## Gray menu card over the pause vibrancy backdrop; remappable gameplay inputs.

signal closed

const PAUSE_THEME: Theme = preload("res://common/themes/main_theme/main_theme.tres")
const MAIN_MENU_GRAY := Color(0.0901961, 0.0901961, 0.0901961, 1)

@onready var _back_button: Button = %BackButton
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _tabs: TabContainer = %MasterOptionsMenu


func _ready() -> void:
	visible = false
	_apply_menu_panel_style()
	_tabs.theme = PAUSE_THEME
	_apply_tab_chrome()
	_configure_controls_tab.call_deferred()
	if not _back_button.pressed.is_connected(_on_back_pressed):
		_back_button.pressed.connect(_on_back_pressed)


func open() -> void:
	show()
	_configure_controls_tab()
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _on_back_pressed() -> void:
	close()


func has_blocking_overlay() -> bool:
	return _has_visible_overlaid_window(self)


func _has_visible_overlaid_window(node: Node) -> bool:
	if node is OverlaidWindow and (node as Control).visible and node != self:
		return true
	for child in node.get_children():
		if _has_visible_overlaid_window(child):
			return true
	return false


func _apply_menu_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = MAIN_MENU_GRAY
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	_menu_panel.add_theme_stylebox_override("panel", style)


func _apply_tab_chrome() -> void:
	if _tabs == null:
		return
	_tabs.add_theme_stylebox_override("panel", _flat_style(Color(1, 1, 1, 0), 8))
	_tabs.add_theme_stylebox_override("tab_selected", _tab_style(true))
	_tabs.add_theme_stylebox_override("tab_hovered", _tab_style(false))
	_tabs.add_theme_stylebox_override("tab_unselected", _tab_style(false))
	_tabs.add_theme_stylebox_override("tab_disabled", _tab_style(false))
	_tabs.add_theme_stylebox_override("tab_focus", StyleBoxEmpty.new())
	_tabs.add_theme_color_override("font_selected_color", Color(0.85, 0.9, 0.996, 1.0))
	_tabs.add_theme_color_override("font_hovered_color", Color(1.0, 1.0, 1.0, 1.0))
	_tabs.add_theme_color_override("font_unselected_color", Color(0.85, 0.9, 0.996, 0.65))


func _flat_style(color: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(margin)
	return style


func _tab_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.08 if selected else 0.0)
	style.border_color = Color(1, 1, 1, 0.25 if selected else 0.0)
	style.border_width_bottom = 2 if selected else 0
	style.content_margin_left = 16
	style.content_margin_top = 10
	style.content_margin_right = 16
	style.content_margin_bottom = 10
	return style


func _configure_controls_tab() -> void:
	var list := _tabs.find_child("InputActionsList", true, false) as InputActionsList
	if list == null:
		return

	list.input_icon_mapper = null
	list.show_all_actions = false
	list.show_built_in_actions = false
	list.vertical = true
	list.action_groups = 2
	list.action_group_names = ["Primary", "Secondary"]
	# Non-zero Y keeps rows from vertically expanding inside the scroll area.
	list.button_minimum_size = Vector2(0, 40)
	list.capitalize_action_names = false
	list.input_action_names = GameInput.REMAP_ACTIONS.duplicate()
	list.readable_action_names = GameInput.REMAP_LABELS.duplicate()

	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 320)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list.follow_focus = true

	var controls_page := _tabs.find_child("Controls", true, false) as MarginContainer
	if controls_page:
		controls_page.add_theme_constant_override("margin_left", 8)
		controls_page.add_theme_constant_override("margin_right", 8)
		controls_page.add_theme_constant_override("margin_top", 4)
		controls_page.add_theme_constant_override("margin_bottom", 4)

	var mapping := list.get_parent() as VBoxContainer
	if mapping:
		mapping.alignment = BoxContainer.ALIGNMENT_BEGIN
		mapping.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mapping.add_theme_constant_override("separation", 10)

	# Rebuild, then force compact row layout (ScrollContainer + expand flags otherwise stretch rows).
	list._set_action_box_container_size()
	list._build_assigned_input_events()
	list._build_ui_list()
	_fix_input_list_layout(list)
	_style_controls_buttons(list.get_parent())


func _fix_input_list_layout(list: InputActionsList) -> void:
	var parent_box := list.get_node_or_null("%ParentBoxContainer") as BoxContainer
	if parent_box == null:
		return
	parent_box.vertical = true
	parent_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Critical: do not expand to fill the scroll viewport or rows stretch apart.
	parent_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent_box.add_theme_constant_override("separation", 8)

	for row in parent_box.get_children():
		if row == list.get_node_or_null("%ActionBoxContainer"):
			continue
		if row is BoxContainer:
			var box := row as BoxContainer
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			box.add_theme_constant_override("separation", 12)
			var child_index := 0
			for child in box.get_children():
				if child is Label:
					var label := child as Label
					label.custom_minimum_size = Vector2(220, 40)
					label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				elif child is Button:
					var button := child as Button
					button.custom_minimum_size = Vector2(140, 40)
					button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					button.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _style_controls_buttons(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Button:
			_style_plain_button(child as Button)
		_style_controls_buttons(child)


func _style_plain_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0)
	normal.border_color = Color(0.85, 0.9, 0.996, 0.55)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_top = 6
	normal.content_margin_right = 10
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.06)
	hover.border_color = Color(0.85, 0.9, 0.996, 0.9)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 1, 1, 0.12)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0)
	disabled.border_color = Color(0.85, 0.9, 0.996, 0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.85, 0.9, 0.996, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.85, 0.9, 0.996, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.85, 0.9, 0.996, 0.35))
	button.icon = null
