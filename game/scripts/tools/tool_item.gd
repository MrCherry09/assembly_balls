extends HoldableItem
class_name ToolItem

@export_group("Tool Properties")
@export var tool_id: StringName = &""
@export var tool_name: String = ""

func get_tool_definition() -> ToolDefinition:
	var def := ToolDefinition.new()
	def.id = tool_id
	def.display_name = tool_name
	def.icon = inventory_icon
	return def
