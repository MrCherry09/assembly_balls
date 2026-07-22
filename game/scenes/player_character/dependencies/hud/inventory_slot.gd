extends PanelContainer

var slot_index: int = -1
var hud: HUD = null

var is_dragging_this_slot: bool = false
var drag_preview_ctrl: Control = null
var current_drag_data: Dictionary = {}

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	if is_dragging_this_slot:
		if not hud.is_point_over_inventory_ui(get_global_mouse_position()):
			# Mouse left the inventory! Spawn immediately.
			hud._try_begin_inventory_slot_drag(slot_index)
			
			if is_instance_valid(drag_preview_ctrl):
				drag_preview_ctrl.queue_free()
			
			# Invalidate the drag data so it can't be dropped back into a slot
			current_drag_data["type"] = "cancelled"
			
			is_dragging_this_slot = false
			set_process(false)

func _get_drag_data(at_position: Vector2) -> Variant:
	if hud == null or slot_index < 0:
		return null
	var path = hud._inventory_slot_scene_paths[slot_index]
	if path == "":
		return null
	var tex = hud._inventory_slot_textures[slot_index]
	
	is_dragging_this_slot = true
	set_process(true)
	
	var preview := TextureRect.new()
	preview.texture = tex
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = size
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.7)
	
	drag_preview_ctrl = Control.new()
	drag_preview_ctrl.add_child(preview)
	preview.position = -0.5 * size
	set_drag_preview(drag_preview_ctrl)
	
	current_drag_data = {"type": "inventory_slot", "slot_index": slot_index, "texture": tex, "scene_path": path}
	return current_drag_data

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "inventory_slot":
		return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "inventory_slot":
		var source_index: int = data["slot_index"]
		var source_path: String = data["scene_path"]
		var source_tex: Texture2D = data["texture"]
		
		if source_index != slot_index:
			var my_path: String = hud._inventory_slot_scene_paths[slot_index]
			var my_tex: Texture2D = hud._inventory_slot_textures[slot_index]
			
			hud._set_inventory_slot_content(slot_index, source_path, source_tex)
			hud._set_inventory_slot_content(source_index, my_path, my_tex)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if is_dragging_this_slot:
			is_dragging_this_slot = false
			set_process(false)
			if not get_viewport().gui_is_drag_successful():
				if not hud.is_point_over_inventory_ui(get_global_mouse_position()):
					hud._try_begin_inventory_slot_drag(slot_index)
