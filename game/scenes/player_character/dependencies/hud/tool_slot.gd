extends PanelContainer
class_name ToolSlot

var slot_index: int = -1
var hotbar: ToolHotbar = null

func _get_drag_data(at_position: Vector2) -> Variant:
	if hotbar:
		return hotbar._on_slot_get_drag_data(slot_index, at_position)
	return null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if hotbar:
		return hotbar._on_slot_can_drop_data(slot_index, at_position, data)
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if hotbar:
		hotbar._on_slot_drop_data(slot_index, at_position, data)
