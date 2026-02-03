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
