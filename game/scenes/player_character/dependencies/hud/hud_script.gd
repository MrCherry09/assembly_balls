extends CanvasLayer

class_name HUD

const INVENTORY_TOGGLE_ACTION: StringName = &"toggle_inventory"
const INVENTORY_PICKUP_ACTION: StringName = &"pickup_holdable_item"
@export var INVENTORY_SLOT_COUNT: int = 30
@export var INVENTORY_COLUMNS: int = 5
@export var INVENTORY_SLOT_SIZE: float = 64.0
@export var INVENTORY_SLOT_SEPARATION: float = 8.0
## Leaves room for the bottom tool hotbar so the panel doesn't overlap it.
@export var INVENTORY_HOTBAR_CLEARANCE: float = 150.0
const DEFAULT_INVENTORY_ICON: Texture2D = preload("res://icon.png")
const INVENTORY_SLOT_SCRIPT: GDScript = preload("res://scenes/player_character/dependencies/hud/inventory_slot.gd")
const VIBRANCY_MATERIAL: ShaderMaterial = preload("res://common/shaders/vibrancy_backdrop.tres")

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
var tool_hotbar: ToolHotbar
var _inventory_tween: Tween
var _inventory_slot_style: StyleBoxFlat
var _inventory_slot_icons: Array[TextureRect] = []
var _inventory_slot_textures: Array[Texture2D] = []
var _inventory_slot_scene_paths: Array[String] = []
## Floating UI drag from the world (slot_index -1) — not in a slot until dropped.
var _floating_drag_active: bool = false
var _floating_drag_data: Dictionary = {}
var _floating_was_dragging: bool = false
## Pause hides inventory without closing it; restored when unpaused.
var _pause_suppressed: bool = false

func _ready() -> void:
	_ensure_inventory_action()
	_ensure_inventory_pickup_action()
	get_viewport().size_changed.connect(_refresh_inventory_layout)
	_setup_inventory_ui()
	_setup_tool_hotbar()
	_setup_outline_stencil.call_deferred()
	_cicle_ui(0)
	_setup_look_hint_label()
	_hide_removed_debug_rows()
	_refresh_inventory_layout()
	inventory_root.visible = false

func _setup_tool_hotbar() -> void:
	tool_hotbar = ToolHotbar.new()
	tool_hotbar.name = "ToolHotbar"
	tool_hotbar.hud = self
	add_child(tool_hotbar)

func _setup_outline_stencil() -> void:
	if not _is_local_hud():
		return
	if get_node_or_null("OutlineStencilOverlay") != null:
		return
	var overlay := OutlineStencilOverlay.new()
	overlay.name = "OutlineStencilOverlay"
	if play_char and play_char.cam:
		overlay.source_camera = play_char.cam
	# Draw under crosshair / inventory / hotbar.
	add_child(overlay)
	move_child(overlay, 0)

func get_selected_hotbar_index() -> int:
	if tool_hotbar == null:
		return 0
	return tool_hotbar.get_selected_index()

func get_selected_tool() -> ToolDefinition:
	if tool_hotbar == null:
		return null
	return tool_hotbar.get_selected_tool()

func is_local_hud() -> bool:
	return _is_local_hud()

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
	_apply_inventory_vibrancy()
	_inventory_slot_style = _build_inventory_slot_style()
	_inventory_slot_icons.clear()
	_inventory_slot_textures.clear()
	_inventory_slot_scene_paths.clear()
	for child in inventory_slots_grid.get_children():
		child.queue_free()

	for slot_index in INVENTORY_SLOT_COUNT:
		var slot := PanelContainer.new()
		slot.set_script(INVENTORY_SLOT_SCRIPT)
		slot.slot_index = slot_index
		slot.hud = self
		slot.name = "Slot_%02d" % (slot_index + 1)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_ARROW
		slot.custom_minimum_size = Vector2(INVENTORY_SLOT_SIZE, INVENTORY_SLOT_SIZE)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.add_theme_stylebox_override("panel", _inventory_slot_style)
		slot.material = VIBRANCY_MATERIAL.duplicate()

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

func _apply_inventory_vibrancy() -> void:
	if inventory_panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.11, 0.45)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_top = 16.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 16.0
	inventory_panel.add_theme_stylebox_override("panel", style)
	inventory_panel.material = VIBRANCY_MATERIAL.duplicate()

func _build_inventory_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.4)
	style.border_color = Color(1, 1, 1, 0.16)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style

func _get_inventory_grid_size() -> Vector2:
	var cols := INVENTORY_COLUMNS
	var rows := int(ceil(float(INVENTORY_SLOT_COUNT) / float(maxi(cols, 1))))
	var sep := INVENTORY_SLOT_SEPARATION
	var grid_w := cols * INVENTORY_SLOT_SIZE + (cols - 1) * sep
	var grid_h := rows * INVENTORY_SLOT_SIZE + (rows - 1) * sep
	return Vector2(grid_w, grid_h)

func _get_inventory_panel_width() -> float:
	# Panel chrome: style margins + inner MarginContainer (24*2) + title row padding.
	var chrome_x := 16.0 * 2.0 + 24.0 * 2.0
	return _get_inventory_grid_size().x + chrome_x

func _get_inventory_panel_height() -> float:
	var chrome_y := 16.0 * 2.0 + 24.0 * 2.0
	var title_row := 48.0
	var sep_under_title := 14.0 + 12.0
	return _get_inventory_grid_size().y + chrome_y + title_row + sep_under_title

func _get_inventory_open_x() -> float:
	var viewport_width := get_viewport().get_visible_rect().size.x
	return viewport_width - _get_inventory_panel_width() - 16.0

func _get_inventory_hidden_x() -> float:
	return get_viewport().get_visible_rect().size.x

func _refresh_inventory_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := _get_inventory_panel_width()
	var panel_height := _get_inventory_panel_height()
	# Sit above the tool hotbar.
	var panel_y := viewport_size.y - panel_height - INVENTORY_HOTBAR_CLEARANCE
	panel_y = maxf(16.0, panel_y)
	inventory_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var target_x := _get_inventory_hidden_x() if not inventory_open else _get_inventory_open_x()
	# Don't fight an in-progress slide tween.
	if _inventory_tween == null or not _inventory_tween.is_running():
		inventory_panel.position = Vector2(target_x, panel_y)
	else:
		inventory_panel.position.y = panel_y
	inventory_panel.size = Vector2(panel_width, panel_height)
	inventory_slots_grid.columns = INVENTORY_COLUMNS
	inventory_slots_grid.add_theme_constant_override("h_separation", int(INVENTORY_SLOT_SEPARATION))
	inventory_slots_grid.add_theme_constant_override("v_separation", int(INVENTORY_SLOT_SEPARATION))
	for child in inventory_slots_grid.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = Vector2(INVENTORY_SLOT_SIZE, INVENTORY_SLOT_SIZE)
	_apply_inventory_pause_visibility()

func _apply_inventory_pause_visibility() -> void:
	if inventory_root == null:
		return
	if _pause_suppressed:
		inventory_root.visible = false
	else:
		inventory_root.visible = inventory_open or (_inventory_tween != null and _inventory_tween.is_running())

func set_pause_suppressed(suppressed: bool) -> void:
	if _pause_suppressed == suppressed:
		return
	_pause_suppressed = suppressed
	if suppressed:
		if _floating_drag_active:
			var drag_type := str(_floating_drag_data.get("type", ""))
			if drag_type == "inventory_slot":
				_place_floating_in_inventory_at_mouse()
			else:
				_spawn_floating_drag_to_world()
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		# World-held items still soft-drop.
		var grabber := _get_item_grabber()
		if grabber and grabber.has_method("force_release_now"):
			grabber.force_release_now()
	else:
		# Snap open inventory to its resting position when unpausing.
		if inventory_open:
			inventory_panel.position.x = _get_inventory_open_x()
	_apply_inventory_pause_visibility()

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

func is_point_over_tool_hotbar(point: Vector2) -> bool:
	return tool_hotbar != null and tool_hotbar.is_point_over(point)

func is_point_over_hud_ui(point: Vector2) -> bool:
	return is_point_over_inventory_ui(point) or is_point_over_tool_hotbar(point)

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
	var items := world_root.get_node_or_null("World3D/Items")
	if items:
		items.add_child(item)
	else:
		world_root.add_child(item)
	return item

func _is_local_hud() -> bool:
	if play_char == null:
		return is_multiplayer_authority()
	if multiplayer.has_multiplayer_peer():
		return play_char.is_multiplayer_authority()
	return true

func try_add_tool_item(item: Node) -> bool:
	if not _is_local_hud() or tool_hotbar == null:
		return false
	return tool_hotbar.try_add_tool(item)

func try_add_tool_item_at_point(item: Node, point: Vector2) -> bool:
	if not _is_local_hud() or tool_hotbar == null:
		return false
	return tool_hotbar.try_add_tool_at_point(item, point)

func try_add_holdable_item(item: HoldableItem) -> bool:
	if item is ToolItem:
		return try_add_tool_item(item)
	return stow_holdable_item(item) >= 0

## Prefer an empty slot under the cursor; otherwise first free slot.
func try_add_holdable_item_at_point(item: HoldableItem, point: Vector2) -> bool:
	if item is ToolItem:
		return try_add_tool_item_at_point(item, point)
	return stow_holdable_item(item, point) >= 0

## Puts a world item into inventory. Returns the slot index, or -1 on failure.
func stow_holdable_item(item: HoldableItem, point: Vector2 = Vector2(INF, INF)) -> int:
	if item == null or not _is_local_hud():
		return -1
	var slot_index := -1
	if point.x < INF:
		slot_index = find_inventory_slot_at_point(point)
		if slot_index >= 0 and _inventory_slot_scene_paths[slot_index] != "":
			slot_index = -1
	if slot_index < 0:
		slot_index = _find_first_free_inventory_slot()
	if slot_index < 0:
		return -1
	if not _put_holdable_in_slot(item, slot_index):
		return -1
	return slot_index

func has_free_inventory_slot() -> bool:
	return _find_first_free_inventory_slot() >= 0

func find_inventory_slot_at_point(point: Vector2) -> int:
	if not inventory_open or not inventory_root.visible:
		return -1
	for i in _inventory_slot_icons.size():
		var icon := _inventory_slot_icons[i]
		if icon == null:
			continue
		var slot := icon.get_parent() as Control
		if slot and slot.get_global_rect().has_point(point):
			return i
	return -1

func _put_holdable_in_slot(item: HoldableItem, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _inventory_slot_icons.size():
		return false
	if item is ToolItem:
		return false
	var scene_path := item.get_spawn_scene_path() if item.has_method("get_spawn_scene_path") else item.scene_file_path
	if scene_path == "":
		return false
	var icon_texture := item.inventory_icon if item.inventory_icon else DEFAULT_INVENTORY_ICON
	_set_inventory_slot_content(slot_index, scene_path, icon_texture)
	return true

## Start icon UI drag without occupying a slot until drop (mirrors drag-out).
func begin_floating_inventory_drag(scene_path: String, texture: Texture2D) -> bool:
	if not _is_local_hud() or not inventory_open:
		return false
	if scene_path == "" or not has_free_inventory_slot():
		return false
	if is_tool_scene_path(scene_path):
		return false
	if inventory_panel == null:
		return false

	var tex: Texture2D = texture if texture else DEFAULT_INVENTORY_ICON
	_floating_drag_data = {
		"type": "inventory_slot",
		"slot_index": -1,
		"texture": tex,
		"scene_path": scene_path,
	}
	_floating_drag_active = true
	_floating_was_dragging = true

	var preview := TextureRect.new()
	preview.texture = tex
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(INVENTORY_SLOT_SIZE, INVENTORY_SLOT_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.7)

	var preview_root := Control.new()
	preview_root.add_child(preview)
	preview.position = Vector2(-INVENTORY_SLOT_SIZE * 0.5, -INVENTORY_SLOT_SIZE * 0.5)
	inventory_panel.force_drag(_floating_drag_data, preview_root)
	return true

func begin_floating_tool_drag(scene_path: String, texture: Texture2D, tool_def: ToolDefinition = null) -> bool:
	if not _is_local_hud() or tool_hotbar == null:
		return false
	if scene_path == "":
		return false
	var def := tool_def
	if def == null:
		def = get_tool_definition_for_scene_path(scene_path, texture)
	if def == null:
		return false
	var tex: Texture2D = texture if texture else (def.icon if def.icon else ToolHotbar.DEFAULT_ICON)
	if def.icon == null:
		def.icon = tex
	_floating_drag_data = {
		"type": "tool_slot",
		"slot_index": -1,
		"texture": tex,
		"scene_path": scene_path,
		"tool_def": def,
	}
	_floating_drag_active = true
	_floating_was_dragging = true

	var preview := TextureRect.new()
	preview.texture = tex
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(ToolHotbar.ICON_SIZE, ToolHotbar.ICON_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.7)

	var preview_root := Control.new()
	preview_root.add_child(preview)
	preview.position = Vector2(-ToolHotbar.ICON_SIZE * 0.5, -ToolHotbar.ICON_SIZE * 0.5)
	tool_hotbar.force_drag(_floating_drag_data, preview_root)
	return true

func clear_floating_drag_state() -> void:
	_floating_drag_active = false
	_floating_drag_data.clear()
	_floating_was_dragging = false

func is_tool_scene_path(scene_path: String) -> bool:
	return get_tool_definition_for_scene_path(scene_path) != null

func get_tool_definition_for_scene_path(scene_path: String, fallback_texture: Texture2D = null) -> ToolDefinition:
	if scene_path == "":
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	if not (node is ToolItem):
		node.queue_free()
		return null
	var def := (node as ToolItem).get_tool_definition()
	if def and def.icon == null and fallback_texture:
		def.icon = fallback_texture
	node.queue_free()
	return def

func place_floating_drag_in_slot(slot_index: int, scene_path: String, texture: Texture2D) -> void:
	if slot_index < 0 or slot_index >= _inventory_slot_scene_paths.size():
		return
	if is_tool_scene_path(scene_path):
		_spawn_floating_drag_to_world()
		return
	var existing_path: String = _inventory_slot_scene_paths[slot_index]
	var existing_tex: Texture2D = _inventory_slot_textures[slot_index]
	if existing_path != "":
		var free_index := _find_first_free_inventory_slot()
		if free_index < 0:
			return
		_set_inventory_slot_content(free_index, existing_path, existing_tex)
	_set_inventory_slot_content(slot_index, scene_path, texture if texture else DEFAULT_INVENTORY_ICON)
	clear_floating_drag_state()

func _spawn_floating_drag_to_world() -> void:
	if _floating_drag_data.is_empty():
		clear_floating_drag_state()
		return
	var scene_path: String = str(_floating_drag_data.get("scene_path", ""))
	clear_floating_drag_state()
	if scene_path == "":
		return
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	var grabber := _get_item_grabber()
	if grabber == null:
		return
	if WorldNet and WorldNet.is_net_active():
		grabber.begin_net_inventory_drag(scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var item := packed.instantiate() as HoldableItem
	if item == null:
		return
	item.set_spawn_scene_path(scene_path)
	var world_root := get_tree().current_scene
	var items := world_root.get_node_or_null("World3D/Items") if world_root else null
	if items:
		items.add_child(item)
	elif world_root:
		world_root.add_child(item)
	else:
		item.queue_free()
		return
	if not grabber.begin_inventory_drag(item):
		item.queue_free()

func _place_floating_in_inventory_at_mouse() -> void:
	if _floating_drag_data.is_empty():
		clear_floating_drag_state()
		return
	var scene_path: String = str(_floating_drag_data.get("scene_path", ""))
	if is_tool_scene_path(scene_path):
		_spawn_floating_drag_to_world()
		return
	var texture_variant: Variant = _floating_drag_data.get("texture", null)
	var texture: Texture2D = texture_variant as Texture2D
	var point := get_viewport().get_mouse_position()
	var slot_index := find_inventory_slot_at_point(point)
	if slot_index < 0 or _inventory_slot_scene_paths[slot_index] != "":
		slot_index = _find_first_free_inventory_slot()
	if slot_index < 0 or scene_path == "":
		_spawn_floating_drag_to_world()
		return
	place_floating_drag_in_slot(slot_index, scene_path, texture)

func _update_floating_inventory_drag() -> void:
	if not _floating_drag_active:
		_floating_was_dragging = false
		return
	var dragging := get_viewport().gui_is_dragging()
	if _floating_was_dragging and not dragging:
		# Drag ended without a successful slot drop.
		var mouse := get_viewport().get_mouse_position()
		var drag_type := str(_floating_drag_data.get("type", ""))
		if drag_type == "inventory_slot" and is_point_over_inventory_ui(mouse):
			_place_floating_in_inventory_at_mouse()
		elif drag_type == "tool_slot" and tool_hotbar and tool_hotbar.place_tool_drag_data_at_point(mouse, _floating_drag_data):
			clear_floating_drag_state()
		else:
			_spawn_floating_drag_to_world()
		return
	_floating_was_dragging = dragging
	if dragging and not is_point_over_hud_ui(get_viewport().get_mouse_position()):
		_spawn_floating_drag_to_world()

func add_inventory_item_from_net(scene_path: String, icon_path: String) -> bool:
	if not _is_local_hud():
		return false
	if scene_path == "":
		return false
	
	var packed = load(scene_path) as PackedScene
	if packed:
		var item = packed.instantiate()
		if item is ToolItem:
			var added = try_add_tool_item(item)
			item.queue_free()
			if added:
				return true
			_floating_drag_data = {
				"type": "tool_slot",
				"slot_index": -1,
				"texture": DEFAULT_INVENTORY_ICON,
				"scene_path": scene_path,
			}
			_spawn_floating_drag_to_world()
			return false
		else:
			item.queue_free()
	
	var slot_index := _find_first_free_inventory_slot()
	if slot_index == -1:
		return false
	var icon_texture: Texture2D = DEFAULT_INVENTORY_ICON
	if icon_path != "":
		var loaded := load(icon_path)
		if loaded is Texture2D:
			icon_texture = loaded
	_set_inventory_slot_content(slot_index, scene_path, icon_texture)
	return true

func begin_floating_drag_from_net(scene_path: String, icon_path: String) -> void:
	if not _is_local_hud():
		return
	var icon_texture: Texture2D = DEFAULT_INVENTORY_ICON
	if icon_path != "":
		var loaded := load(icon_path)
		if loaded is Texture2D:
			icon_texture = loaded
	if is_tool_scene_path(scene_path):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			begin_floating_tool_drag(scene_path, icon_texture)
		else:
			var def := get_tool_definition_for_scene_path(scene_path, icon_texture)
			if def and tool_hotbar:
				tool_hotbar.try_add_tool_definition(def, scene_path)
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		begin_floating_inventory_drag(scene_path, icon_texture)
	else:
		# LMB already released — just stow.
		var slot_index := _find_first_free_inventory_slot()
		if slot_index >= 0:
			_set_inventory_slot_content(slot_index, scene_path, icon_texture)

func _try_begin_inventory_slot_drag(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _inventory_slot_scene_paths.size():
		return
	var scene_path := _inventory_slot_scene_paths[slot_index]
	if scene_path == "":
		return
	var grabber := _get_item_grabber()
	if grabber == null:
		return
	if WorldNet and WorldNet.is_net_active():
		grabber.begin_net_inventory_drag(scene_path)
		_clear_inventory_slot(slot_index)
		return
	var item := _instantiate_inventory_item(slot_index)
	if item == null:
		return
	if not grabber.begin_inventory_drag(item):
		item.queue_free()
		return
	_clear_inventory_slot(slot_index)


func _set_inventory_open(value: bool) -> void:
	if inventory_open == value:
		return
	var opening := value
	inventory_open = value

	if _inventory_tween and _inventory_tween.is_valid():
		_inventory_tween.kill()

	# Size/Y layout without snapping X to the destination (that killed the slide).
	_refresh_inventory_layout()
	if not _pause_suppressed:
		inventory_root.visible = true

	if opening:
		inventory_panel.position.x = _get_inventory_hidden_x()
	else:
		inventory_panel.position.x = _get_inventory_open_x()

	var target_x := _get_inventory_open_x() if opening else _get_inventory_hidden_x()
	_inventory_tween = create_tween()
	_inventory_tween.set_trans(Tween.TRANS_CUBIC)
	_inventory_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_inventory_tween.tween_property(inventory_panel, "position:x", target_x, 0.22 if opening else 0.18)
	_inventory_tween.finished.connect(_on_inventory_tween_finished)

func _on_inventory_tween_finished() -> void:
	_apply_inventory_pause_visibility()

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
	look_hint_label.text = "RMB look  |  V aim  |  E pickup  |  Tab inventory  |  1-9 / scroll tools  |  LMB grab items (free cursor)"

	look_hint_label.add_theme_font_size_override("font_size", 18)
	look_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	look_hint_label.add_theme_constant_override("outline_size", 4)
	add_child(look_hint_label)

func _process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not _is_local_hud():
		if visible:
			hide()
		return
	if not visible:
		show()
	_sync_pause_suppressed()
	if tool_hotbar:
		tool_hotbar.visible = true
	_update_floating_inventory_drag()
	var outline := get_node_or_null("OutlineStencilOverlay") as OutlineStencilOverlay
	if outline == null and _is_local_hud():
		_setup_outline_stencil()
	elif outline and play_char and play_char.cam and outline.source_camera != play_char.cam:
		outline.source_camera = play_char.cam
	display_current_FPS()
	display_properties()
	if look_hint_label and not look_hint_label.visible:
		look_hint_label.visible = true

func _sync_pause_suppressed() -> void:
	var blocked := play_char != null and play_char.is_gameplay_blocked()
	if blocked != _pause_suppressed:
		set_pause_suppressed(blocked)

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
	if not _is_local_hud():
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
		look_hint_label.visible = _is_local_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_hud():
		return
	# While paused, keep inventory state but don't toggle/close it here.
	if play_char and play_char.is_gameplay_blocked():
		return
	if event.is_action_pressed("cicle_player_hud"):
		_cicle_ui()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(INVENTORY_TOGGLE_ACTION):
		_set_inventory_open(not inventory_open)
		get_viewport().set_input_as_handled()
#endregion
