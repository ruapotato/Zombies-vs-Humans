extends Control
## Game over screen with stats

@export var final_round: int = 1

@onready var round_label: Label = $VBoxContainer/RoundLabel
@onready var stats_container: VBoxContainer = $VBoxContainer/StatsContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	round_label.text = "You survived to Round %d" % final_round

	_populate_stats()


func _populate_stats() -> void:
	# Clear existing
	for child in stats_container.get_children():
		child.queue_free()

	# Get game time
	var game_time := GameManager.get_game_time()
	var minutes := int(game_time) / 60
	var seconds := int(game_time) % 60
	_add_stat("Time Survived", "%d:%02d" % [minutes, seconds])

	# Total kills
	_add_stat("Total Zombies Killed", str(GameManager.total_zombies_killed))

	# Per-player stats
	for player_id in GameManager.player_stats:
		var stats: Dictionary = GameManager.player_stats[player_id]
		var player_name := "Player %d" % player_id

		if player_id in NetworkManager.connected_players:
			player_name = NetworkManager.connected_players[player_id].get("name", player_name)

		_add_stat("", "")  # Spacer
		_add_stat(player_name, "")
		_add_stat("  Kills", str(stats.get("kills", 0)))
		_add_stat("  Headshots", str(stats.get("headshots", 0)))
		_add_stat("  Revives", str(stats.get("revives", 0)))
		_add_stat("  Downs", str(stats.get("downs", 0)))
		_add_stat("  Points Earned", str(stats.get("points_earned", 0)))


func _add_stat(stat_name: String, stat_value: String) -> void:
	var hbox := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = stat_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var value_label := Label.new()
	value_label.text = stat_value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

	stats_container.add_child(hbox)


func _on_restart_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")

	# Reset and restart
	GameManager.reset_game()

	if NetworkManager.is_server():
		NetworkManager.start_game()


func _on_main_menu_pressed() -> void:
	AudioManager.play_sound_ui("ui_click")

	# Disconnect and return to menu
	GameManager.reset_game()
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
