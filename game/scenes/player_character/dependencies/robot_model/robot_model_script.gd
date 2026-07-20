extends Node3D
class_name PlayerCharacterModelBody

const ROTATION_SYNC_SPEED: float = 10.0
@export var anim_lib_prefix := "Robot/"
@export var player: PlayerCharacter = null
@export var animation_player: AnimationPlayer = null
@onready var limbs_and_head: MeshInstance3D = %"Limbs and head"
@onready var cam_face_link: Node3D = %CamFaceLink
@onready var skeleton_3d: Skeleton3D = $RobotArmature/Skeleton3D
@onready var head_top_bone_attachment: BoneAttachment3D = %HeadTopBoneAttachment

var last_state: State
var last_anim := ""
var curr_color := Color.WHITE

func _process(delta: float) -> void:
	var parent := self.get_parent()
	if parent and parent is Node3D:
		top_level = true
		self.global_position = parent.global_position
		
		sync_rotations(delta)
	else:
		top_level = false
		self.position = Vector3.ZERO
	
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority(): return
	if player and animation_player: _update_animations()

func _update_animations() -> void:
	var curr_state: State = player.state_machine.curr_state
	var speed := 1.0
	var blend := 0.2
	var anim := ""
	if last_state != curr_state:
		if curr_state is JumpState:
			if not last_anim.containsn("Jump"):
				if last_anim == "Wallrun":
					anim = "WallJump"
					speed = 1.5
					blend = 0.1
				elif last_anim == "Slide":
					anim = "Jump1"
					speed = 1.5
					blend = 0.3
				elif last_anim == "Crouch":
					anim = "Jump1"
					blend = 0.3
				else:
					anim = "Jump"

	if curr_state is InairState:
		anim = "Inair"
	if curr_state is WalkState:
		anim = "Walk"
	if curr_state is SlideState:
		anim = "Slide"
	if curr_state is RunState:
		anim = "Run"
	if curr_state is WallrunState:
		anim = "Run"
		blend = 2
	if curr_state is CrouchState:
		anim = "Crouch"
	if curr_state is FlyState:
		anim = "Fly"
	if curr_state is IdleState:
		anim = "Idle"
	
	last_anim = anim
	last_state = curr_state
	if not anim: return
	if not anim.begins_with(anim_lib_prefix): anim = anim_lib_prefix + anim
	if animation_player.current_animation != anim or not animation_player.is_playing():
		animation_player.playback_default_blend_time = blend
		animation_player.speed_scale = speed
		animation_player.play(anim,blend,speed)

@rpc("any_peer","call_remote")
func play(anim: String,blend: float, speed: float) -> void:
	animation_player.play(anim,blend,speed)

func sync_rotations(delta: float, reference_node: Node3D = player.cam_holder, velocity: float = ROTATION_SYNC_SPEED) -> void:
	var target_yaw: float
	if player and player.cam_holder and player.cam_holder.is_third_person:
		# Detached free-look: follow body yaw, not camera yaw
		target_yaw = player.character_model.rotation.y if player.character_model else player.body_yaw
	elif reference_node:
		target_yaw = reference_node.rotation.y
	else:
		return
	rotation.y = lerp_angle(rotation.y, target_yaw, velocity * delta)

func _on_peer_connected(_peer: int) -> void:
	_update_mesh_view.call_deferred()

func _on_camera_mode_changed(_is_third_person: bool) -> void:
	_update_mesh_view()

func _ready() -> void:
	_update_mesh_view.call_deferred()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_connected.connect(func(_id: int) -> void: if is_multiplayer_authority(): _set_mesh_color.rpc(curr_color))
	if player and player.cam_holder:
		player.cam_holder.camera_mode_changed.connect(_on_camera_mode_changed)

func _update_mesh_view() -> void:
	var third_person := player != null and player.cam_holder != null and player.cam_holder.is_third_person
	var show_full_body := not is_multiplayer_authority() or third_person
	for child in skeleton_3d.get_children():
		child.visible = false
		if child is MeshInstance3D:
			child.visible = show_full_body or child == limbs_and_head
	var bone_names := [
		"Head",
		"HeadTop",
	]

	for bone_name in bone_names:
		var new_scale := Vector3.ONE if show_full_body else Vector3.ZERO
		var bone_index := skeleton_3d.find_bone(bone_name)
		if bone_index >= 0: skeleton_3d.set_bone_pose_scale(bone_index, new_scale)
	if is_multiplayer_authority():
		_set_mesh_color.rpc(Online.personal_player_data.color)

@rpc("any_peer","call_local")
func _set_mesh_color(color: Color):
	curr_color = color
	for mesh: MeshInstance3D in skeleton_3d.find_children("*", "MeshInstance3D"):
		if mesh.get_parent() != skeleton_3d: continue
		var material: Variant = mesh.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material: StandardMaterial3D = material
			new_material.albedo_color = curr_color
			mesh.set_surface_override_material(0, new_material)
