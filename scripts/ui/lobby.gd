extends Control
## Lobby screen controller

@onready var player_list: VBoxContainer = $MarginContainer/VBoxContainer/Content/PlayersPanel/VBox/PlayerList
@onready var map_select: OptionButton = $MarginContainer/VBoxContainer/Content/SettingsPanel/VBox/MapSelect
@onready var server_info: Label = $MarginContainer/VBoxContainer/Content/SettingsPanel/VBox/ServerInfo
@onready var start_button: Button = $MarginContainer/VBoxContainer/Footer/StartButton
@onready var ready_check: CheckBox = $MarginContainer/VBoxContainer/Content/SettingsPanel/VBox/ReadyCheck

var player_ready_states: Dictionary = {}


func _ready() -> void:
	NetworkManager.lobby_updated.connect(_on_lobby_updated)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_setup_map_list()
	_update_ui()


func _setup_map_list() -> void:
	map_select.clear()

	var maps := MapManager.get_available_maps()
	print("Available maps: ", maps.size())
	for m in maps:
		print("  - ", m.get("name", "?"), " / ", m.get("display_name", "?"))

	if maps.is_empty():
		# Add default map
		map_select.add_item("Nacht der Untoten", 0)
		map_select.set_item_metadata(0, "nacht")
		print("No maps found, using default nacht")
	else:
		for i in range(maps.size()):
			var map_data: Dictionary = maps[i]
			map_select.add_item(map_data.get("display_name", map_data["name"]), i)
			map_select.set_item_metadata(i, map_data["name"])

	# Only host can change map
	map_select.disabled = not NetworkManager.is_server()

	# Set initial map to match what's displayed (first item)
	if NetworkManager.is_server() and map_select.item_count > 0:
		var initial_map: String = map_select.get_item_metadata(0)
		NetworkManager.set_server_map(initial_map)
		print("Initial map set to: ", initial_map)


func _update_ui() -> void:
	# Update start button visibility (host only)
	start_button.visible = NetworkManager.is_server()

	# Update server info
	if NetworkManager.is_server():
		server_info.text = "Hosting on port %d" % NetworkManager.DEFAULT_PORT
	else:
		server_info.text = "Connected to server"

	# Update player list
	_refresh_player_list()


func _refresh_player_list() -> void:
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	# Add player entries
	for peer_id in NetworkManager.connected_players:
		var player_info: Dictionary = NetworkManager.connected_players[peer_id]
		var entry := _create_player_entry(peer_id, player_info)
		player_list.add_child(entry)


func _create_player_entry(peer_id: int, player_info: Dictionary) -> HBoxContainer:
	var entry := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = player_info.get("name", "Player")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if peer_id == 1:
		name_label.text += " (Host)"

	if peer_id == multiplayer.get_unique_id():
		name_label.text += " (You)"

	entry.add_child(name_label)

	# Ready indicator
	var ready_label := Label.new()
	var is_ready: bool = player_ready_states.get(peer_id, false)
	ready_label.text = "Ready" if is_ready else "Not Ready"
	ready_label.modulate = Color.GREEN if is_ready else Color.RED
	entry.add_child(ready_label)

	# Kick button (host only, can't kick self)
	if NetworkManager.is_server() and peer_id != 1:
		var kick_button := Button.new()
		kick_button.text = "Kick"
		kick_button.pressed.connect(_on_kick_player.bind(peer_id))
		entry.add_child(kick_button)

	return entry


func _on_lobby_updated(players: Dictionary) -> void:
	_refresh_player_list()


func _on_player_connected(peer_id: int, player_info: Dictionary) -> void:
	AudioManager.play_sound_ui("ui_click")
	_refresh_player_list()


func _on_player_disconnected(peer_id: int) -> void:
	player_ready_states.erase(peer_id)
	_refresh_player_list()


func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_back_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_back")
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_map_selected(index: int) -> void:
	if not NetworkManager.is_server():
		return

	var map_name: String = map_select.get_item_metadata(index)
	print("Map selected: index=%d, name=%s" % [index, map_name])
	NetworkManager.set_server_map(map_name)


func _on_ready_toggled(toggled_on: bool) -> void:
	var peer_id := multiplayer.get_unique_id()
	player_ready_states[peer_id] = toggled_on

	# Sync ready state
	rpc("_sync_ready_state", peer_id, toggled_on)


@rpc("any_peer", "call_local", "reliable")
func _sync_ready_state(peer_id: int, is_ready: bool) -> void:
	player_ready_states[peer_id] = is_ready
	_refresh_player_list()


func _on_start_button_pressed() -> void:
	if not NetworkManager.is_server():
		return

	AudioManager.play_sound_ui("ui_click")
	NetworkManager.start_game()


func _on_kick_player(peer_id: int) -> void:
	if not NetworkManager.is_server():
		return

	NetworkManager.kick_player(peer_id)
