extends Control
## Main menu controller

@onready var host_dialog: Window = $HostDialog
@onready var join_dialog: Window = $JoinDialog
@onready var host_name_input: LineEdit = $HostDialog/VBoxContainer/NameInput
@onready var host_port_input: LineEdit = $HostDialog/VBoxContainer/PortInput
@onready var join_name_input: LineEdit = $JoinDialog/VBoxContainer/NameInput
@onready var join_ip_input: LineEdit = $JoinDialog/VBoxContainer/IPInput


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Set default names
	host_name_input.text = "Host"
	join_name_input.text = "Player"

	# Handle CLI arguments for automated launch
	_handle_cli_args()


func _handle_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	var arg_dict := {}

	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg.begins_with("--"):
			var key := arg.substr(2)
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				arg_dict[key] = args[i + 1]
				i += 2
			else:
				arg_dict[key] = ""
				i += 1
		else:
			i += 1

	if arg_dict.is_empty():
		return

	var port := int(arg_dict.get("port", "7777"))
	var player_name: String = arg_dict.get("name", "")
	var map_name: String = arg_dict.get("map", "nacht")

	if "server" in arg_dict or "host" in arg_dict:
		if player_name.is_empty():
			player_name = "Host"
		print("[CLI] Hosting on port %d as '%s' (map: %s)" % [port, player_name, map_name])
		var error := NetworkManager.host_game(port, player_name)
		if error == OK:
			NetworkManager.set_server_map(map_name)
			if "autostart" in arg_dict:
				# Skip lobby, start game immediately once someone joins (or solo)
				print("[CLI] Autostart enabled - going to lobby")
			get_tree().change_scene_to_file("res://scenes/main/lobby.tscn")
		else:
			push_error("[CLI] Failed to host: %s" % error_string(error))

	elif "join" in arg_dict or "client" in arg_dict:
		var ip: String = arg_dict.get("join", arg_dict.get("client", "127.0.0.1"))
		if ip.is_empty():
			ip = "127.0.0.1"
		if player_name.is_empty():
			player_name = "Player_%d" % randi_range(1, 999)
		print("[CLI] Joining %s:%d as '%s'" % [ip, port, player_name])
		var error := NetworkManager.join_game(ip, port, player_name)
		if error != OK:
			push_error("[CLI] Failed to join: %s" % error_string(error))


func _on_host_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	host_dialog.popup_centered()


func _on_join_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	join_dialog.popup_centered()


func _on_options_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	# TODO: Options menu
	pass


func _on_quit_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	get_tree().quit()


func _on_start_host_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")

	var port := int(host_port_input.text) if host_port_input.text.is_valid_int() else 7777
	var player_name := host_name_input.text if host_name_input.text.length() > 0 else "Host"

	var error := NetworkManager.host_game(port, player_name)

	if error == OK:
		host_dialog.hide()
		get_tree().change_scene_to_file("res://scenes/main/lobby.tscn")
	else:
		# Show error
		push_error("Failed to host game: %s" % error_string(error))


func _on_connect_button_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")

	var ip := join_ip_input.text if join_ip_input.text.length() > 0 else "127.0.0.1"
	var player_name := join_name_input.text if join_name_input.text.length() > 0 else "Player"

	var error := NetworkManager.join_game(ip, 7777, player_name)

	if error != OK:
		push_error("Failed to join game: %s" % error_string(error))


func _on_connection_succeeded() -> void:
	join_dialog.hide()
	get_tree().change_scene_to_file("res://scenes/main/lobby.tscn")


func _on_connection_failed() -> void:
	AudioManager.play_sound_ui("denied")
	push_warning("Connection failed!")
	# Could show error dialog here


func _on_host_cancel_pressed() -> void:
	AudioManager.play_sound_ui("ui_back")
	host_dialog.hide()


func _on_join_cancel_pressed() -> void:
	AudioManager.play_sound_ui("ui_back")
	join_dialog.hide()


func _on_host_dialog_close_requested() -> void:
	host_dialog.hide()


func _on_join_dialog_close_requested() -> void:
	join_dialog.hide()
