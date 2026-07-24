extends Node
## Registers gameplay InputMap actions before menus / AppConfig load remaps.

const LOOK_ACTION: StringName = &"play_char_look_action"
const ATTACK_ACTION: StringName = &"play_char_attack_action"

## Readable labels for the pause options Controls tab (ordered).
const REMAP_ACTIONS: Array[StringName] = [
	&"play_char_move_forward_action",
	&"play_char_move_backward_action",
	&"play_char_move_left_ation",
	&"play_char_move_right_action",
	&"play_char_jump_action",
	&"play_char_run_action",
	&"play_char_crouch_action",
	ATTACK_ACTION,
	LOOK_ACTION,
	&"play_char_aim_action",
	&"play_char_zoom_action",
	&"pickup_holdable_item",
	&"toggle_inventory",
]

const REMAP_LABELS: Array[String] = [
	"Move Forward",
	"Move Backward",
	"Move Left",
	"Move Right",
	"Jump",
	"Run",
	"Crouch",
	"Attack / Grab",
	"Look",
	"Aim",
	"Zoom",
	"Pickup",
	"Inventory",
]


func _ready() -> void:
	_ensure_defaults()


func _ensure_defaults() -> void:
	_ensure_key_action(&"play_char_move_forward_action", [KEY_W, KEY_UP])
	_ensure_key_action(&"play_char_move_backward_action", [KEY_S, KEY_DOWN])
	_ensure_key_action(&"play_char_move_left_ation", [KEY_A, KEY_LEFT])
	_ensure_key_action(&"play_char_move_right_action", [KEY_D, KEY_RIGHT])
	_ensure_key_action(&"play_char_jump_action", [KEY_SPACE])
	_ensure_key_action(&"play_char_run_action", [KEY_SHIFT])
	_ensure_key_action(&"play_char_crouch_action", [KEY_CTRL])
	_ensure_key_action(&"play_char_aim_action", [KEY_V])
	_ensure_key_action(&"play_char_zoom_action", [KEY_Z])
	_ensure_mouse_action(ATTACK_ACTION, MOUSE_BUTTON_LEFT)
	_ensure_mouse_action(LOOK_ACTION, MOUSE_BUTTON_RIGHT)
	_ensure_key_action(&"pickup_holdable_item", [KEY_E])
	_ensure_key_action(&"toggle_inventory", [KEY_TAB])


func _ensure_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	for keycode in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


func _ensure_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
