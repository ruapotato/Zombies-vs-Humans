extends Node
## NetworkManager - Multiplayer networking singleton
## Handles hosting, joining, player connections, and state synchronization

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal lobby_updated(players: Dictionary)
signal game_starting
signal all_players_loaded

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 6

var peer: ENetMultiplayerPeer = null
var connected_players: Dictionary = {}  # peer_id -> player_info
var players_loaded: Dictionary = {}  # peer_id -> bool

var local_player_info: Dictionary = {
	"name": "Player",
	"color": Color.WHITE
}

var server_info: Dictionary = {
	"name": "Zombies Server",
	"map": "nacht",
	"max_players": MAX_CLIENTS
}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> Error:
	peer = ENetMultiplayerPeer.new()

	var error: Error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("Failed to create server: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer

	local_player_info["name"] = player_name
	connected_players[1] = local_player_info.duplicate()

	print("Server started on port %d" % port)
	lobby_updated.emit(connected_players)

	return OK


func join_game(address: String, port: int = DEFAULT_PORT, player_name: String = "Player") -> Error:
	peer = ENetMultiplayerPeer.new()

	var error: Error = peer.create_client(address, port)
	if error != OK:
		push_error("Failed to create client: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	local_player_info["name"] = player_name

	print("Connecting to %s:%d..." % [address, port])

	return OK


func disconnect_from_game() -> void:
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	connected_players.clear()
	players_loaded.clear()


func is_server() -> bool:
	return multiplayer.is_server()


func is_connected_to_server() -> bool:
	return multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)

	if multiplayer.is_server():
		# Send current lobby state to new player
		rpc_id(peer_id, "_receive_lobby_state", connected_players, server_info)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)

	if peer_id in connected_players:
		var player_info: Dictionary = connected_players[peer_id]
		connected_players.erase(peer_id)
		players_loaded.erase(peer_id)

		player_disconnected.emit(peer_id)
		lobby_updated.emit(connected_players)

		# Notify GameManager
		GameManager.unregister_player(peer_id)


func _on_connected_to_server() -> void:
	print("Connected to server!")
	connection_succeeded.emit()

	# Send our player info to the server
	rpc_id(1, "_register_player", local_player_info)


func _on_connection_failed() -> void:
	print("Connection failed!")
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("Server disconnected!")
	peer = null
	multiplayer.multiplayer_peer = null
	connected_players.clear()
	players_loaded.clear()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _register_player(player_info: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	if not multiplayer.is_server():
		return

	connected_players[sender_id] = player_info.duplicate()

	# Broadcast updated lobby to all players
	rpc("_receive_lobby_state", connected_players, server_info)

	player_connected.emit(sender_id, player_info)


@rpc("authority", "reliable")
func _receive_lobby_state(players: Dictionary, info: Dictionary) -> void:
	connected_players = players.duplicate()
	server_info = info.duplicate()
	lobby_updated.emit(connected_players)


func set_player_name(player_name: String) -> void:
	local_player_info["name"] = player_name

	if is_connected_to_server():
		if multiplayer.is_server():
			connected_players[1]["name"] = player_name
			rpc("_receive_lobby_state", connected_players, server_info)
		else:
			rpc_id(1, "_update_player_info", local_player_info)


func set_player_color(color: Color) -> void:
	local_player_info["color"] = color

	if is_connected_to_server():
		if multiplayer.is_server():
			connected_players[1]["color"] = color
			rpc("_receive_lobby_state", connected_players, server_info)
		else:
			rpc_id(1, "_update_player_info", local_player_info)


@rpc("any_peer", "reliable")
func _update_player_info(player_info: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	if not multiplayer.is_server():
		return

	if sender_id in connected_players:
		connected_players[sender_id] = player_info.duplicate()
		rpc("_receive_lobby_state", connected_players, server_info)


func set_server_map(map_name: String) -> void:
	if not multiplayer.is_server():
		return

	server_info["map"] = map_name
	rpc("_receive_lobby_state", connected_players, server_info)


func start_game() -> void:
	if not multiplayer.is_server():
		return

	if connected_players.size() < 1:
		push_warning("Cannot start game with no players")
		return

	# Reset loaded state
	players_loaded.clear()
	_all_loaded_sent = false
	for peer_id: int in connected_players:
		players_loaded[peer_id] = false

	game_starting.emit()
	rpc("_load_game", server_info["map"])


@rpc("authority", "call_local", "reliable")
func _load_game(_map_name: String) -> void:
	# Load the game scene
	var game_scene_path: String = "res://scenes/main/game.tscn"

	get_tree().change_scene_to_file(game_scene_path)

	# Wait for scene to be ready
	await get_tree().process_frame
	await get_tree().process_frame

	# Notify server we're loaded
	if multiplayer.is_server():
		# Server calls directly (can't RPC to self)
		_on_player_loaded(1)
	else:
		rpc_id(1, "_player_loaded")


@rpc("any_peer", "reliable")
func _player_loaded() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	if not multiplayer.is_server():
		return

	_on_player_loaded(sender_id)


var _load_timeout_timer: SceneTreeTimer = null

func _on_player_loaded(loaded_peer_id: int) -> void:
	players_loaded[loaded_peer_id] = true

	# Start timeout on first player loaded
	if _load_timeout_timer == null:
		_load_timeout_timer = get_tree().create_timer(30.0)
		_load_timeout_timer.timeout.connect(_on_load_timeout)

	_check_all_players_loaded()


var _all_loaded_sent := false

func _check_all_players_loaded() -> void:
	if _all_loaded_sent:
		return

	var all_loaded: bool = true
	for pid: int in connected_players:
		if not players_loaded.get(pid, false):
			all_loaded = false
			break

	if all_loaded:
		_all_loaded_sent = true
		_load_timeout_timer = null
		rpc("_all_players_loaded")


func _on_load_timeout() -> void:
	_load_timeout_timer = null
	if not multiplayer.is_server():
		return

	# Kick players that haven't loaded
	var unloaded: Array[int] = []
	for pid: int in connected_players:
		if not players_loaded.get(pid, false):
			unloaded.append(pid)

	for pid: int in unloaded:
		push_warning("Player %d timed out during loading, removing" % pid)
		connected_players.erase(pid)
		players_loaded.erase(pid)
		player_disconnected.emit(pid)
		if pid != 1:
			peer.disconnect_peer(pid)

	# Proceed with loaded players
	_check_all_players_loaded()


@rpc("authority", "call_local", "reliable")
func _all_players_loaded() -> void:
	all_players_loaded.emit()

	# Small delay then start the game
	await get_tree().create_timer(1.0).timeout

	if multiplayer.is_server():
		GameManager.start_game()


func spawn_player(peer_id: int, spawn_position: Vector3) -> void:
	if not multiplayer.is_server():
		return

	rpc("_spawn_player_at", peer_id, spawn_position)


@rpc("authority", "call_local", "reliable")
func _spawn_player_at(peer_id: int, spawn_position: Vector3) -> void:
	# Prevent duplicate spawns
	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("Players/Player_%d" % peer_id):
		return

	var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()

	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	player.set("player_id", peer_id)

	if peer_id in connected_players:
		player.set("player_name", connected_players[peer_id].get("name", "Player"))
		player.set("player_color", connected_players[peer_id].get("color", Color.WHITE))

	if game_scene and game_scene.has_node("Players"):
		game_scene.get_node("Players").add_child(player)
		player.global_position = spawn_position
	else:
		push_error("[SPAWN] Game scene or Players node not found!")

	GameManager.register_player(peer_id, player)


func despawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	rpc("_despawn_player", peer_id)


@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("Players"):
		var players_node: Node = game_scene.get_node("Players")
		var player_name: String = "Player_%d" % peer_id
		if players_node.has_node(player_name):
			players_node.get_node(player_name).queue_free()

	GameManager.unregister_player(peer_id)


# Chat/messaging system
signal chat_message_received(sender_id: int, sender_name: String, message: String)

func send_chat_message(message: String) -> void:
	var sender_name: String = str(local_player_info.get("name", "Player"))
	rpc("_receive_chat_message", multiplayer.get_unique_id(), sender_name, message)


@rpc("any_peer", "call_local", "reliable")
func _receive_chat_message(sender_id: int, sender_name: String, message: String) -> void:
	# Validate sender matches claimed ID (0 = local call)
	var remote := multiplayer.get_remote_sender_id()
	if remote != 0 and remote != sender_id:
		return
	chat_message_received.emit(sender_id, sender_name, message)


# Kick player (server only)
func kick_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if peer_id == 1:
		push_warning("Cannot kick the host")
		return

	rpc_id(peer_id, "_kicked_from_server")

	# Force disconnect
	await get_tree().create_timer(0.1).timeout
	peer.disconnect_peer(peer_id)


@rpc("authority", "reliable")
func _kicked_from_server() -> void:
	disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
