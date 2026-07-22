extends Node

const MAX_PLAYERS: int = 12

enum ErrorCodes { NO_RESPONSE, SUCCESS, FAILED, CURRENTLY_BUSY, JOIN_FAILED_SAME_OWNER_ID, STEAM_CONNECTION_ERROR }

signal joined_lobby
signal connection_failed
signal steam_lobby_invite_received(lobby_id: int, sender_id: int)
signal lobby_hosting_response(error_code: ErrorCodes)
signal lobby_join_response(error_code: ErrorCodes)
signal player_connected(player_data: PlayerData)
signal player_disconnected(player_data: PlayerData)
signal server_disconnected

var is_busy: bool = false
var is_host: bool = false
var is_joining: bool = false
var steam_lobby_id: int = 0
var players: Dictionary[int, PlayerData]: # Uses multiplayer ids as keys
	get: players.sort(); return players

func players_to_data_dicts() -> Array[Dictionary]: # Returns an array with all the players PlayerData resource in Dictionary format
	var value: Array[Dictionary]
	for player_data: PlayerData in players.values():
		if is_instance_valid(player_data): value.append(player_data.to_dict())
	return value

@onready var personal_player_data: PlayerData: get = _get_personal_player_data # Your PlayerData resource

func _ready() -> void:
	_setup_steam_multiplayer()
	_setup_local_multiplayer()

func _process(_delta: float) -> void:
	if Steam.has_method("run_callbacks"):
		Steam.run_callbacks()
	_process_steam_p2p_packets()

func leave_lobby() -> void:
	is_host = false
	is_busy = false
	is_joining = false
	var had_session := steam_lobby_id != 0 or multiplayer.multiplayer_peer != null
	if steam_lobby_id != 0:
		Steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	# Notify lobby UI / spawn cleanup. Safe to emit even if peer.close() also triggers it.
	if had_session:
		server_disconnected.emit()


func join_address(address: String, port: int = LOCAL_SERVER_PORT) -> ErrorCodes:
	if is_busy: return ErrorCodes.CURRENTLY_BUSY
	is_host = false
	var response: ErrorCodes = ErrorCodes.FAILED
	if is_host or steam_lobby_id != 0: leave_lobby()
	var new_multiplayer_peer := ENetMultiplayerPeer.new()
	var error := new_multiplayer_peer.create_client(address, port)
	is_busy = false
	if error != OK:
		printerr("Failed to join port %s with address: %s" % [port, address])
		return response
	multiplayer.multiplayer_peer = new_multiplayer_peer
	response = ErrorCodes.SUCCESS
	_register_player_data(personal_player_data.to_dict())
	joined_lobby.emit()
	return response

func _on_connected_to_server() -> void: _register_player_data.rpc_id(1,personal_player_data.to_dict()) # Sends a request to the server host to register and sync your PlayerData resource

func _on_connection_failed() -> void:
	is_host = false
	steam_lobby_id = 0
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_peer_disconnected(id: int) -> void: _handle_peer_disconnection(id)

func _on_server_disconnected() -> void:
	is_host = false
	players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

func _get_os_user_name() -> String:
	var username := "Player"
	if OS.has_environment("USER"): username = OS.get_environment("USER")
	elif OS.has_environment("USERNAME"): username = OS.get_environment("USERNAME")
	return username

func _handle_peer_disconnection(peer_id: int) -> void:
	if not players.has(peer_id): return
	var player_data: PlayerData = players[peer_id]
	players.erase(peer_id)
	player_disconnected.emit(player_data)

@rpc("any_peer", "reliable", "call_local")
func _register_player_data(player_data_dict: Dictionary):
	var player_data := PlayerData.from_dict(player_data_dict)
	var mult_id := player_data.multiplayer_id
	if not players.has(mult_id):
		players[player_data.multiplayer_id] = player_data
		player_connected.emit.call_deferred(player_data)
		if is_host:
			# Registers the new player data to the other active players in the lobby
			for peer in multiplayer.get_peers():
				_register_player_data.rpc_id(peer,player_data_dict)
		
			# Syncs the current players data to the player that was just registred
			var sender_id := multiplayer.get_remote_sender_id()
			if sender_id != 0 and sender_id != multiplayer.get_unique_id():
				for data: PlayerData in players.values():
					_register_player_data.rpc_id(sender_id,data.to_dict())

func _get_personal_player_data() -> PlayerData:
	if not personal_player_data:
		personal_player_data = PlayerData.new()
		personal_player_data.steam_id = Steam.getSteamID()
		personal_player_data.display_name = Steam.getPersonaName()
	personal_player_data.multiplayer_id = 0 if not multiplayer.has_multiplayer_peer() else multiplayer.get_unique_id()
	return personal_player_data

#region STEAM P2P MULTIPLAYER
const STEAM_APP_ID: int = 480 # Default for the "Spacewar" game
const STEAM_JOIN_TIMEOUT_SEC := 15.0

func _setup_steam_multiplayer() -> void:
	multiplayer.server_relay = true
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))
	var init_ok: bool = Steam.steamInit(false, STEAM_APP_ID)
	if not init_ok:
		push_warning("Steam.steamInit failed — Steam lobbies will not work. Is Steam running?")
	Steam.allowP2PPacketRelay(true)
	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_joined.connect(_on_steam_lobby_join_response)
	Steam.join_requested.connect(_on_steam_join_requested)

func _on_steam_lobby_created(connection_response: int, lobby_id: int) -> void:
	match connection_response:
		Steam.RESULT_OK:
			steam_lobby_id = lobby_id
			Steam.setLobbyJoinable(lobby_id, true)
			# Prefer lobby-aware host API when available (GodotSteam MultiplayerPeer).
			var peer := _create_steam_peer()
			var host_err: Error = OK
			if peer.has_method("host_with_lobby"):
				host_err = peer.host_with_lobby(lobby_id)
			else:
				host_err = peer.create_host(0)
			if host_err != OK:
				push_error("Steam host peer failed: %s" % host_err)
				peer.close()
				Steam.leaveLobby(lobby_id)
				steam_lobby_id = 0
				lobby_hosting_response.emit(ErrorCodes.FAILED)
				return
			multiplayer.multiplayer_peer = peer
			lobby_hosting_response.emit.call_deferred(ErrorCodes.SUCCESS)
		_:
			lobby_hosting_response.emit(ErrorCodes.FAILED)

func host_steam_lobby() -> ErrorCodes:
	if is_busy:
		return ErrorCodes.CURRENTLY_BUSY
	if steam_lobby_id != 0 or multiplayer.multiplayer_peer != null:
		leave_lobby()
	is_host = false
	is_busy = true
	var error_response := ErrorCodes.NO_RESPONSE
	# Invisible: joinable by ID/invite, not listed in public lobby browser.
	Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, MAX_PLAYERS)
	var hosting_response: ErrorCodes = await lobby_hosting_response
	error_response = hosting_response
	match hosting_response:
		ErrorCodes.SUCCESS:
			is_host = true
			_register_player_data(personal_player_data.to_dict())
			joined_lobby.emit()
		_:
			if steam_lobby_id != 0:
				Steam.leaveLobby(steam_lobby_id)
				steam_lobby_id = 0
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
	is_busy = false
	return error_response

func _on_steam_join_requested(lobby_id: int, _steam_id: int) -> void:
	join_steam_lobby(lobby_id)

func join_steam_lobby(lobby_id: int = 0) -> ErrorCodes:
	if is_busy:
		return ErrorCodes.CURRENTLY_BUSY
	if lobby_id == 0:
		push_error("join_steam_lobby called with lobby_id 0")
		return ErrorCodes.FAILED
	is_busy = true
	is_joining = true
	is_host = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if steam_lobby_id != 0 and steam_lobby_id != lobby_id:
		Steam.leaveLobby(steam_lobby_id)
		players.clear()
	steam_lobby_id = lobby_id
	Steam.joinLobby(lobby_id)

	var got_response := false
	var error: ErrorCodes = ErrorCodes.NO_RESPONSE
	var on_response := func(code: ErrorCodes) -> void:
		if got_response:
			return
		got_response = true
		error = code
	lobby_join_response.connect(on_response, CONNECT_ONE_SHOT)

	# Includes Steam lobby callback + P2P handshake inside _complete_steam_client_join.
	var elapsed := 0.0
	while not got_response and elapsed < STEAM_JOIN_TIMEOUT_SEC * 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not got_response:
		if lobby_join_response.is_connected(on_response):
			lobby_join_response.disconnect(on_response)
		error = ErrorCodes.STEAM_CONNECTION_ERROR
		push_error("Steam lobby join timed out for lobby %s" % lobby_id)

	is_joining = false
	is_busy = false
	if error != ErrorCodes.SUCCESS:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		if steam_lobby_id != 0:
			Steam.leaveLobby(steam_lobby_id)
			steam_lobby_id = 0
		return error

	joined_lobby.emit()
	return error

func _on_steam_lobby_join_response(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# Host createLobby also emits lobby_joined — ignore unless this peer is joining.
	if not is_joining:
		return
	_complete_steam_client_join.call_deferred(lobby_id, response)

func _complete_steam_client_join(lobby_id: int, response: int) -> void:
	if not is_joining:
		return
	# lobby_joined uses ChatRoomEnterResponse (success == 1).
	if response != 1:
		push_error("Steam lobby_joined failed response=%s lobby=%s" % [response, lobby_id])
		lobby_join_response.emit(ErrorCodes.STEAM_CONNECTION_ERROR)
		return

	var lobby_owner_id: int = Steam.getLobbyOwner(lobby_id)
	if lobby_owner_id == 0:
		push_error("Steam getLobbyOwner returned 0 for lobby %s" % lobby_id)
		lobby_join_response.emit(ErrorCodes.STEAM_CONNECTION_ERROR)
		return
	if lobby_owner_id == Steam.getSteamID():
		lobby_join_response.emit(ErrorCodes.JOIN_FAILED_SAME_OWNER_ID)
		return

	var peer := _create_steam_peer()
	var err: Error = OK
	if peer.has_method("connect_to_lobby"):
		err = peer.connect_to_lobby(lobby_id)
	else:
		err = peer.create_client(lobby_owner_id, 0)
	if err != OK:
		push_error("Steam client peer failed: %s (owner=%s lobby=%s)" % [err, lobby_owner_id, lobby_id])
		peer.close()
		Steam.leaveLobby(lobby_id)
		lobby_join_response.emit(ErrorCodes.FAILED)
		return

	steam_lobby_id = lobby_id
	multiplayer.multiplayer_peer = peer

	# create_client returns before the P2P session is up — wait for connection.
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		var connected := false
		var failed := false
		var on_ok := func() -> void: connected = true
		var on_fail := func() -> void: failed = true
		if not multiplayer.connected_to_server.is_connected(on_ok):
			multiplayer.connected_to_server.connect(on_ok, CONNECT_ONE_SHOT)
		if not multiplayer.connection_failed.is_connected(on_fail):
			multiplayer.connection_failed.connect(on_fail, CONNECT_ONE_SHOT)
		var wait := 0.0
		while not connected and not failed and wait < STEAM_JOIN_TIMEOUT_SEC:
			await get_tree().process_frame
			wait += get_process_delta_time()
			if multiplayer.multiplayer_peer == null:
				failed = true
				break
			if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				connected = true
				break
		if not connected:
			push_error("Steam P2P connection never established to owner %s" % lobby_owner_id)
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
			Steam.leaveLobby(lobby_id)
			lobby_join_response.emit(ErrorCodes.STEAM_CONNECTION_ERROR)
			return

	# Host registration happens in _on_connected_to_server via rpc_id(1, ...).
	# Trigger it if the signal already fired before we connected the waiter.
	if multiplayer.get_unique_id() != 1:
		_register_player_data.rpc_id(1, personal_player_data.to_dict())
	lobby_join_response.emit(ErrorCodes.SUCCESS)

func _create_steam_peer() -> SteamMultiplayerPeer:
	var new_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	new_peer.server_relay = true
	return new_peer

func _process_steam_p2p_packets() -> void:
	var packet_size: int = Steam.getAvailableP2PPacketSize(0)
	if packet_size == 0:
		return
	var packet: Dictionary = Steam.readP2PPacket(packet_size, 0)
	var packet_data: Variant = bytes_to_var(packet["data"])
	_handle_incoming_packet(packet_data)

#endregion

#region LOCAL MULTIPLAYER

const LOCAL_SERVER_ADDRESS: String = "127.0.0.1"
const LOCAL_SERVER_PORT: int = 8080

signal _local_host_check_response(has_host: bool)

var _check_timer: Timer

func _setup_local_multiplayer() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server) # Only emitted on clients

func host_local_lobby() -> ErrorCodes:
	if is_busy: return ErrorCodes.CURRENTLY_BUSY
	if steam_lobby_id != 0 or multiplayer.multiplayer_peer != null:
		leave_lobby()
	is_busy = true
	is_host = true
	
	var new_peer := ENetMultiplayerPeer.new()
	var error := new_peer.create_server(LOCAL_SERVER_PORT, MAX_PLAYERS)
	match error:
		OK:
			multiplayer.multiplayer_peer = new_peer
			_register_player_data(personal_player_data.to_dict())
			is_busy = false
			return ErrorCodes.SUCCESS
		_:
			is_host = false
			is_busy = false
			return ErrorCodes.FAILED

func join_local_lobby() -> ErrorCodes:
	if is_busy: return ErrorCodes.CURRENTLY_BUSY
	is_busy = true
	var has_local_host := await check_if_host_exists(LOCAL_SERVER_ADDRESS,LOCAL_SERVER_PORT)
	is_busy = false
	if not has_local_host: return ErrorCodes.FAILED
	else: return join_address(LOCAL_SERVER_ADDRESS, LOCAL_SERVER_PORT)

func check_if_host_exists(ip_address: String, port: int) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip_address, port)
	if error != OK: return false
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_host_found)
	multiplayer.connection_failed.connect(_on_host_missing)
	_check_timer = Timer.new()
	add_child(_check_timer)
	_check_timer.wait_time = 2.0
	_check_timer.one_shot = true
	_check_timer.timeout.connect(_on_host_missing)
	_check_timer.start()
	var has_host: bool = await _local_host_check_response
	peer.close()
	_local_cleanup()
	return has_host

func _on_host_found(): _local_host_check_response.emit(true)

func _on_host_missing(): _local_host_check_response.emit(false)

func _local_cleanup():
	if is_instance_valid(_check_timer): _check_timer.queue_free()
	if multiplayer.connected_to_server.is_connected(_on_host_found):
		multiplayer.connected_to_server.disconnect(_on_host_found)
	if multiplayer.connection_failed.is_connected(_on_host_missing):
		multiplayer.connection_failed.disconnect(_on_host_missing)
	multiplayer.multiplayer_peer = null
#endregion


#region DATA PAYLOAD LOGIC
class DataPayload extends Resource:
	enum Types { UNDEFINED, STEAM_LOBBY_INVITE }
	
	func _init() -> void: header = "DATA_PAYLOAD"
	
	var header: String:
		set(value): if header != value: header = value; _update_content("header",value)
	var lobby_invite_address: String:
		set(value): if lobby_invite_address != value: lobby_invite_address = value; _update_content("lobby_invite_address",value)
	var type: Types = Types.UNDEFINED:
		set(value): if type != value: type = value; _update_content("type",value)
	var steam_target_id: int = 0:
		set(value): if steam_target_id != value: steam_target_id = value; _update_content("steam_target_id",value)
	var steam_sender_id: int = 0:
		set(value): if steam_sender_id != value: steam_sender_id = value; _update_content("steam_sender_id",value)
	var steam_send_type: Steam.P2PSend = Steam.P2PSend.P2P_SEND_RELIABLE:
		set(value): if steam_send_type != value: steam_send_type = value; _update_content("steam_send_type",value)
	var steam_packet_channel: int = 0:
		set(value): if steam_packet_channel != value: steam_packet_channel = value; _update_content("steam_packet_channel",value)

	var content: Dictionary
	var packet_data: PackedByteArray: get = _get_packet_data
	
	func _get_packet_data() -> PackedByteArray:
		var data: Dictionary = {}
		for key in content:
			data.set(key,str(content.get(key)))
		return var_to_bytes(data)
	
	func _update_content(content_key: String,value: Variant) -> bool:
		if not value: content.erase(content_key)
		else: content.set(content_key,value)
		return true
	
	static func create_steam_invite_payload(invite_address: Variant, steam_id_to_invite: int, invite_send_type := Steam.P2PSend.P2P_SEND_RELIABLE, invite_packet_channel: int = 0) -> DataPayload:
		invite_address = str(invite_address)
		if not invite_address: return
		var invite_payload := DataPayload.new()
		invite_payload.type = Types.STEAM_LOBBY_INVITE
		invite_payload.lobby_invite_address = invite_address
		invite_payload.steam_target_id = steam_id_to_invite
		invite_payload.steam_sender_id = Steam.getSteamID()
		invite_payload.steam_send_type = invite_send_type
		invite_payload.steam_packet_channel = invite_packet_channel
		return invite_payload

	static func from_dict(dict: Dictionary) -> DataPayload:
		# Instantiates a DataPayload and configures it based on the given dictionary.
		var new_payload := DataPayload.new()
		for key in dict:
			var value: Variant = dict.get(key)
			if value == null: continue
			new_payload.set(key,value)
		return new_payload

	func send() -> bool: return Online._send_steam_data_payload(self)

func _handle_incoming_packet(data: Dictionary) -> void:
	match data.get("header"):
		"DATA_PAYLOAD": _handle_payload_received(DataPayload.from_dict(data))

func _handle_payload_received(payload: DataPayload) -> void:
	match payload.type:
		payload.Types.STEAM_LOBBY_INVITE:
			var invite_steam_lobby_id: int = int(payload.lobby_invite_address)
			var sender_id: int = payload.steam_sender_id
			steam_lobby_invite_received.emit(invite_steam_lobby_id, sender_id)

func _send_steam_data_payload(payload: DataPayload) -> bool:
	var target_steam_id: int = payload.steam_target_id
	for player: PlayerData in players.values():
		if player.steam_id == target_steam_id:
			var target_persona_name := Steam.getFriendPersonaName(player.steam_id)
			print_rich("[color=red][b]Lobby Error:[/b][/color] Failed to invite '%s' (Already in lobby)." % target_persona_name)
			return false
	var success: bool = Steam.sendP2PPacket(target_steam_id, payload.packet_data, payload.steam_send_type, payload.steam_packet_channel)
	if payload.type == payload.Types.STEAM_LOBBY_INVITE:
		Steam.inviteUserToLobby(int(payload.lobby_invite_address), payload.steam_target_id) # This triggers the direct message invite in the Steam App
	return success
#endregion
