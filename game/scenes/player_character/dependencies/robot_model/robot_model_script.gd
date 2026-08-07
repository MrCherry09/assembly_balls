extends Node3D
class_name PlayerCharacterModelBody

## Visual body + networked animation. Authority picks clips; all peers play them.
## Use play_synced() / stop_synced() for anything that must appear on other clients —
## including future additive overlays (AnimLayer.ADDITIVE) once an additive_player is assigned.

const ROTATION_SYNC_SPEED: float = 10.0
const AIM_ROTATION_SYNC_SPEED: float = 40.0

enum AnimLayer {
	BASE = 0,
	## Upper-body / gesture overlays — requires additive_player (or AnimationTree later).
	ADDITIVE = 1,
	## Fire-and-forget clips; still networked so everyone sees them.
	ONESHOT = 2,
}

@export var anim_lib_prefix := "Robot/"
@export var player: PlayerCharacter = null
@export var animation_player: AnimationPlayer = null
## Optional second player for additive / overlay clips (leave empty until you add one).
@export var additive_player: AnimationPlayer = null

@export_group("Animations")
@export var anim_idle := "Idle"
@export var anim_walk := "Walk"
@export var anim_run := "Run"
@export var anim_crouch := "Crouch"
@export var anim_jump := "Jump"
@export var anim_jump1 := "Jump1"
@export var anim_inair := "Inair"
@onready var limbs_and_head: MeshInstance3D = %"Limbs and head"
@onready var cam_face_link: Node3D = %CamFaceLink
@onready var skeleton_3d: Skeleton3D = $RobotArmature/Skeleton3D
@onready var head_top_bone_attachment: BoneAttachment3D = %HeadTopBoneAttachment

var last_state: State
var last_anim := ""
var curr_color := Color.WHITE
## Last networked clip per layer: { anim, blend, speed, seek }.
var _layer_state: Dictionary = {}


func _ready() -> void:
	# Manual follow of the interpolated player — don't also run physics interpolation.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_update_mesh_view.call_deferred()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_connected.connect(func(_id: int) -> void: if is_multiplayer_authority(): _set_mesh_color.rpc(curr_color))


func _process(delta: float) -> void:
	var parent := get_parent() as Node3D
	if parent:
		global_position = parent.get_global_transform_interpolated().origin
		sync_rotations(delta)
	else:
		top_level = false
		position = Vector3.ZERO

	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if player and animation_player:
		_update_animations()


func _update_animations() -> void:
	var curr_state: State = player.state_machine.curr_state
	var speed := 1.0
	var blend := 0.2
	var anim := ""
	if last_state != curr_state:
		if curr_state is JumpState:
			if not (last_anim == anim_jump or last_anim == anim_jump1):
				if last_anim == anim_crouch:
					anim = anim_jump1
					blend = 0.3
				else:
					anim = anim_jump

	if curr_state is InairState:
		anim = anim_inair
	if curr_state is WalkState:
		anim = anim_walk
	if curr_state is RunState:
		anim = anim_run
	if curr_state is CrouchState:
		anim = anim_crouch
	if curr_state is IdleState:
		anim = anim_idle

	last_anim = anim
	last_state = curr_state
	if anim.is_empty():
		return
	if not anim.begins_with(anim_lib_prefix):
		anim = anim_lib_prefix + anim
	if animation_player.current_animation != anim or not animation_player.is_playing():
		play_synced(anim, blend, speed, AnimLayer.BASE)


## Authority-only entry point. Remotes receive via RPC. Safe for future additive layers.
func play_synced(anim: String, blend: float = 0.2, speed: float = 1.0, layer: int = AnimLayer.BASE, seek: float = -1.0) -> void:
	if anim.is_empty():
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_anim.rpc(anim, blend, speed, layer, seek)
	else:
		_apply_play(anim, blend, speed, layer, seek)


func stop_synced(layer: int = AnimLayer.BASE) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_stop_anim.rpc(layer)
	else:
		_apply_stop(layer)


@rpc("any_peer", "call_local", "reliable")
func _rpc_play_anim(anim: String, blend: float, speed: float, layer: int, seek: float) -> void:
	if not _rpc_from_this_player_authority():
		return
	_apply_play(anim, blend, speed, layer, seek)


@rpc("any_peer", "call_local", "reliable")
func _rpc_stop_anim(layer: int) -> void:
	if not _rpc_from_this_player_authority():
		return
	_apply_stop(layer)


@rpc("any_peer", "reliable")
func _rpc_sync_anim_state(payload: Array) -> void:
	## Full layer snapshot for late joiners (authority → one peer).
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	for entry in payload:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_apply_play(
			str(entry.get("anim", "")),
			float(entry.get("blend", 0.2)),
			float(entry.get("speed", 1.0)),
			int(entry.get("layer", AnimLayer.BASE)),
			float(entry.get("seek", 0.0))
		)


func _rpc_from_this_player_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender := multiplayer.get_remote_sender_id()
	# call_local on the authority uses sender 0.
	if sender == 0:
		return is_multiplayer_authority()
	return sender == get_multiplayer_authority()


func _player_for_layer(layer: int) -> AnimationPlayer:
	if layer == AnimLayer.ADDITIVE and additive_player != null:
		return additive_player
	return animation_player


func _apply_play(anim: String, blend: float, speed: float, layer: int, seek: float) -> void:
	var ap := _player_for_layer(layer)
	if ap == null or anim.is_empty():
		return
	if not ap.has_animation(anim):
		push_warning("PlayerAnim: missing animation '%s' on %s" % [anim, ap.name])
		return
	ap.playback_default_blend_time = blend
	ap.speed_scale = speed
	ap.play(anim, blend, speed)
	if seek >= 0.0:
		ap.seek(seek, true)
	_layer_state[layer] = {
		"anim": anim,
		"blend": blend,
		"speed": speed,
		"seek": maxf(seek, 0.0),
	}


func _apply_stop(layer: int) -> void:
	var ap := _player_for_layer(layer)
	if ap:
		ap.stop()
	_layer_state.erase(layer)


func _build_anim_sync_payload() -> Array:
	var payload: Array = []
	for layer in _layer_state.keys():
		var state: Dictionary = _layer_state[layer]
		var ap := _player_for_layer(int(layer))
		var seek := float(state.get("seek", 0.0))
		if ap and ap.is_playing():
			seek = ap.current_animation_position
		payload.append({
			"layer": int(layer),
			"anim": str(state.get("anim", "")),
			"blend": float(state.get("blend", 0.2)),
			"speed": float(state.get("speed", 1.0)),
			"seek": seek,
		})
	return payload


## Legacy helper — routes through networked play so remotes stay in sync.
func play(anim: String, blend: float, speed: float) -> void:
	play_synced(anim, blend, speed, AnimLayer.BASE)


func sync_rotations(delta: float, _reference_node: Node3D = null, velocity: float = ROTATION_SYNC_SPEED) -> void:
	if not player: return
	var target_yaw: float = player.character_model.rotation.y if player.character_model else player.body_yaw
	var sync_speed := AIM_ROTATION_SYNC_SPEED if player.cam_holder and player.cam_holder.is_aiming else velocity
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(sync_speed * delta, 0.0, 1.0))


func _on_peer_connected(peer: int) -> void:
	_update_mesh_view.call_deferred()
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		# Defer so the joining peer has finished spawning our player replica.
		call_deferred("_send_anim_state_to_peer", peer)


func _send_anim_state_to_peer(peer: int) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.get_peers().has(peer) and peer != multiplayer.get_unique_id():
		return
	var payload := _build_anim_sync_payload()
	if payload.is_empty():
		return
	_rpc_sync_anim_state.rpc_id(peer, payload)


func _update_mesh_view() -> void:
	# Always show the full body in third person
	for child in skeleton_3d.get_children():
		child.visible = false
		if child is MeshInstance3D:
			child.visible = true
	for bone_name in ["Head", "HeadTop"]:
		var bone_index := skeleton_3d.find_bone(bone_name)
		if bone_index >= 0:
			skeleton_3d.set_bone_pose_scale(bone_index, Vector3.ONE)
	if is_multiplayer_authority():
		_set_mesh_color.rpc(Online.personal_player_data.color)


@rpc("any_peer", "call_local")
func _set_mesh_color(color: Color):
	curr_color = color
	for mesh: MeshInstance3D in skeleton_3d.find_children("*", "MeshInstance3D"):
		if mesh.get_parent() != skeleton_3d: continue
		var material: Variant = mesh.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material: StandardMaterial3D = material
			new_material.albedo_color = curr_color
			mesh.set_surface_override_material(0, new_material)
