extends Control
class_name OutlineStencilOverlay

## Fullscreen fake-stencil outline (Sithoid / Leafshade / Mark Raynsford).
## A SubViewport camera sees only OUTLINE_VISUAL_LAYER; this ColorRect edge-detects that mask.

const OUTLINE_VISUAL_LAYER: int = 6 # Editor layer 6 → bit 32
const OUTLINE_LAYER_BIT: int = 1 << (OUTLINE_VISUAL_LAYER - 1)

const OUTLINE_MATERIAL: ShaderMaterial = preload("res://common/shaders/outline_stencil.tres")

@export var source_camera: Camera3D

var _stencil_viewport: SubViewport
var _stencil_camera: Camera3D
var _outline_rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = -20
	_build()
	get_viewport().size_changed.connect(_sync_viewport_size)
	_sync_viewport_size()
	_bind_world()

func _build() -> void:
	_stencil_viewport = SubViewport.new()
	_stencil_viewport.name = "StencilViewport"
	_stencil_viewport.transparent_bg = true
	_stencil_viewport.handle_input_locally = false
	_stencil_viewport.gui_disable_input = true
	_stencil_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stencil_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_stencil_viewport.positional_shadow_atlas_size = 0
	add_child(_stencil_viewport)

	_stencil_camera = Camera3D.new()
	_stencil_camera.name = "StencilCamera"
	_stencil_camera.cull_mask = OUTLINE_LAYER_BIT
	_stencil_camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_stencil_camera.environment = env
	_stencil_viewport.add_child(_stencil_camera)

	_outline_rect = ColorRect.new()
	_outline_rect.name = "OutlineRect"
	_outline_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outline_rect.color = Color.WHITE
	_material = OUTLINE_MATERIAL.duplicate() as ShaderMaterial
	_outline_rect.material = _material
	add_child(_outline_rect)

	# Assign after both nodes are in the tree.
	_material.set_shader_parameter("stencilMask", _stencil_viewport.get_texture())

func _bind_world() -> void:
	var main_vp := get_viewport()
	if main_vp and main_vp.world_3d:
		_stencil_viewport.world_3d = main_vp.world_3d

func _sync_viewport_size() -> void:
	if _stencil_viewport == null:
		return
	var size := get_viewport().get_visible_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return
	_stencil_viewport.size = Vector2i(size)

func _process(_delta: float) -> void:
	if _stencil_camera == null:
		return
	if source_camera == null or not is_instance_valid(source_camera):
		return
	if not source_camera.is_inside_tree():
		return

	if _stencil_viewport.world_3d == null:
		_bind_world()

	_stencil_camera.global_transform = source_camera.global_transform
	_stencil_camera.fov = source_camera.fov
	_stencil_camera.near = source_camera.near
	_stencil_camera.far = source_camera.far
	_stencil_camera.keep_aspect = source_camera.keep_aspect
	_stencil_camera.projection = source_camera.projection
	if source_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_stencil_camera.size = source_camera.size
