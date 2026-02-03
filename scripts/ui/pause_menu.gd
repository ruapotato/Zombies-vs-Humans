extends Control
## Pause menu controller


func _ready() -> void:
	visible = false


func show_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	hide_menu()
	GameManager.current_state = GameManager.GameState.PLAYING


func _on_options_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")
	# TODO: Show options menu


func _on_quit_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")

	# Disconnect and return to menu
	GameManager.reset_game()
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
